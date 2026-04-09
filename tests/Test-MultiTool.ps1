#!/usr/bin/env pwsh
# Multi-tool turn tests — simulates the Matrix agent's tool-calling loop
# without a live Ollama connection. Feeds synthetic "model messages" through
# the real Invoke-MatrixToolchain / Invoke-MatrixTool pipeline and verifies
# correct dispatch, argument marshalling, and result formatting.

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Test-Framework.ps1")

# Bootstrap the agent libs (same path as Matrix.ps1)
$global:MatrixRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $global:MatrixRoot "lib" "Logger.ps1")
. (Join-Path $global:MatrixRoot "lib" "ToolManager.ps1")
. (Join-Path $global:MatrixRoot "lib" "Network.ps1")
. (Join-Path $global:MatrixRoot "lib" "Context.ps1")

# Silence log output during tests
function Write-MatrixLog { param($Message, $Level = "INFO") }

# ── Helper: build a fake Ollama tool-call message ────────────────────────────

function New-ToolCallMessage {
    param(
        [string]$ToolName,
        [hashtable]$Arguments,
        [string]$TextContent = ""
    )
    $argsJson = $Arguments | ConvertTo-Json -Compress
    return [PSCustomObject]@{
        role       = "assistant"
        content    = $TextContent
        tool_calls = @(
            [PSCustomObject]@{
                function = [PSCustomObject]@{
                    name      = $ToolName
                    arguments = $argsJson
                }
            }
        )
    }
}

function New-MultiToolMessage {
    param([array]$Calls)  # each: @{ Tool; Args }
    $toolCalls = $Calls | ForEach-Object {
        [PSCustomObject]@{
            function = [PSCustomObject]@{
                name      = $_.Tool
                arguments = ($_.Args | ConvertTo-Json -Compress)
            }
        }
    }
    return [PSCustomObject]@{
        role       = "assistant"
        content    = ""
        tool_calls = $toolCalls
    }
}

# ── Single-tool dispatch tests ────────────────────────────────────────────────

Start-Suite "Tool dispatch — single calls"

# Get-Time: no args
$msg = New-ToolCallMessage -ToolName "Get-Time" -Arguments @{}
$res = Invoke-MatrixToolchain -Message $msg
Assert-True   "HasTools = true"              $res.HasTools
Assert-Equal  "one tool result"  1           $res.ToolResults.Count
Assert-True   "result is valid JSON"         ($null -ne ($res.ToolResults[0].content | ConvertFrom-Json -EA SilentlyContinue))
Assert-True   "result role = tool"           ($res.ToolResults[0].role -eq "tool")

# Invoke-Math with int arg (tests type coercion — must NOT receive "2" as string)
$msg2 = New-ToolCallMessage -ToolName "Invoke-Math" -Arguments @{ Expression = "10 + 5" }
$res2 = Invoke-MatrixToolchain -Message $msg2
$resultObj = $res2.ToolResults[0].content | ConvertFrom-Json
Assert-True   "Invoke-Math 10+5 = 15"        ($resultObj.Result -eq 15)

# Convert-Units: number arg coercion
$msg3 = New-ToolCallMessage -ToolName "Convert-Units" -Arguments @{ Value = 0; From = "c"; To = "f" }
$res3 = Invoke-MatrixToolchain -Message $msg3
$obj3 = $res3.ToolResults[0].content | ConvertFrom-Json
Assert-Equal  "0°C = 32°F"  32  $obj3.Result

# Read-File: string arg
$tmpFile = [IO.Path]::GetTempFileName()
"Test content line" | Set-Content $tmpFile -Encoding UTF8
$msg4 = New-ToolCallMessage -ToolName "Read-File" -Arguments @{ Path = $tmpFile }
$res4 = Invoke-MatrixToolchain -Message $msg4
$obj4 = $res4.ToolResults[0].content | ConvertFrom-Json
Assert-True   "Read-File content present"    ($obj4.Content -match "Test content line")
Remove-Item $tmpFile -Force -EA SilentlyContinue

# Unknown tool: should not throw, should return error string
$msgBad = New-ToolCallMessage -ToolName "NonExistentTool_XYZ" -Arguments @{}
$resBad = Invoke-MatrixToolchain -Message $msgBad
Assert-True   "Unknown tool returns result"  ($resBad.ToolResults.Count -eq 1)
Assert-True   "Unknown tool error message"   ($resBad.ToolResults[0].content -match "not found|error")

# ── Multi-tool dispatch (parallel calls in one message) ───────────────────────

Start-Suite "Tool dispatch — multi-tool message"

$multiMsg = New-MultiToolMessage -Calls @(
    @{ Tool = "Get-Time";    Args = @{} },
    @{ Tool = "Invoke-Math"; Args = @{ Expression = "7 * 6" } }
)
$multiRes = Invoke-MatrixToolchain -Message $multiMsg
Assert-True   "both tools called"             ($multiRes.HasTools)
Assert-Equal  "two tool results"  2           $multiRes.ToolResults.Count
Assert-Equal  "two tools listed"  2           $multiRes.ToolsCalled.Count

$mathResult = $multiRes.ToolResults[1].content | ConvertFrom-Json
Assert-Equal  "7*6 = 42"  42  $mathResult.Result

# Three tools in one message
$triMsg = New-MultiToolMessage -Calls @(
    @{ Tool = "Get-Time";          Args = @{} },
    @{ Tool = "Get-SystemInfo";    Args = @{} },
    @{ Tool = "Invoke-Math";       Args = @{ Expression = "2 * 2" } }
)
$triRes = Invoke-MatrixToolchain -Message $triMsg
Assert-Equal  "three tool results"  3  $triRes.ToolResults.Count
$sysObj = $triRes.ToolResults[1].content | ConvertFrom-Json
Assert-True   "SystemInfo has OS field"       ($null -ne $sysObj.OS)

# ── Type coercion edge cases ──────────────────────────────────────────────────

Start-Suite "Argument type coercion"

# Boolean argument
$tmpFile2 = [IO.Path]::GetTempFileName()
"existing" | Set-Content $tmpFile2 -Encoding UTF8
$msgBool = New-ToolCallMessage -ToolName "Write-FileContent" -Arguments @{
    Path      = $tmpFile2
    Content   = "replaced"
    Overwrite = $true   # boolean, not string "true"
}
$resBool = Invoke-MatrixToolchain -Message $msgBool
$boolObj = $resBool.ToolResults[0].content | ConvertFrom-Json
Assert-True   "bool=true Overwrite worked"   ($null -eq $boolObj.error)
Remove-Item $tmpFile2 -Force -EA SilentlyContinue

# Integer argument for Top param
$msgInt = New-ToolCallMessage -ToolName "Get-ProcessList" -Arguments @{ Top = 3 }
$resInt = Invoke-MatrixToolchain -Message $msgInt
$intObj = $resInt.ToolResults[0].content | ConvertFrom-Json
Assert-True   "int Top=3 respected"          ($intObj.TotalShown -le 3)

# ── Tool schema discovery ─────────────────────────────────────────────────────

Start-Suite "Tool schema discovery"

$tools = Get-MatrixTools
$toolNames = $tools | ForEach-Object { $_.function.name }

# Every .ps1 in tools/ should appear in the schema
$toolFiles = Get-ChildItem (Join-Path $global:MatrixRoot "tools") -Filter "*.ps1" |
             Select-Object -ExpandProperty BaseName

foreach ($name in $toolFiles) {
    Assert-True "[$name] in schema"  ($name -in $toolNames)
}

Assert-True "schema count matches files"  ($tools.Count -eq $toolFiles.Count)

# Every schema entry should have required fields
foreach ($t in $tools) {
    Assert-True "[$($t.function.name)] type=function"      ($t.type -eq "function")
    Assert-True "[$($t.function.name)] has description"    (-not [string]::IsNullOrWhiteSpace($t.function.description))
    Assert-True "[$($t.function.name)] parameters.type"   ($t.function.parameters.type -eq "object")
}

# ── Cache invalidation ────────────────────────────────────────────────────────

Start-Suite "Tool cache invalidation"

# First call — populates cache
$tools1 = Get-MatrixTools
Assert-True  "initial load works"  ($tools1.Count -gt 0)

# Second call — should be a cache hit (same object reference for identical content)
$tools2 = Get-MatrixTools
Assert-Equal "cache hit same count"  $tools1.Count  $tools2.Count

# Force invalidation by clearing mtime table, then add a temp tool
$script:ToolCacheMtime = @{}
$script:ToolCache      = $null
$tmpTool = Join-Path $global:MatrixRoot "tools" "_TestTempTool_$(Get-Random).ps1"
@"
<#
.SYNOPSIS
Temporary test tool.
#>
[CmdletBinding()]
param()
return @{ ok = `$true } | ConvertTo-Json -Compress
"@ | Set-Content $tmpTool -Encoding UTF8

$tools3 = Get-MatrixTools
Assert-Equal "new tool detected after cache clear"  ($tools1.Count + 1)  $tools3.Count

Remove-Item $tmpTool -Force -EA SilentlyContinue

# After removal, force rebuild and verify count returns to original
$script:ToolCacheMtime = @{}
$script:ToolCache      = $null
$tools4 = Get-MatrixTools
Assert-Equal "count restored after temp tool removed"  $tools1.Count  $tools4.Count

# ── Summary ───────────────────────────────────────────────────────────────────
$failed = Show-TestSummary
exit $failed

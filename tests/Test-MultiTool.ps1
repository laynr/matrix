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

# ── Get-DynamicNumCtx ─────────────────────────────────────────────────────────
# These tests exist specifically to prevent the bug where tool schema tokens
# were not counted, causing num_ctx < prompt size and Ollama 400 errors.

Start-Suite "Dynamic num_ctx"

$realTools = Get-MatrixTools

# Override pin
$pinned = Get-DynamicNumCtx -Messages @() -Tools @() -Override 16384
Assert-Equal "Override pin respected"  16384  $pinned

# No tools, no messages — should return minimum 4096
$bare = Get-DynamicNumCtx -Messages @() -Tools @()
Assert-True  "bare minimum >= 4096"  ($bare -ge 4096)

# With 15 real tools: tool schemas alone are ~1500+ tokens; result must exceed
# the raw token estimate of the tool JSON so the prompt fits in the context
$toolJson   = $realTools | ConvertTo-Json -Depth 10 -Compress
$toolTokens = [math]::Ceiling($toolJson.Length / 3.5)
$withTools  = Get-DynamicNumCtx -Messages @() -Tools $realTools
Assert-True  "num_ctx > tool token estimate"   ($withTools -gt $toolTokens)
Assert-True  "num_ctx rounded to 512 boundary" ($withTools % 512 -eq 0)
Assert-True  "num_ctx <= MaxCtx"               ($withTools -le 131072)

# With tools + messages: must be larger than tools-only
$msgs = @(
    @{ role = "system"; content = "You are Matrix." },
    @{ role = "user";   content = "What tools do you have?" }
)
$withBoth = Get-DynamicNumCtx -Messages $msgs -Tools $realTools
Assert-True  "messages + tools > tools alone"  ($withBoth -ge $withTools)

# Grows with conversation: a long conversation should produce a larger num_ctx
$longMsgs = 1..20 | ForEach-Object { @{ role = "user"; content = ("word " * 200) } }
$short = Get-DynamicNumCtx -Messages $msgs     -Tools $realTools
$long  = Get-DynamicNumCtx -Messages $longMsgs -Tools $realTools
Assert-True  "longer conversation → larger num_ctx"  ($long -gt $short)

# ── HttpClient overload sanity ────────────────────────────────────────────────
# Guards against the bug where PostAsync was called with HttpCompletionOption
# (which doesn't exist) instead of SendAsync (which does). This crashed at
# runtime but was invisible to schema-only tests.

Start-Suite "HttpClient streaming overload"

# PostAsync has NO overload accepting HttpCompletionOption — confirm .NET agrees
$postAsyncBadOverload = [System.Net.Http.HttpClient].GetMethods() | Where-Object {
    $_.Name -eq 'PostAsync' -and
    ($_.GetParameters() | Where-Object { $_.ParameterType -eq [System.Net.Http.HttpCompletionOption] })
}
Assert-True  "PostAsync has no HttpCompletionOption overload" ($null -eq $postAsyncBadOverload)

# SendAsync DOES have a 2-param overload (HttpRequestMessage, HttpCompletionOption)
$sendAsyncGoodOverload = [System.Net.Http.HttpClient].GetMethods() | Where-Object {
    $_.Name -eq 'SendAsync' -and
    $_.GetParameters().Count -ge 2 -and
    $_.GetParameters()[1].ParameterType -eq [System.Net.Http.HttpCompletionOption]
}
Assert-True  "SendAsync(msg, HttpCompletionOption) overload exists" ($null -ne $sendAsyncGoodOverload)

# Static check: Network.ps1 must not call PostAsync with HttpCompletionOption
$networkSrc = Get-Content (Join-Path $global:MatrixRoot "lib" "Network.ps1") -Raw
Assert-True  "Network.ps1 does not call PostAsync with HttpCompletionOption" `
    ($networkSrc -notmatch 'PostAsync\s*\([^)]*HttpCompletionOption')

# Static check: Network.ps1 must use SendAsync for streaming
Assert-True  "Network.ps1 uses SendAsync for streaming" `
    ($networkSrc -match 'SendAsync\s*\(')

# ── Tool selection — relevance scoring ───────────────────────────────────────

Start-Suite "Tool selection — relevance scoring"

$null = Get-MatrixTools   # ensure cache is warm

# Weather query → Get-Weather should score highest
$weatherSel = Select-MatrixTools -UserMessage "What is the weather like in London today?" -MaxCount 5
Assert-True "weather query selects Get-Weather" `
    ($null -ne ($weatherSel | Where-Object { $_.function.name -eq "Get-Weather" }))

# File reading → Read-File should score highest
$fileSel = Select-MatrixTools -UserMessage "Read the contents of /tmp/notes.txt for me" -MaxCount 5
Assert-True "file query selects Read-File" `
    ($null -ne ($fileSel | Where-Object { $_.function.name -eq "Read-File" }))

# Math query → Invoke-Math should be included
$mathSel = Select-MatrixTools -UserMessage "Calculate 42 * 7 math expression" -MaxCount 5
Assert-True "math query selects Invoke-Math" `
    ($null -ne ($mathSel | Where-Object { $_.function.name -eq "Invoke-Math" }))

# MaxCount cap is respected
$cappedSel = Select-MatrixTools -UserMessage "tell me anything" -MaxCount 3 -MaxTokenBudget 999999
Assert-True "MaxCount=3 returns at most 3 tools" ($cappedSel.Count -le 3)

# Token budget enforced — budget of 1 token = 3 chars, no full schema fits
$budgetSel = Select-MatrixTools -UserMessage "anything" -MaxTokenBudget 1 -MaxCount 999
Assert-True "MaxTokenBudget=1 returns 0 tools (no schema fits)" ($budgetSel.Count -eq 0)

# CoreTools always included even when message has no relevant keywords
$coreSel = Select-MatrixTools -UserMessage "xyzzy plugh nothing matches" -MaxCount 5 -CoreTools @("Get-Time")
Assert-True "CoreTools always included regardless of query" `
    ($null -ne ($coreSel | Where-Object { $_.function.name -eq "Get-Time" }))

# Empty message — no crash, still returns tools up to cap
$emptySel = Select-MatrixTools -UserMessage "" -MaxCount 5
Assert-True "empty message returns up to MaxCount tools" ($emptySel.Count -gt 0 -and $emptySel.Count -le 5)

# Empty cache — returns empty array, no crash
Reset-ToolCache
$cachelessSel = Select-MatrixTools -UserMessage "weather file math"
Assert-True "empty cache returns empty array" ($cachelessSel.Count -eq 0)
$null = Get-MatrixTools   # restore cache for subsequent suites

# ── Tool catalog ──────────────────────────────────────────────────────────────

Start-Suite "Tool catalog"

$null = Get-MatrixTools

$catalog = Get-MatrixToolCatalog
Assert-True "catalog is non-empty string" (-not [string]::IsNullOrWhiteSpace($catalog))

$catalogLines = $catalog -split "`n"
$allTools     = Get-MatrixTools
Assert-Equal "catalog has one line per tool" $allTools.Count $catalogLines.Count

# Every tool name must appear in the catalog
foreach ($t in $allTools) {
    Assert-True "[$($t.function.name)] appears in catalog" ($catalog -match [regex]::Escape($t.function.name))
}

# Lines should be in "Name: description" format
Assert-True "catalog lines use 'Name: description' format" ($catalogLines[0] -match '^\S+: .+')

# Empty cache → empty catalog, no crash
Reset-ToolCache
$emptyCatalog = Get-MatrixToolCatalog
Assert-True "empty cache returns empty catalog" ([string]::IsNullOrWhiteSpace($emptyCatalog))
$null = Get-MatrixTools   # restore

# ── Model auto-selection (Select-MatrixModel) ─────────────────────────────────
# Guards against: selecting a model that isn't pulled in Ollama (produces 404),
# RAM detection failures, and tier ordering bugs.

Start-Suite "Model auto-selection"

. (Join-Path $global:MatrixRoot "lib" "Config.ps1")

$fakeTiers = @{
    ModelTiers = @(
        @{ MinRamGB = 20; Model = "qwen3:8b"    }
        @{ MinRamGB = 12; Model = "qwen2.5:7b"  }
        @{ MinRamGB = 6;  Model = "qwen3:4b"    }
        @{ MinRamGB = 0;  Model = "llama3.2:3b" }
    )
}

# RAM fits top tier AND top-tier model is installed
function Get-SystemRamGB { return 24 }
function Get-OllamaModels { return @("qwen3:8b:latest") }
Assert-Equal "24 GB + qwen3:8b installed → qwen3:8b" "qwen3:8b" (Select-MatrixModel -Config $fakeTiers)

# RAM fits top tier but top-tier model NOT installed — fall to next installed tier
function Get-SystemRamGB { return 24 }
function Get-OllamaModels { return @("qwen2.5:7b:latest") }
Assert-Equal "qwen3:8b missing → falls to qwen2.5:7b" "qwen2.5:7b" (Select-MatrixModel -Config $fakeTiers)

# RAM only fits the 4b slot and it's installed
function Get-SystemRamGB { return 8 }
function Get-OllamaModels { return @("qwen3:4b:latest") }
Assert-Equal "8 GB + qwen3:4b installed → qwen3:4b" "qwen3:4b" (Select-MatrixModel -Config $fakeTiers)

# Ollama not reachable (empty list) — trust RAM fit, don't 404-proof-loop forever
function Get-SystemRamGB { return 16 }
function Get-OllamaModels { return @() }
Assert-Equal "Ollama unreachable → trust RAM (qwen2.5:7b)" "qwen2.5:7b" (Select-MatrixModel -Config $fakeTiers)

# No tier model is installed but something unrecognised is — return it rather than 404
function Get-SystemRamGB { return 16 }
function Get-OllamaModels { return @("some-random-model:latest") }
Assert-Equal "no tier model → first installed" "some-random-model:latest" (Select-MatrixModel -Config $fakeTiers)

# Very low RAM — only the MinRamGB=0 tier qualifies; model is installed
function Get-SystemRamGB { return 2 }
function Get-OllamaModels { return @("llama3.2:3b:latest") }
Assert-Equal "2 GB + llama3.2:3b installed → llama3.2:3b" "llama3.2:3b" (Select-MatrixModel -Config $fakeTiers)

# Get-SystemRamGB returns a positive integer on this platform
function Get-SystemRamGB {
    try {
        if ($IsWindows) {
            return [math]::Round((Get-CimInstance Win32_ComputerSystem -EA Stop).TotalPhysicalMemory / 1GB)
        } elseif ($IsMacOS) {
            return [math]::Round([long](& sysctl -n hw.memsize) / 1GB)
        } else {
            $kb = [long](((Get-Content /proc/meminfo -EA Stop) -match '^MemTotal:') -replace '[^\d]')
            return [math]::Round($kb / 1MB)
        }
    } catch { return 8 }
}
$detectedRam = Get-SystemRamGB
Assert-True "Get-SystemRamGB returns positive number" ($detectedRam -gt 0)

# ── Disk schema cache ─────────────────────────────────────────────────────────
# Guards against: cache not being written, stale cache serving wrong schemas,
# Reset-ToolCache not clearing the disk file.

Start-Suite "Disk schema cache"

$cachePath = Join-Path $global:MatrixRoot "tools" ".schema-cache.json"

# Warm the cache — populates both memory and disk
Reset-ToolCache
$tools = Get-MatrixTools
Assert-True  "cache file created after Get-MatrixTools"  (Test-Path $cachePath)

$cached = Get-Content $cachePath -Raw | ConvertFrom-Json
Assert-True  "cache has fingerprint"                     ($null -ne $cached.fingerprint)
Assert-True  "cache has schemas"                         ($cached.schemas -and $cached.schemas.Count -gt 0)
Assert-Equal "cached count matches live count"           $tools.Count  $cached.schemas.Count

# Disk cache hit: clear in-memory cache but leave disk cache; reload must succeed
$script:ToolCache      = $null
$script:ToolCacheMtime = @{}
$reloaded = Get-MatrixTools
Assert-Equal "disk cache hit returns correct count"      $tools.Count  $reloaded.Count

# Reset clears the disk file
Reset-ToolCache
Assert-True  "Reset-ToolCache deletes disk cache"        (-not (Test-Path $cachePath))

# Rebuild recreates the disk file
$null = Get-MatrixTools
Assert-True  "rebuild recreates disk cache file"         (Test-Path $cachePath)

# Disk cache is invalidated when a new tool is added
$script:ToolCache      = $null
$script:ToolCacheMtime = @{}
$tmpTool = Join-Path $global:MatrixRoot "tools" "_CacheTest_$(Get-Random).ps1"
@"
<#
.SYNOPSIS
Temporary cache invalidation test tool.
#>
[CmdletBinding()]
param()
return @{ ok = `$true } | ConvertTo-Json -Compress
"@ | Set-Content $tmpTool -Encoding UTF8
$afterAdd = Get-MatrixTools
Assert-Equal "new tool invalidates disk cache and is discovered"  ($tools.Count + 1)  $afterAdd.Count
Remove-Item $tmpTool -Force -EA SilentlyContinue

# Rebuild after removal restores original count
Reset-ToolCache
$afterRemove = Get-MatrixTools
Assert-Equal "count restored after temp tool removed"  $tools.Count  $afterRemove.Count

# ── Load-ToolSchemaCache edge cases ──────────────────────────────────────────

Start-Suite "Load-ToolSchemaCache edge cases"

$cachePath2 = Join-Path $global:MatrixRoot "tools" ".schema-cache.json"
$origCache  = if (Test-Path $cachePath2) { Get-Content $cachePath2 -Raw } else { $null }

try {
    # Corrupt JSON → returns $null
    "{ this is not valid json !!!" | Set-Content $cachePath2 -Encoding UTF8
    $result = Load-ToolSchemaCache -Fingerprint @{ "toolA" = "2024-01-01T00:00:00" }
    Assert-True "Corrupt JSON returns null" ($null -eq $result)

    # Missing fingerprint property → returns $null
    @{ schemas = @() } | ConvertTo-Json | Set-Content $cachePath2 -Encoding UTF8
    $result = Load-ToolSchemaCache -Fingerprint @{ "toolA" = "2024-01-01T00:00:00" }
    Assert-True "Missing fingerprint returns null" ($null -eq $result)

    # Tool count mismatch (caller has 2 keys, disk has 1) → returns $null
    @{ fingerprint = @{ toolA = "t1" }; schemas = @() } | ConvertTo-Json -Depth 5 | Set-Content $cachePath2 -Encoding UTF8
    $result = Load-ToolSchemaCache -Fingerprint @{ toolA = "t1"; toolB = "t2" }
    Assert-True "Count mismatch returns null" ($null -eq $result)

    # Mtime value mismatch → returns $null
    @{ fingerprint = @{ toolA = "OLD-MTIME" }; schemas = @() } | ConvertTo-Json -Depth 5 | Set-Content $cachePath2 -Encoding UTF8
    $result = Load-ToolSchemaCache -Fingerprint @{ toolA = "NEW-MTIME" }
    Assert-True "Mtime mismatch returns null" ($null -eq $result)
} finally {
    if ($null -ne $origCache) { $origCache | Set-Content $cachePath2 -Encoding UTF8 -NoNewline }
    elseif (Test-Path $cachePath2) { Remove-Item $cachePath2 -Force -EA SilentlyContinue }
}

# ── Reset-ToolCache state verification ───────────────────────────────────────

Start-Suite "Reset-ToolCache — state verification"

$null = Get-MatrixTools   # warm cache
Reset-ToolCache
Assert-True  "ToolCache is null after Reset" ($null -eq $script:ToolCache)
Assert-Equal "ToolCacheMtime is empty after Reset" 0 $script:ToolCacheMtime.Count

# Second Reset with no disk file must not throw
Reset-ToolCache
Assert-True "Second Reset-ToolCache does not throw" $true

$null = Get-MatrixTools   # restore

# ── RunspacePool ISS sanity ───────────────────────────────────────────────────
# Guards against the [void] bug where Add() return values polluted the function
# output, causing Get-MatrixRunspacePool to return Object[] instead of a pool.

Start-Suite "RunspacePool ISS type safety"

$pool  = Get-MatrixRunspacePool
$pool2 = Get-MatrixRunspacePool
Assert-True "Get-MatrixRunspacePool returns a RunspacePool (not Object[])" `
    ($pool -is [System.Management.Automation.Runspaces.RunspacePool])
Assert-Equal "RunspacePool state is Opened" "Opened" $pool.RunspacePoolStateInfo.State.ToString()
Assert-True  "Second call returns same pool object" ([object]::ReferenceEquals($pool, $pool2))
Assert-Equal "Pool MinRunspaces = 1" 1 $pool.GetMinRunspaces()
Assert-Equal "Pool MaxRunspaces = 8" 8 $pool.GetMaxRunspaces()

# Dispatch a real tool through the ISS pool to confirm libs pre-loaded correctly
$issMsg = New-ToolCallMessage -ToolName "Get-Time" -Arguments @{}
$issRes  = Invoke-MatrixToolchain -Message $issMsg
Assert-True  "ISS pool dispatches tools correctly"  $issRes.HasTools
Assert-True  "ISS pool tool result is valid JSON" `
    ($null -ne ($issRes.ToolResults[0].content | ConvertFrom-Json -EA SilentlyContinue))

# ── Summary ───────────────────────────────────────────────────────────────────
$failed = Show-TestSummary
exit $failed

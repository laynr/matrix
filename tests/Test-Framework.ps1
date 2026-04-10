#!/usr/bin/env pwsh
# Matrix Test Framework — shared helpers used by all test scripts.
# Provides: Assert-*, Invoke-Tool, Test-ToolSchema, and result tracking.

$script:Results = @()
$script:CurrentSuite = ""

# ── Result tracking ───────────────────────────────────────────────────────────

function Start-Suite {
    param([string]$Name)
    $script:CurrentSuite = $Name
    Write-Host ""
    Write-Host "  [$Name]" -ForegroundColor Cyan
}

function Add-Result {
    param([string]$Test, [bool]$Passed, [string]$Detail = "")
    $script:Results += [PSCustomObject]@{
        Suite  = $script:CurrentSuite
        Test   = $Test
        Passed = $Passed
        Detail = $Detail
    }
    if ($Passed) {
        Write-Host "    [PASS] $Test" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] $Test$(if ($Detail) { " — $Detail" })" -ForegroundColor Red
    }
}

function Get-TestResults { return $script:Results }

function Show-TestSummary {
    $total  = $script:Results.Count
    $passed = ($script:Results | Where-Object Passed).Count
    $failed = $total - $passed

    Write-Host ""
    Write-Host ("─" * 50)
    Write-Host "  Results: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

    if ($failed -gt 0) {
        Write-Host ""
        Write-Host "  Failed tests:" -ForegroundColor Red
        $script:Results | Where-Object { -not $_.Passed } | ForEach-Object {
            Write-Host "    [$($_.Suite)] $($_.Test)" -ForegroundColor Red
            if ($_.Detail) { Write-Host "      $($_.Detail)" -ForegroundColor DarkGray }
        }
    }
    Write-Host ""
    return $failed
}

# ── Assertions ────────────────────────────────────────────────────────────────

function Assert-NotNull {
    param([string]$Test, $Value, [string]$Because = "")
    $detail = if ($Because) { $Because } elseif ($null -eq $Value) { "value was null" } else { "" }
    Add-Result -Test $Test -Passed ($null -ne $Value) -Detail $detail
}

function Assert-True {
    param([string]$Test, [bool]$Condition, [string]$Because = "")
    Add-Result -Test $Test -Passed $Condition -Detail $Because
}

function Assert-Equal {
    param([string]$Test, $Expected, $Actual, [string]$Because = "")
    $passed = "$Expected" -eq "$Actual"
    $detail = if (-not $passed) { "expected '$Expected', got '$Actual'" } else { $Because }
    Add-Result -Test $Test -Passed $passed -Detail $detail
}

function Assert-HasKey {
    param([string]$Test, $Object, [string]$Key)
    $keyExists = $null -ne $Object -and (
        ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Key)) -or
        ($Object.PSObject.Properties.Name -contains $Key)
    )
    Add-Result -Test $Test -Passed $keyExists -Detail $(if (-not $keyExists) { "key '$Key' missing" })
}

function Assert-NoError {
    param([string]$Test, $JsonOutput)
    try {
        $obj = $JsonOutput | ConvertFrom-Json -EA Stop
        $passed = -not $obj.error
        $detail = if ($obj.error) { "tool returned error: $($obj.error)" } else { "" }
        Add-Result -Test $Test -Passed $passed -Detail $detail
    } catch {
        Add-Result -Test $Test -Passed $false -Detail "output is not valid JSON: $JsonOutput"
    }
}

function Assert-ValidJson {
    param([string]$Test, $Output)
    try {
        $null = $Output | ConvertFrom-Json -EA Stop
        Add-Result -Test $Test -Passed $true
    } catch {
        Add-Result -Test $Test -Passed $false -Detail "not valid JSON: $($Output | Select-Object -First 1)"
    }
}

# ── Tool invocation helpers ───────────────────────────────────────────────────

# Direct invocation — bypasses the agent, calls the .ps1 tool script directly.
function Invoke-Tool {
    param(
        [string]$ToolName,
        [hashtable]$ToolArgs = @{}
    )
    $toolPath = Join-Path $PSScriptRoot ".." "tools" "$ToolName.ps1"
    if (-not (Test-Path $toolPath)) {
        throw "Tool not found: $toolPath"
    }
    if ($ToolArgs.Count -gt 0) {
        return & $toolPath @ToolArgs
    } else {
        return & $toolPath
    }
}

# Parse JSON output from a tool and return the object (or throw on invalid JSON).
function Get-ToolOutput {
    param([string]$JsonOutput)
    return $JsonOutput | ConvertFrom-Json
}

# ── Schema validation ─────────────────────────────────────────────────────────

# Verifies that a tool's .ps1 file produces a valid Ollama-compatible schema.
function Test-ToolSchema {
    param([string]$ToolName)

    $toolsDir = Join-Path $PSScriptRoot ".." "tools"
    $toolPath = Join-Path $toolsDir "$ToolName.ps1"

    if (-not (Test-Path $toolPath)) {
        Add-Result -Test "$ToolName schema" -Passed $false -Detail "file not found"
        return
    }

    try {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $toolPath, [ref]$tokens, [ref]$errors)

        $help = $ast.GetHelpContent()
        Assert-True "$ToolName has .SYNOPSIS" `
            ($null -ne $help -and -not [string]::IsNullOrWhiteSpace($help.Synopsis))

        $hasCmdletBinding = $ast.ParamBlock -and (
            $ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
        )
        Assert-True "$ToolName has [CmdletBinding()]" ([bool]$hasCmdletBinding)

        # Every mandatory param should have a .PARAMETER doc entry
        if ($ast.ParamBlock) {
            foreach ($p in $ast.ParamBlock.Parameters) {
                $pName = $p.Name.VariablePath.UserPath
                $hasMandatory = $p.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.Language.AttributeAst] -and
                    $_.TypeName.Name -eq 'Parameter' -and
                    ($_.NamedArguments | Where-Object {
                        $_.ArgumentName -eq 'Mandatory' -and
                        ($_.ExpressionOmitted -or $_.Argument.Extent.Text -match '^\$?true$')
                    })
                }
                if ($hasMandatory -and $help -and $help.Parameters) {
                    Assert-True "$ToolName.$pName has .PARAMETER doc" `
                        ($null -ne $help.Parameters[$pName.ToUpper()])
                }
            }
        }
    } catch {
        Add-Result -Test "$ToolName schema" -Passed $false -Detail $_
    }
}

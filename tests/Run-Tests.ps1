#!/usr/bin/env pwsh
# Matrix Test Runner — runs all tests and reports coverage.
# Exit code 0 = all pass; non-zero = failure count (usable in CI).
#
# Usage:
#   pwsh tests/Run-Tests.ps1               # full suite
#   pwsh tests/Run-Tests.ps1 -SchemaOnly   # schemas only, no network calls
#   pwsh tests/Run-Tests.ps1 -Suite Tools  # single suite

param(
    [switch]$SchemaOnly,           # skip tests requiring network
    [ValidateSet("All","Tools","MultiTool")]
    [string]$Suite = "All"
)

$ErrorActionPreference = "Stop"
$start = Get-Date

Write-Host ""
Write-Host "  ╔══════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║      M A T R I X   T E S T S     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Suite      : $Suite"
Write-Host "  SchemaOnly : $SchemaOnly"
Write-Host "  Platform   : $(if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' })"
Write-Host "  pwsh       : $($PSVersionTable.PSVersion)"
Write-Host ""

$totalFailed = 0
$suiteResults = @()

function Run-Suite {
    param([string]$Name, [string]$Script, [hashtable]$Params = @{})

    Write-Host ("─" * 50)
    Write-Host "  Running: $Name" -ForegroundColor White

    $args = @()
    if ($Params.SchemaOnly) { $args += "-SchemaOnly" }

    try {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $Script @args
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Host "  [ERROR] Suite '$Name' threw: $_" -ForegroundColor Red
        $exitCode = 1
    }

    $script:suiteResults += [PSCustomObject]@{
        Suite    = $Name
        ExitCode = $exitCode
    }
    $script:totalFailed += $exitCode
}

$testsDir = $PSScriptRoot

if ($Suite -in @("All","Tools")) {
    Run-Suite "Tool Unit Tests" (Join-Path $testsDir "Test-Tools.ps1") @{ SchemaOnly = $SchemaOnly }
}
if ($Suite -in @("All","MultiTool")) {
    Run-Suite "Multi-Tool Integration" (Join-Path $testsDir "Test-MultiTool.ps1")
}

# ── Coverage report ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("─" * 50)
Write-Host "  Coverage Report" -ForegroundColor Cyan

$toolsDir  = Join-Path $PSScriptRoot ".." "tools"
$toolFiles = @(Get-ChildItem $toolsDir -Filter "*.ps1" | Select-Object -ExpandProperty BaseName)

Write-Host "  Tools in tools/ : $($toolFiles.Count)"
Write-Host ""
foreach ($tool in ($toolFiles | Sort-Object)) {
    Write-Host "    $tool" -ForegroundColor DarkGray
}
Write-Host ""

# ── Final result ──────────────────────────────────────────────────────────────
$elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)

Write-Host ("─" * 50)
if ($totalFailed -eq 0) {
    Write-Host "  ALL TESTS PASSED  ($elapsed s)" -ForegroundColor Green
} else {
    Write-Host "  $totalFailed SUITE(S) FAILED  ($elapsed s)" -ForegroundColor Red
    Write-Host ""
    $suiteResults | Where-Object { $_.ExitCode -ne 0 } | ForEach-Object {
        Write-Host "    FAILED: $($_.Suite)" -ForegroundColor Red
    }
}
Write-Host ""

exit $totalFailed

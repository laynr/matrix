#!/usr/bin/env pwsh
# Install / Uninstall integration tests.
# Verifies the full lifecycle in the correct order:
#   1. Uninstall (pre-install) — must be idempotent / graceful when nothing exists
#   2. Install                 — deploy files, write config, create launcher
#   3. Smoke test              — installed libs load, tools are discoverable
#   4. Uninstall (post-install)— removes everything the install laid down
#
# ORDER MATTERS — this suite must run BEFORE Tool and MultiTool tests.
# Run-Tests.ps1 enforces this automatically.

param([switch]$SchemaOnly)   # accepted for runner compatibility; all install tests are local

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Test-Framework.ps1")

$platform        = if ($IsWindows) { "Windows" } elseif ($IsMacOS) { "macOS" } else { "Linux" }
$sourceRoot      = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$testHome        = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-install-$PID"
$testBin         = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-bin-$PID"
$uninstallerPath = Join-Path $sourceRoot "uninstall.pwsh.ps1"

# Launcher path is platform-specific (mirrors install.pwsh.ps1 Step 5)
$script:launcher = if ($IsWindows) { Join-Path $testBin "matrix.ps1" } else { Join-Path $testBin "matrix" }

Write-Host "  Platform    : $platform"         -ForegroundColor DarkGray
Write-Host "  Source      : $sourceRoot"       -ForegroundColor DarkGray
Write-Host "  Install dir : $testHome"         -ForegroundColor DarkGray
Write-Host "  Bin dir     : $testBin"          -ForegroundColor DarkGray

# Helper: run the uninstaller pointed at our test dirs
function Invoke-TestUninstaller {
    $env:MATRIX_HOME    = $testHome
    $env:MATRIX_BIN_DIR = $testBin
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $uninstallerPath -Quiet 2>&1 | Out-Null
        return $LASTEXITCODE
    } finally {
        Remove-Item Env:MATRIX_HOME    -ErrorAction SilentlyContinue
        Remove-Item Env:MATRIX_BIN_DIR -ErrorAction SilentlyContinue
    }
}

# ── 1. Pre-install uninstall — must succeed even when nothing exists ───────────
Start-Suite "Pre-install cleanup [$platform]"

Assert-True "uninstall.pwsh.ps1 exists" (Test-Path $uninstallerPath)

try {
    # Neither $testHome nor $testBin exist yet — uninstaller must handle this gracefully
    $exitCode = Invoke-TestUninstaller
    Assert-True "uninstaller is idempotent on missing dirs" ($exitCode -eq 0)
} catch {
    Add-Result -Test "uninstaller runs cleanly on missing dirs" -Passed $false -Detail "$_"
}

Assert-True "install dir absent before install" (-not (Test-Path $testHome))
Assert-True "launcher absent before install"    (-not (Test-Path $script:launcher))

# ── 2. Install ─────────────────────────────────────────────────────────────────
Start-Suite "Install [$platform]"

try {
    New-Item -ItemType Directory -Path $testHome -Force | Out-Null
    New-Item -ItemType Directory -Path $testBin  -Force | Out-Null

    # Mirror what install.pwsh.ps1 does: copy source tree to install dir
    Copy-Item (Join-Path $sourceRoot "Matrix.ps1") $testHome -Force
    Copy-Item (Join-Path $sourceRoot "lib")   (Join-Path $testHome "lib")   -Recurse -Force
    Copy-Item (Join-Path $sourceRoot "tools") (Join-Path $testHome "tools") -Recurse -Force

    # Write default config.json
    @{
        Provider     = "Ollama"
        Model        = "gemma4:latest"
        Endpoint     = "http://localhost:11434/api/chat"
        SystemPrompt = "You are Matrix, a helpful AI agent. Use the tools available to you when they are needed to answer the user. Be concise and direct."
    } | ConvertTo-Json | Set-Content (Join-Path $testHome "config.json") -Encoding UTF8

    # Create platform-specific launcher (mirrors install.pwsh.ps1 Step 5)
    $matrixScript = Join-Path $testHome "Matrix.ps1"
    if ($IsWindows) {
        "& `"$matrixScript`" @args" | Set-Content $script:launcher -Encoding UTF8
    } else {
        @"
#!/usr/bin/env sh
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$matrixScript" "`$@"
"@ | Set-Content $script:launcher -Encoding UTF8
        chmod +x $script:launcher
    }
} catch {
    Add-Result -Test "Install setup" -Passed $false -Detail "$_"
    $failed = Show-TestSummary
    exit $failed
}

# Layout assertions
Assert-True  "install dir created"            (Test-Path $testHome)
Assert-True  "Matrix.ps1 present"             (Test-Path (Join-Path $testHome "Matrix.ps1"))
Assert-True  "lib/Network.ps1 present"        (Test-Path (Join-Path $testHome "lib" "Network.ps1"))
Assert-True  "lib/Context.ps1 present"        (Test-Path (Join-Path $testHome "lib" "Context.ps1"))
Assert-True  "lib/CLI.ps1 present"            (Test-Path (Join-Path $testHome "lib" "CLI.ps1"))
Assert-True  "lib/ToolManager.ps1 present"    (Test-Path (Join-Path $testHome "lib" "ToolManager.ps1"))
Assert-True  "tools/ present"                 (Test-Path (Join-Path $testHome "tools"))
Assert-True  "config.json present"            (Test-Path (Join-Path $testHome "config.json"))
Assert-True  "launcher created"               (Test-Path $script:launcher)

if (-not $IsWindows) {
    $executable = & sh -c "[ -x '$($script:launcher)' ] && echo 1 || echo 0" 2>/dev/null
    Assert-True "launcher is executable" ($executable.Trim() -eq "1")
}

$srcCount  = @(Get-ChildItem (Join-Path $sourceRoot "tools") -Filter "*.ps1").Count
$instCount = @(Get-ChildItem (Join-Path $testHome "tools")   -Filter "*.ps1").Count
Assert-Equal "all $srcCount tools installed" $srcCount $instCount

try {
    $cfg = Get-Content (Join-Path $testHome "config.json") -Raw | ConvertFrom-Json
    Assert-True "config.Model set"        (-not [string]::IsNullOrWhiteSpace($cfg.Model))
    Assert-True "config.Endpoint set"     (-not [string]::IsNullOrWhiteSpace($cfg.Endpoint))
    Assert-True "config.SystemPrompt set" (-not [string]::IsNullOrWhiteSpace($cfg.SystemPrompt))
} catch {
    Add-Result -Test "config.json is valid JSON" -Passed $false -Detail "$_"
}

# ── 3. Smoke test — installed libs load and tools are discoverable ─────────────
Start-Suite "Installed Matrix — smoke test [$platform]"

try {
    $safeHome = $testHome -replace "'", "''"
    $result = pwsh -NoProfile -ExecutionPolicy Bypass -Command "
        `$global:MatrixRoot = '$safeHome'
        . (Join-Path `$global:MatrixRoot 'lib' 'Logger.ps1')
        . (Join-Path `$global:MatrixRoot 'lib' 'ToolManager.ps1')
        function Write-MatrixLog { param(`$Message, `$Level = 'INFO') }
        `$tools = Get-MatrixTools
        `$tools.Count
    " 2>&1

    $toolCount = [int]($result | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1)
    Assert-True  "installed libs load without error"       ($toolCount -gt 0)
    Assert-Equal "installed tool count matches source"     $srcCount $toolCount
} catch {
    Add-Result -Test "Smoke test" -Passed $false -Detail "$_"
}

# ── 4. Uninstall — removes everything the install laid down ───────────────────
Start-Suite "Uninstall [$platform]"

try {
    $exitCode = Invoke-TestUninstaller
    Assert-True "uninstaller exits cleanly" ($exitCode -eq 0)
} catch {
    Add-Result -Test "Uninstaller ran without exception" -Passed $false -Detail "$_"
}

Assert-True "install dir gone" (-not (Test-Path $testHome))
Assert-True "launcher gone"    (-not (Test-Path $script:launcher))

# The bin dir is a system path in real use and is left in place by the uninstaller.
# Clean it up here since it was a temp dir created solely for this test run.
Remove-Item $testBin -Recurse -Force -ErrorAction SilentlyContinue
Assert-True "bin dir gone"     (-not (Test-Path $testBin))

# ── Summary ───────────────────────────────────────────────────────────────────
$failed = Show-TestSummary
exit $failed

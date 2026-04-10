#!/usr/bin/env pwsh
# Install / Uninstall integration tests.
# Actually executes install.pwsh.ps1 and uninstall.pwsh.ps1 with mocked
# dependencies — no network, no real Ollama, no shell-profile modification.
#
# Environment hooks used (all defined in install.pwsh.ps1):
#   MATRIX_HOME         — install directory
#   MATRIX_BIN_DIR      — launcher directory
#   MATRIX_MODEL        — model name
#   MATRIX_RELEASE_ZIP  — local zip path (skips Invoke-WebRequest)
#   MATRIX_NO_PROFILE   — skip shell profile modification
#   MATRIX_NO_LAUNCH    — skip final Matrix launch
#
# ORDER MATTERS — this suite must run BEFORE Tool and MultiTool tests.

param([switch]$SchemaOnly)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Test-Framework.ps1")

$platform        = if ($IsWindows) { "Windows" } elseif ($IsMacOS) { "macOS" } else { "Linux" }
$sourceRoot      = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$installerPath   = Join-Path $sourceRoot "install.pwsh.ps1"
$uninstallerPath = Join-Path $sourceRoot "uninstall.pwsh.ps1"
$testHome        = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-install-$PID"
$testBin         = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-bin-$PID"
$stubBin         = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-stubs-$PID"

$script:launcher = if ($IsWindows) { Join-Path $testBin "matrix.ps1" } else { Join-Path $testBin "matrix" }

Write-Host "  Platform    : $platform"         -ForegroundColor DarkGray
Write-Host "  Source      : $sourceRoot"       -ForegroundColor DarkGray
Write-Host "  Install dir : $testHome"         -ForegroundColor DarkGray
Write-Host "  Bin dir     : $testBin"          -ForegroundColor DarkGray

# ── Helpers ────────────────────────────────────────────────────────────────────
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

function New-StubOllama {
    # Creates a fake ollama that reports itself present and model available
    New-Item -ItemType Directory -Path $stubBin -Force | Out-Null
    if ($IsWindows) {
        @'
@echo off
if "%1"=="--version" echo ollama version 0.0.0-stub
if "%1"=="list"      echo stub-model:latest    abc123    1.0 GB    1 hour ago
if "%1"=="pull"      echo pulling stub model...
exit /b 0
'@ | Set-Content (Join-Path $stubBin "ollama.cmd") -Encoding ASCII
    } else {
        @'
#!/usr/bin/env sh
case "$1" in
    --version) printf "ollama version 0.0.0-stub\n" ;;
    list)      printf "NAME                 ID        SIZE    MODIFIED\nstub-model:latest    abc123    1.0 GB  1 hour ago\n" ;;
    pull)      printf "pulling stub model...\n" ;;
    serve)     exit 0 ;;
esac
exit 0
'@ | Set-Content (Join-Path $stubBin "ollama") -Encoding UTF8
        chmod +x (Join-Path $stubBin "ollama")
    }
    $sep       = [IO.Path]::PathSeparator
    $env:PATH  = "$stubBin$sep$env:PATH"
}

function New-TestReleaseZip {
    # Build a local zip from the source tree — mirrors what publish.yml produces
    $stagingDir = Join-Path ([IO.Path]::GetTempPath()) "matrix-zip-stage-$PID"
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    Copy-Item (Join-Path $sourceRoot "Matrix.ps1") $stagingDir -Force
    Copy-Item (Join-Path $sourceRoot "lib")   (Join-Path $stagingDir "lib")   -Recurse -Force
    Copy-Item (Join-Path $sourceRoot "tools") (Join-Path $stagingDir "tools") -Recurse -Force

    $zipPath = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".zip")
    Push-Location $stagingDir
    try { Compress-Archive -Path @("Matrix.ps1","lib","tools") -DestinationPath $zipPath -Force }
    finally { Pop-Location }
    Remove-Item $stagingDir -Recurse -Force
    return $zipPath
}

# ── 1. Pre-install cleanup ─────────────────────────────────────────────────────
Start-Suite "Pre-install cleanup [$platform]"

Assert-True "install.pwsh.ps1 exists"   (Test-Path $installerPath)
Assert-True "uninstall.pwsh.ps1 exists" (Test-Path $uninstallerPath)

try {
    $exitCode = Invoke-TestUninstaller
    Assert-True "uninstaller is idempotent on missing dirs" ($exitCode -eq 0)
} catch {
    Add-Result -Test "uninstaller runs cleanly on missing dirs" -Passed $false -Detail "$_"
}

Assert-True "install dir absent before install" (-not (Test-Path $testHome))
Assert-True "launcher absent before install"    (-not (Test-Path $script:launcher))

# ── 2. Run the real installer ──────────────────────────────────────────────────
Start-Suite "install.pwsh.ps1 execution [$platform]"

$zipPath = $null
try {
    New-StubOllama
    $zipPath = New-TestReleaseZip

    New-Item -ItemType Directory -Path $testBin -Force | Out-Null

    $env:MATRIX_HOME        = $testHome
    $env:MATRIX_BIN_DIR     = $testBin
    $env:MATRIX_MODEL       = "stub-model:latest"
    $env:MATRIX_RELEASE_ZIP = $zipPath
    $env:MATRIX_NO_PROFILE  = "1"
    $env:MATRIX_NO_LAUNCH   = "1"

    $output = pwsh -NoProfile -ExecutionPolicy Bypass -File $installerPath 2>&1 | Out-String
    $installerExit = $LASTEXITCODE

    Assert-True "installer exits cleanly" ($installerExit -eq 0)
    Assert-True "installer reports ollama present"  ($output -match "Ollama")
    Assert-True "installer reports model available" ($output -match "stub-model")
    Assert-True "installer reports Matrix installed" ($output -match "Matrix installed")
    Assert-True "installer reports launcher created" ($output -match "Installed 'matrix'")

} catch {
    Add-Result -Test "installer execution" -Passed $false -Detail "$_"
} finally {
    Remove-Item Env:MATRIX_HOME        -EA SilentlyContinue
    Remove-Item Env:MATRIX_BIN_DIR     -EA SilentlyContinue
    Remove-Item Env:MATRIX_MODEL       -EA SilentlyContinue
    Remove-Item Env:MATRIX_RELEASE_ZIP -EA SilentlyContinue
    Remove-Item Env:MATRIX_NO_PROFILE  -EA SilentlyContinue
    Remove-Item Env:MATRIX_NO_LAUNCH   -EA SilentlyContinue
    if ($zipPath -and (Test-Path $zipPath)) { Remove-Item $zipPath -Force -EA SilentlyContinue }
}

# ── 3. Layout assertions ───────────────────────────────────────────────────────
Start-Suite "Install layout [$platform]"

Assert-True "install dir created"         (Test-Path $testHome)
Assert-True "Matrix.ps1 present"          (Test-Path (Join-Path $testHome "Matrix.ps1"))
Assert-True "lib/Network.ps1 present"     (Test-Path (Join-Path $testHome "lib" "Network.ps1"))
Assert-True "lib/Context.ps1 present"     (Test-Path (Join-Path $testHome "lib" "Context.ps1"))
Assert-True "lib/CLI.ps1 present"         (Test-Path (Join-Path $testHome "lib" "CLI.ps1"))
Assert-True "lib/ToolManager.ps1 present" (Test-Path (Join-Path $testHome "lib" "ToolManager.ps1"))
Assert-True "tools/ present"              (Test-Path (Join-Path $testHome "tools"))
Assert-True "launcher created"            (Test-Path $script:launcher)

if (-not $IsWindows) {
    $executable = & sh -c "[ -x '$($script:launcher)' ] && echo 1 || echo 0" 2>/dev/null
    Assert-True "launcher is executable" ($executable.Trim() -eq "1")
}

$srcCount  = @(Get-ChildItem (Join-Path $sourceRoot "tools") -Filter "*.ps1").Count
$instCount = @(Get-ChildItem (Join-Path $testHome "tools")   -Filter "*.ps1").Count
Assert-Equal "all $srcCount tools installed" $srcCount $instCount

# ── 4. Smoke test ─────────────────────────────────────────────────────────────
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
    Assert-True  "installed libs load without error"     ($toolCount -gt 0)
    Assert-Equal "installed tool count matches source"   $srcCount $toolCount
} catch {
    Add-Result -Test "Smoke test" -Passed $false -Detail "$_"
}

# ── 5. Bin-dir candidate selection (non-Windows) ──────────────────────────────
if (-not $IsWindows) {
    Start-Suite "Bin-dir candidate selection [$platform]"

    # Run installer without MATRIX_BIN_DIR so the candidate-probe logic runs.
    # Inject a writable temp dir as the first candidate by pre-staging it.
    $candidateBin  = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-cand-$PID"
    $candidateHome = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-chome-$PID"
    New-Item -ItemType Directory -Path $candidateBin  -Force | Out-Null
    New-Item -ItemType Directory -Path $candidateHome -Force | Out-Null

    # Simulate re-install: plant a stale symlink where the launcher will be written
    $staleLauncher = Join-Path $candidateBin "matrix"
    New-Item -ItemType SymbolicLink -Path $staleLauncher -Target "/nonexistent/matrix" -Force | Out-Null

    $zipPath2 = $null
    try {
        $zipPath2 = New-TestReleaseZip

        # Patch the candidate list in a temp copy of the installer
        $tmpInstaller = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".ps1")
        (Get-Content $installerPath -Raw) -replace
            [regex]::Escape('@("/usr/local/bin", "/opt/homebrew/bin", "$HOME/.local/bin", "$HOME/bin")'),
            "@(`"$candidateBin`")" |
            Set-Content $tmpInstaller -Encoding UTF8

        $env:MATRIX_HOME        = $candidateHome
        $env:MATRIX_MODEL       = "stub-model:latest"
        $env:MATRIX_RELEASE_ZIP = $zipPath2
        $env:MATRIX_NO_PROFILE  = "1"
        $env:MATRIX_NO_LAUNCH   = "1"

        $output2    = pwsh -NoProfile -ExecutionPolicy Bypass -File $tmpInstaller 2>&1 | Out-String
        $exitCode2  = $LASTEXITCODE

        Assert-True  "installer exits cleanly without MATRIX_BIN_DIR" ($exitCode2 -eq 0)
        Assert-True  "launcher written to candidate dir" (Test-Path (Join-Path $candidateBin "matrix"))
        $isExec = & sh -c "[ -x '$(Join-Path $candidateBin "matrix")' ] && echo 1 || echo 0" 2>/dev/null
        Assert-True  "candidate launcher is executable" ($isExec.Trim() -eq "1")

    } catch {
        Add-Result -Test "bin-dir candidate selection" -Passed $false -Detail "$_"
    } finally {
        Remove-Item Env:MATRIX_HOME        -EA SilentlyContinue
        Remove-Item Env:MATRIX_MODEL       -EA SilentlyContinue
        Remove-Item Env:MATRIX_RELEASE_ZIP -EA SilentlyContinue
        Remove-Item Env:MATRIX_NO_PROFILE  -EA SilentlyContinue
        Remove-Item Env:MATRIX_NO_LAUNCH   -EA SilentlyContinue
        if ($zipPath2) { Remove-Item $zipPath2 -Force -EA SilentlyContinue }
        if ($tmpInstaller) { Remove-Item $tmpInstaller -Force -EA SilentlyContinue }
        Remove-Item $candidateBin, $candidateHome -Recurse -Force -EA SilentlyContinue
    }
}

# ── 6. Uninstall ──────────────────────────────────────────────────────────────
Start-Suite "Uninstall [$platform]"

try {
    $exitCode = Invoke-TestUninstaller
    Assert-True "uninstaller exits cleanly" ($exitCode -eq 0)
} catch {
    Add-Result -Test "Uninstaller ran without exception" -Passed $false -Detail "$_"
}

Assert-True "install dir gone" (-not (Test-Path $testHome))
Assert-True "launcher gone"    (-not (Test-Path $script:launcher))

Remove-Item $testBin  -Recurse -Force -EA SilentlyContinue
Remove-Item $stubBin  -Recurse -Force -EA SilentlyContinue
Assert-True "bin dir gone"     (-not (Test-Path $testBin))

# ── Summary ───────────────────────────────────────────────────────────────────
$failed = Show-TestSummary
exit $failed

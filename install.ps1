# Matrix — Windows bootstrap (PowerShell 5.1+)
#
# Ensures PowerShell 7 (pwsh) is installed, then delegates to
# install.pwsh.ps1 which handles Ollama, model, repo, and launch.
#
# Usage (run from Windows PowerShell 5.1):
#   irm https://raw.githubusercontent.com/laynr/matrix/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Write-Info { param($m) Write-Host "  [setup] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  [ok]    $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  [warn]  $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "  [error] $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  +----------------------------------+" -ForegroundColor Cyan
Write-Host "  |          M A T R I X             |" -ForegroundColor Cyan
Write-Host "  |   AI Agent  *  PowerShell Core   |" -ForegroundColor Cyan
Write-Host "  +----------------------------------+" -ForegroundColor Cyan
Write-Host ""

# ── Execution policy ─────────────────────────────────────────────────────────
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("Restricted","Undefined")) {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Ok "Execution policy set to RemoteSigned"
}

# ── Install PowerShell 7 (pwsh) if missing or old ────────────────────────────
$pwshOk = $false
try {
    $v = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>$null
    if ([int]$v -ge 7) { $pwshOk = $true }
} catch {}

if ($pwshOk) {
    Write-Ok "PowerShell 7 already installed"
} else {
    Write-Warn "PowerShell 7 not found — installing..."
    if (Get-Command winget -EA SilentlyContinue) {
        Write-Info "Installing via winget..."
        winget install --id Microsoft.PowerShell -e --source winget --silent
    } else {
        Write-Info "Downloading PowerShell 7 installer..."
        $tmp = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".msi")
        # Resolve latest version from GitHub API
        $rel = Invoke-RestMethod "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $asset = $rel.assets | Where-Object { $_.name -match "win-x64\.msi$" } | Select-Object -First 1
        Invoke-WebRequest $asset.browser_download_url -OutFile $tmp
        Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /quiet /norestart" -Wait
        Remove-Item $tmp -Force
    }
    # Reload PATH
    $env:PATH = [Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("PATH","User")

    try { $v = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.Major' }
    catch { Write-Fail "PowerShell 7 installation failed." }
    Write-Ok "PowerShell $v installed"
}

# ── Delegate to the shared cross-platform installer ───────────────────────────
Write-Info "Running cross-platform PowerShell installer..."
Write-Host ""

$installerUrl = "https://raw.githubusercontent.com/laynr/matrix/main/install.pwsh.ps1"
$tmp = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".ps1")
Invoke-WebRequest $installerUrl -OutFile $tmp
& pwsh -NoProfile -ExecutionPolicy Bypass -File $tmp
Remove-Item $tmp -Force

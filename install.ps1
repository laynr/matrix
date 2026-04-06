# matrix.ps1 — Windows installer
#
# One-liner install (PowerShell, no Administrator required):
#   irm https://raw.githubusercontent.com/laynr/matrix.ps1/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$REPO_URL    = "https://github.com/laynr/matrix.ps1"
$INSTALL_DIR = if ($env:MATRIX_HOME) { $env:MATRIX_HOME } else { Join-Path $HOME ".matrix" }
$MODEL       = if ($env:MATRIX_MODEL) { $env:MATRIX_MODEL } else { "gemma4:latest" }

function Write-Ok   { param($msg) Write-Host "  [ok]    $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "  [setup] $msg" -ForegroundColor Cyan }
function Write-Warn { param($msg) Write-Host "  [warn]  $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  [error] $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  +----------------------------------+" -ForegroundColor Cyan
Write-Host "  |          M A T R I X             |" -ForegroundColor Cyan
Write-Host "  |     AI Agent  *  Ollama           |" -ForegroundColor Cyan
Write-Host "  +----------------------------------+" -ForegroundColor Cyan
Write-Host "  Installing to : $INSTALL_DIR"
Write-Host "  Model         : $MODEL"
Write-Host ""

# ── Step 1: Execution policy ──────────────────────────────────────────────────
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("Restricted", "Undefined")) {
    Write-Info "Setting execution policy to RemoteSigned for current user..."
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Ok "Execution policy: RemoteSigned"
} else {
    Write-Ok "Execution policy: $policy"
}

# ── Step 2: PowerShell version ────────────────────────────────────────────────
$psVer = $PSVersionTable.PSVersion
if ($psVer.Major -lt 5) { Write-Fail "PowerShell 5.1+ required (found $psVer)" }
Write-Ok "PowerShell $psVer"

# ── Step 3: Install Git if missing ────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn "Git not found — installing via winget..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Git.Git -e --source winget --silent
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
    } else {
        Write-Fail "Git is required. Install from https://git-scm.com/download/win and re-run."
    }
}
Write-Ok "Git: $(git --version)"

# ── Step 4: Install Ollama if missing ─────────────────────────────────────────
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Warn "Ollama not found — installing..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "Installing Ollama via winget..."
        winget install --id Ollama.Ollama -e --source winget --silent
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
    } else {
        Write-Info "Downloading Ollama installer..."
        $tmp = [System.IO.Path]::GetTempFileName() -replace "\.tmp$",".exe"
        Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $tmp
        Write-Info "Running Ollama installer (silent)..."
        Start-Process -FilePath $tmp -ArgumentList "/S" -Wait
        Remove-Item $tmp -Force
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
    }
    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Fail "Ollama installation failed. Install manually from https://ollama.com"
    }
}
Write-Ok "Ollama: $(ollama --version 2>$null | Select-Object -First 1)"

# ── Step 5: Ensure Ollama service is running ──────────────────────────────────
Write-Info "Checking Ollama service..."
try { ollama list 2>$null | Out-Null }
catch {
    Write-Info "Starting Ollama service..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 4
}
Write-Ok "Ollama service running"

# ── Step 6: Pull model ────────────────────────────────────────────────────────
Write-Info "Checking model '$MODEL'..."
$modelList = ollama list 2>$null
if ($modelList -match [regex]::Escape($MODEL.Split(":")[0])) {
    Write-Ok "Model '$MODEL' already available"
} else {
    Write-Info "Pulling '$MODEL' — this may take several minutes..."
    ollama pull $MODEL
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to pull '$MODEL'. Check your internet connection." }
    Write-Ok "Model '$MODEL' ready"
}

# ── Step 7: Clone or update repo ──────────────────────────────────────────────
if (Test-Path (Join-Path $INSTALL_DIR ".git")) {
    Write-Info "Updating Matrix at $INSTALL_DIR..."
    git -C $INSTALL_DIR pull --quiet
    Write-Ok "Matrix updated"
} else {
    Write-Info "Cloning Matrix to $INSTALL_DIR..."
    git clone --quiet $REPO_URL $INSTALL_DIR
    Write-Ok "Matrix cloned to $INSTALL_DIR"
}

# ── Step 8: Install 'matrix' command ─────────────────────────────────────────
$binDir = Join-Path $HOME "bin"
if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir | Out-Null }

$launcherPath = Join-Path $binDir "matrix.ps1"
@"
# Matrix launcher — generated by installer
& "$INSTALL_DIR\Matrix.ps1" @args
"@ | Set-Content $launcherPath -Encoding UTF8

$userPath = [System.Environment]::GetEnvironmentVariable("PATH","User")
if ($userPath -notlike "*$binDir*") {
    [System.Environment]::SetEnvironmentVariable("PATH","$binDir;$userPath","User")
    $env:PATH = "$binDir;$env:PATH"
    Write-Ok "Added $binDir to PATH"
}
Write-Ok "Installed 'matrix' command → $launcherPath"

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ✓ Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "  Run anytime:  matrix"
Write-Host "  Override model:  `$env:MATRIX_MODEL='gemma4:27b'; matrix"
Write-Host ""
Write-Host "  Starting Matrix now..."
Write-Host ""

& "$INSTALL_DIR\Matrix.ps1" -CLI

#!/usr/bin/env pwsh
# Matrix — cross-platform PowerShell Core installer
#
# This script runs with `pwsh` (PowerShell 7+) on Mac, Linux, and Windows.
# It is called by install.sh (Mac/Linux) and install.ps1 (Windows) after
# those platform-specific scripts have bootstrapped pwsh itself.
#
# Handles: Ollama install, model pull, download release zip, launcher, run.

$ErrorActionPreference = "Stop"

$RELEASE_ZIP = "https://github.com/laynr/matrix/releases/download/latest/matrix-release.zip"
$INSTALL_DIR = if ($env:MATRIX_HOME) { $env:MATRIX_HOME } else { Join-Path $HOME ".matrix" }
$MODEL       = if ($env:MATRIX_MODEL) { $env:MATRIX_MODEL } else { "gemma4:latest" }

function Write-Ok   { param($m) Write-Host "  [ok]    $m" -ForegroundColor Green }
function Write-Info { param($m) Write-Host "  [setup] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "  [warn]  $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "  [error] $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  Installing to : $INSTALL_DIR" -ForegroundColor Cyan
Write-Host "  Model         : $MODEL" -ForegroundColor Cyan
Write-Host "  PowerShell    : $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Install Ollama ────────────────────────────────────────────────────
function Install-Ollama {
    if ($IsWindows) {
        if (Get-Command winget -EA SilentlyContinue) {
            Write-Info "Installing Ollama via winget..."
            winget install --id Ollama.Ollama -e --source winget --silent
        } else {
            Write-Info "Downloading Ollama installer..."
            $tmp = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".exe")
            Invoke-WebRequest "https://ollama.com/download/OllamaSetup.exe" -OutFile $tmp
            Start-Process $tmp -ArgumentList "/S" -Wait
            Remove-Item $tmp -Force
        }
        # Reload PATH
        $env:PATH = [Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("PATH","User")

    } elseif ($IsMacOS) {
        if (Get-Command brew -EA SilentlyContinue) {
            Write-Info "Installing Ollama via Homebrew..."
            brew install ollama
        } else {
            Write-Info "Downloading Ollama for macOS..."
            $tmp = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".zip")
            Invoke-WebRequest "https://ollama.com/download/Ollama-darwin.zip" -OutFile $tmp
            $extractDir = [IO.Path]::Combine([IO.Path]::GetTempPath(), "ollama-extract")
            Expand-Archive $tmp -DestinationPath $extractDir -Force
            $bin = Join-Path $extractDir "Ollama.app/Contents/Resources/ollama"
            if (Test-Path $bin) {
                sudo cp $bin /usr/local/bin/ollama
                sudo chmod +x /usr/local/bin/ollama
                Write-Ok "Ollama binary installed to /usr/local/bin/ollama"
            } else {
                Write-Fail "Could not find ollama binary in Ollama.app"
            }
            Remove-Item $tmp, $extractDir -Recurse -Force
        }

    } elseif ($IsLinux) {
        Write-Info "Installing Ollama via official install script..."
        $script = Invoke-RestMethod "https://ollama.com/install.sh"
        $tmp = [IO.Path]::GetTempFileName()
        $script | Set-Content $tmp
        chmod +x $tmp
        & sh $tmp
        Remove-Item $tmp -Force
    }
}

if (Get-Command ollama -EA SilentlyContinue) {
    Write-Ok "Ollama: $(ollama --version 2>$null | Select-Object -First 1)"
} else {
    Write-Warn "Ollama not found — installing..."
    Install-Ollama
    Get-Command ollama -EA SilentlyContinue | Out-Null
    if (-not (Get-Command ollama -EA SilentlyContinue)) {
        Write-Fail "Ollama installation failed. Install manually from https://ollama.com"
    }
    Write-Ok "Ollama installed: $(ollama --version 2>$null | Select-Object -First 1)"
}

# ── Step 2: Start Ollama service ──────────────────────────────────────────────
Write-Info "Checking Ollama service..."
$ollamaRunning = $false
try { ollama list 2>$null | Out-Null; $ollamaRunning = $true } catch {}

if (-not $ollamaRunning) {
    Write-Info "Starting Ollama service..."
    if ($IsWindows) {
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    } else {
        Start-Process -FilePath "ollama" -ArgumentList "serve" -RedirectStandardOutput "/dev/null" -RedirectStandardError "/dev/null"
    }
    Start-Sleep -Seconds 4
    try { ollama list 2>$null | Out-Null }
    catch { Write-Fail "Ollama service failed to start. Run 'ollama serve' manually." }
}
Write-Ok "Ollama service running"

# ── Step 3: Pull the model ────────────────────────────────────────────────────
Write-Info "Checking model '$MODEL'..."
$modelBase = $MODEL.Split(":")[0]
$modelList  = ollama list 2>$null | Out-String
if ($modelList -match [regex]::Escape($modelBase)) {
    Write-Ok "Model '$MODEL' already available"
} else {
    Write-Info "Pulling '$MODEL' — this may take several minutes..."
    ollama pull $MODEL
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to pull '$MODEL'. Check your internet connection." }
    Write-Ok "Model '$MODEL' ready"
}

# ── Step 4: Download and extract release ─────────────────────────────────────
Write-Info "Downloading Matrix to $INSTALL_DIR..."
$tmpZip = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".zip")
try {
    Invoke-WebRequest $RELEASE_ZIP -OutFile $tmpZip -UseBasicParsing
    if (Test-Path $INSTALL_DIR) { Remove-Item $INSTALL_DIR -Recurse -Force }
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    Expand-Archive $tmpZip -DestinationPath $INSTALL_DIR -Force
    Write-Ok "Matrix installed to $INSTALL_DIR"
} finally {
    Remove-Item $tmpZip -Force -EA SilentlyContinue
}

# ── Step 5: Install 'matrix' command ─────────────────────────────────────────
$matrixScript = Join-Path $INSTALL_DIR "Matrix.ps1"

if ($IsWindows) {
    $binDir = Join-Path $HOME "bin"
    if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir | Out-Null }
    $launcher = Join-Path $binDir "matrix.ps1"
    "& `"$matrixScript`" @args" | Set-Content $launcher -Encoding UTF8
    $userPath = [Environment]::GetEnvironmentVariable("PATH","User")
    if ($userPath -notlike "*$binDir*") {
        [Environment]::SetEnvironmentVariable("PATH","$binDir;$userPath","User")
        $env:PATH = "$binDir;$env:PATH"
    }
    Write-Ok "Installed 'matrix' → $launcher"
} else {
    # Mac / Linux: write an executable shell script so 'matrix' works anywhere
    $binCandidates = @("/usr/local/bin", "/opt/homebrew/bin", "$HOME/.local/bin", "$HOME/bin")
    $binDir = $binCandidates | Where-Object { Test-Path $_ -and (Get-Item $_).Attributes -notmatch "ReadOnly" } |
              Select-Object -First 1

    if (-not $binDir) {
        $binDir = "$HOME/.local/bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    $launcher = Join-Path $binDir "matrix"
    @"
#!/usr/bin/env sh
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$matrixScript" "`$@"
"@ | Set-Content $launcher -Encoding UTF8
    chmod +x $launcher
    Write-Ok "Installed 'matrix' → $launcher"

    # Ensure binDir is in PATH via shell profile
    foreach ($profile in @("$HOME/.zshrc", "$HOME/.bash_profile", "$HOME/.profile")) {
        if ((Test-Path $profile) -and -not (Get-Content $profile -Raw -EA SilentlyContinue).Contains($binDir)) {
            Add-Content $profile "`n# Added by Matrix installer`nexport PATH=`"$binDir`:`$PATH`""
            Write-Info "Added $binDir to PATH in $profile"
            break
        }
    }
}

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ✓ Setup complete. Run 'matrix' anytime." -ForegroundColor Green
Write-Host "  Override model: MATRIX_MODEL=gemma4:27b matrix"
Write-Host ""
Write-Host "  Starting Matrix now..."
Write-Host ""

# Re-open stdin from the terminal if we were piped from curl|sh
if ($IsWindows) {
    & $matrixScript -CLI
} else {
    # Launch via shell so the </dev/tty redirect works
    $shell = if (Test-Path "/bin/zsh") { "/bin/zsh" } else { "/bin/sh" }
    & $shell -c "pwsh -NoProfile -ExecutionPolicy Bypass -File '$matrixScript' -CLI </dev/tty"
}

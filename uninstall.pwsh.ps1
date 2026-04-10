#!/usr/bin/env pwsh
# Matrix — cross-platform uninstaller
#
# Removes the Matrix install directory and the 'matrix' launcher command.
# Mirrors the paths chosen by install.pwsh.ps1 so they stay in sync.
#
# Usage:
#   pwsh uninstall.pwsh.ps1
#
# Override defaults with environment variables (same vars as the installer):
#   MATRIX_HOME    — install directory (default: ~/.matrix)
#   MATRIX_BIN_DIR — directory that contains the launcher (auto-detected if unset)

param([switch]$Quiet)

$ErrorActionPreference = "Stop"

$INSTALL_DIR = if ($env:MATRIX_HOME) { $env:MATRIX_HOME } else { Join-Path $HOME ".matrix" }

function Write-Ok   { param($m) if (-not $Quiet) { Write-Host "  [ok]    $m" -ForegroundColor Green } }
function Write-Info { param($m) if (-not $Quiet) { Write-Host "  [info]  $m" -ForegroundColor Cyan } }
function Write-Warn { param($m) Write-Host "  [warn]  $m" -ForegroundColor Yellow }

Write-Info "Uninstalling Matrix from $INSTALL_DIR..."

# ── Remove install directory ──────────────────────────────────────────────────
if (Test-Path $INSTALL_DIR) {
    Remove-Item $INSTALL_DIR -Recurse -Force
    Write-Ok "Removed install directory: $INSTALL_DIR"
} else {
    Write-Warn "Install directory not found (already removed?): $INSTALL_DIR"
}

# ── Find and remove the launcher ──────────────────────────────────────────────
$launcher = $null

if ($env:MATRIX_BIN_DIR) {
    # Testing / CI: caller tells us exactly where the launcher is
    $launcherName = if ($IsWindows) { "matrix.ps1" } else { "matrix" }
    $launcher = Join-Path $env:MATRIX_BIN_DIR $launcherName
} elseif ($IsWindows) {
    $launcher = Join-Path $HOME "bin" "matrix.ps1"
} else {
    # Same priority order as the installer's bin-dir candidates
    $candidates = @(
        "/usr/local/bin/matrix"
        "/opt/homebrew/bin/matrix"
        (Join-Path $HOME ".local" "bin" "matrix")
        (Join-Path $HOME "bin" "matrix")
    )
    $launcher = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($launcher -and (Test-Path $launcher)) {
    Remove-Item $launcher -Force
    Write-Ok "Removed launcher: $launcher"
} else {
    Write-Warn "Launcher not found — skipping (path checked: $launcher)"
}

# ── Windows: remove bin dir from user PATH if it is now empty ─────────────────
if ($IsWindows) {
    $binDir = if ($env:MATRIX_BIN_DIR) { $env:MATRIX_BIN_DIR } else { Join-Path $HOME "bin" }
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -and $userPath -like "*$binDir*") {
        $newPath = (($userPath -split ";") | Where-Object { $_ -and $_ -ne $binDir }) -join ";"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        $env:PATH = ($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -ne $binDir }) -join [IO.Path]::PathSeparator
        Write-Ok "Removed $binDir from user PATH"
    }
}

# ── Mac/Linux: remove PATH export lines added by the installer ────────────────
if (-not $IsWindows) {
    $binDir = if ($env:MATRIX_BIN_DIR) { $env:MATRIX_BIN_DIR } else { $null }

    $profiles = @(
        (Join-Path $HOME ".zshrc")
        (Join-Path $HOME ".bash_profile")
        (Join-Path $HOME ".profile")
    )

    foreach ($prof in $profiles) {
        if (-not (Test-Path $prof)) { continue }
        $raw = Get-Content $prof -Raw -Encoding UTF8
        # Remove the two-line block the installer appended (comment + export)
        $pattern = "`n# Added by Matrix installer`nexport PATH=`"[^`"]*`":`\`$PATH`""
        # Also match the specific bin dir if we know it
        $modified = $raw -replace [regex]::Escape("`n# Added by Matrix installer`nexport PATH=`"$(if ($binDir) { [regex]::Escape($binDir) } else { '[^"]*' })`":`$PATH"), ""
        if ($modified -ne $raw) {
            Set-Content $prof $modified -Encoding UTF8 -NoNewline
            Write-Ok "Removed PATH entry from $prof"
        }
    }
}

Write-Ok "Matrix uninstalled successfully."

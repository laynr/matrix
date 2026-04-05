# Matrix — cross-platform meta-installer (Windows entry point)
#
# Detects platform and installs the right port.
# On Windows this delegates to matrix.ps1.
#
# Usage (PowerShell):
#   irm https://raw.githubusercontent.com/laynr/matrix/main/install.ps1 | iex

$OS = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription

if ($IsWindows -or $OS -like "*Windows*") {
    Write-Host ""
    Write-Host "  Matrix — detected Windows"
    Write-Host "  Installing matrix.ps1 (PowerShell + Claude)..."
    Write-Host ""
    $script = (New-Object System.Net.WebClient).DownloadString(
        "https://raw.githubusercontent.com/laynr/matrix.ps1/main/install.ps1"
    )
    Invoke-Expression $script
} elseif ($IsMacOS -or $IsLinux) {
    Write-Host ""
    Write-Host "  Matrix — detected Unix-like OS"
    Write-Host "  Run this instead:"
    Write-Host '    curl -fsSL https://raw.githubusercontent.com/laynr/matrix/main/install.sh | sh'
    Write-Host ""
} else {
    Write-Host "  Unsupported platform." -ForegroundColor Red
    exit 1
}

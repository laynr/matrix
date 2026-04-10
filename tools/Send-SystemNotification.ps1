<#
.SYNOPSIS
Sends a desktop notification using the platform-native mechanism (Windows/macOS/Linux).

.PARAMETER Title
The notification title.

.PARAMETER Message
The notification body text.

.PARAMETER TimeoutSec
How long (in seconds) to display the notification. Defaults to 5.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Title,

    [Parameter(Mandatory)]
    [string]$Message,

    [int]$TimeoutSec = 5
)

try {
    $success = $false
    $method  = ""
    $errMsg  = ""

    if ($IsWindows) {
        # Try Windows 10+ Toast notification via BurntToast-style WinRT call
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $notify            = [System.Windows.Forms.NotifyIcon]::new()
            $notify.Icon       = [System.Drawing.SystemIcons]::Information
            $notify.BalloonTipTitle = $Title
            $notify.BalloonTipText  = $Message
            $notify.Visible    = $true
            $notify.ShowBalloonTip($TimeoutSec * 1000)
            $notify.Dispose()
            $success = $true
            $method  = "NotifyIcon"
        } catch {
            # Fallback: msg.exe (requires interactive session / local user)
            try {
                $safeMsg = ($Title + ": " + $Message) -replace '"', "'"
                & msg.exe * /time:$TimeoutSec "$safeMsg" 2>$null
                $success = ($LASTEXITCODE -eq 0)
                $method  = "msg.exe"
            } catch {
                $errMsg  = $_.Exception.Message
            }
        }

    } elseif ($IsMacOS) {
        try {
            $safeTitle = $Title   -replace "'", "\\'"
            $safeMsg   = $Message -replace "'", "\\'"
            & osascript -e "display notification `"$safeMsg`" with title `"$safeTitle`"" 2>$null
            $success = ($LASTEXITCODE -eq 0)
            $method  = "osascript"
        } catch {
            $errMsg = $_.Exception.Message
        }

    } elseif ($IsLinux) {
        if (-not (Get-Command 'notify-send' -ErrorAction SilentlyContinue)) {
            return @{
                Success = $false
                Method  = ""
                error   = "Linux desktop notifications require 'notify-send' (install libnotify-bin / libnotify)."
            } | ConvertTo-Json -Depth 3 -Compress
        }
        try {
            $timeoutMs = $TimeoutSec * 1000
            & notify-send -t $timeoutMs "$Title" "$Message" 2>$null
            $success = ($LASTEXITCODE -eq 0)
            $method  = "notify-send"
        } catch {
            $errMsg = $_.Exception.Message
        }
    } else {
        return @{ error = "Unsupported platform." } | ConvertTo-Json -Compress
    }

    $result = @{
        Success  = $success
        Method   = $method
        Platform = if ($IsWindows) { "Windows" } elseif ($IsMacOS) { "macOS" } else { "Linux" }
    }
    if (-not $success -and $errMsg) { $result.Error = $errMsg }

    return $result | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{
        Success = $false
        Method  = ""
        error   = $_.Exception.Message
    } | ConvertTo-Json -Depth 3 -Compress
}

#!/usr/bin/env pwsh
# Matrix AI Agent — cross-platform entry point
# Requires PowerShell 7+ (pwsh). Run with: pwsh Matrix.ps1 [-CLI]
param(
    [switch]$CLI   # force CLI mode; default on non-Windows
)

$ErrorActionPreference = "Stop"

# On non-Windows there is no WPF — always use CLI
if (-not $IsWindows) { $CLI = $true }

$global:MatrixRoot = $PSScriptRoot

# Dot-source libs using Join-Path (safe on all platforms)
. (Join-Path $global:MatrixRoot "lib" "Config.ps1")
. (Join-Path $global:MatrixRoot "lib" "Context.ps1")
. (Join-Path $global:MatrixRoot "lib" "Network.ps1")
. (Join-Path $global:MatrixRoot "lib" "ToolManager.ps1")
. (Join-Path $global:MatrixRoot "lib" "Logger.ps1")

$logPath = Join-Path $global:MatrixRoot "matrix.log"
if (Test-Path $logPath) { Remove-Item $logPath -Force }
Write-MatrixLog -Message "Matrix starting (pwsh $($PSVersionTable.PSVersion))"

$global:Config = Load-Config
Clear-Messages

if ($CLI) {
    . (Join-Path $global:MatrixRoot "lib" "CLI.ps1")
    Show-MatrixCLI
} else {
    # GUI — Windows only
    . (Join-Path $global:MatrixRoot "lib" "GUI.ps1")

    $global:TotalInputTokens  = 0
    $global:TotalOutputTokens = 0

    function Update-TokenDisplay {
        if ($global:GUI.TokenTracker) {
            $global:GUI.TokenTracker.Dispatcher.InvokeAsync({
                $global:GUI.TokenTracker.Text = "Tokens: $($global:TotalInputTokens) In | $($global:TotalOutputTokens) Out"
            }) | Out-Null
        }
    }

    function Process-AssistantMessage {
        param($assistantMsg)
        $result = Invoke-MatrixToolchain -Message $assistantMsg.message
        if (-not [string]::IsNullOrWhiteSpace($result.TextOutput)) {
            Add-UIChatMessage -Role "assistant" -Message $result.TextOutput
        }
        if ($result.HasTools) {
            foreach ($tc in $result.ToolsCalled) {
                Add-UIChatMessage -Role "system" -Message "Executing tool $($tc.function.name)..."
            }
            foreach ($tr in $result.ToolResults) {
                Add-Message -Role $tr.role -Content $tr.content
            }
            Add-UIChatMessage -Role "system" -Message "Sending tool results..."
            $global:GUI.Window.Dispatcher.InvokeAsync({
                $resp = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools (Get-MatrixTools)
                if ($resp.error) { Add-UIChatMessage -Role "system" -Message "Error: $($resp.error)" }
                elseif ($resp.message) {
                    Add-Message -Role "assistant" -Content $resp.message.content
                    Process-AssistantMessage -assistantMsg $resp
                    Prune-Context
                }
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        }
    }

    function Invoke-Send {
        $text = $global:GUI.InputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        $global:GUI.InputBox.Text = ""
        Add-UIChatMessage -Role "user" -Message $text
        $global:GUI.SendBtn.IsEnabled    = $false
        $global:GUI.InputBox.IsEnabled   = $false
        Add-Message -Role "user" -Content $text
        Add-UIChatMessage -Role "system" -Message "Thinking..."
        $global:GUI.Window.Dispatcher.InvokeAsync({
            try {
                $resp = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools (Get-MatrixTools)
                if ($resp.error) { Add-UIChatMessage -Role "system" -Message "Error: $($resp.error)" }
                else {
                    Add-Message -Role "assistant" -Content $resp.message.content
                    Process-AssistantMessage -assistantMsg $resp
                    Prune-Context
                }
            } catch {
                Add-UIChatMessage -Role "system" -Message "Exception: $_"
            } finally {
                $global:GUI.SendBtn.IsEnabled  = $true
                $global:GUI.InputBox.IsEnabled = $true
                $global:GUI.InputBox.Focus() | Out-Null
            }
        }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    }

    Show-MatrixGUI
}

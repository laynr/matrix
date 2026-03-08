param(
    [switch]$CLI
)

$ErrorActionPreference = "Stop"

$global:MatrixRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$global:MatrixRoot\lib\Config.ps1"
. "$global:MatrixRoot\lib\Context.ps1"
. "$global:MatrixRoot\lib\Network.ps1"
. "$global:MatrixRoot\lib\ToolManager.ps1"
. "$global:MatrixRoot\lib\Logger.ps1"
$logPath = Join-Path $global:MatrixRoot "err.log"
if (Test-Path $logPath) { Remove-Item $logPath -Force }
Write-MatrixLog -Message "Matrix Starting..."

$global:Config = Load-Config
Clear-Messages

$global:TotalInputTokens = 0
$global:TotalOutputTokens = 0

function Update-TokenDisplay {
    if ($global:GUI.TokenTracker) {
        $global:GUI.TokenTracker.Dispatcher.InvokeAsync({
            $global:GUI.TokenTracker.Text = "Tokens: $($global:TotalInputTokens) In | $($global:TotalOutputTokens) Out"
        }) | Out-Null
    }
}

if ($CLI) {
    . "$global:MatrixRoot\lib\CLI.ps1"
    Show-MatrixCLI
} else {
    . "$global:MatrixRoot\lib\GUI.ps1"
    
    function Invoke-AttachFile {
        $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $OpenFileDialog.Filter = "All Files (*.*)|*.*"
        if ($OpenFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $filePath = $OpenFileDialog.FileName
            try {
                $fileContent = Get-Content $filePath -Raw
                $global:GUI.InputBox.Text += "`n[Attached File: $($OpenFileDialog.SafeFileName)]`n$fileContent`n"
            } catch {
                Add-UIChatMessage -Role "system" -Message "Failed to read file: $_"
            }
        }
    }
    
    function Process-AssistantMessage {
        param($assistantMsg)
        
        $result = Invoke-MatrixToolchain -MessageContent $assistantMsg.content
        
        if (-not [string]::IsNullOrWhiteSpace($result.TextOutput)) {
            Add-UIChatMessage -Role "assistant" -Message $result.TextOutput
        }
        
        if ($result.HasTools) {
            foreach ($tc in $result.ToolsCalled) {
                Add-UIChatMessage -Role "system" -Message "Executing tool $($tc.name)..."
            }
            
            Add-Message -Role "user" -Content $result.ToolResults
            Add-UIChatMessage -Role "system" -Message "Sending tool results back to Matrix..."
            
            $global:CurrentTools = Get-MatrixTools
            
            Write-MatrixLog -Message "Requesting MatrixChat API (Follow-up)..."
            
            $global:GUI.Window.Dispatcher.InvokeAsync({
                $response = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $global:CurrentTools
                
                if ($response.error) {
                    Add-UIChatMessage -Role "system" -Message "API Error: $($response.error)"
                } elseif ($response.content) {
                    if ($response.usage) {
                        $global:TotalInputTokens += $response.usage.input_tokens
                        $global:TotalOutputTokens += $response.usage.output_tokens
                        Update-TokenDisplay
                    }
                    Add-Message -Role "assistant" -Content $response.content
                    Process-AssistantMessage -assistantMsg $response
                    Prune-Context
                }
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        }
    }

    function Invoke-Send {
        $text = $global:GUI.InputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        if (-not $global:Config.ApiKey) {
            Add-UIChatMessage -Role "system" -Message "Please set your API Key in Settings first."
            return
        }
        
        $global:GUI.InputBox.Text = ""
        Add-UIChatMessage -Role "user" -Message $text
        
        $global:GUI.SendBtn.IsEnabled = $false
        $global:GUI.InputBox.IsEnabled = $false
        
        Add-Message -Role "user" -Content $text
        Write-MatrixLog -Message "User Prompt: $text"
        $global:CurrentTools = Get-MatrixTools
        
        Add-UIChatMessage -Role "system" -Message "Thinking..."
        
        $global:GUI.Window.Dispatcher.InvokeAsync({
            try {
                Start-Sleep -Milliseconds 50
                
                $response = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $global:CurrentTools
                
                if ($response.error) {
                    Add-UIChatMessage -Role "system" -Message "API Error: $($response.error)"
                } else {
                    if ($response.usage) {
                        $global:TotalInputTokens += $response.usage.input_tokens
                        $global:TotalOutputTokens += $response.usage.output_tokens
                        Update-TokenDisplay
                    }
                    Add-Message -Role "assistant" -Content $response.content
                    Process-AssistantMessage -assistantMsg $response
                    Prune-Context
                }
            } catch {
                Add-UIChatMessage -Role "system" -Message "Exception: $_"
            } finally {
                $global:GUI.SendBtn.IsEnabled = $true
                $global:GUI.InputBox.IsEnabled = $true
                $global:GUI.InputBox.Focus() | Out-Null
            }
        }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    }
    
    Show-MatrixGUI
}


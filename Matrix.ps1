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
Write-MatrixLog -Message "Matrix Agent Starting..."

$global:Config = Load-Config
Clear-Messages

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
        
        $textOutput = ""
        $toolsCalled = @()
        
        if ($assistantMsg.content) {
            foreach ($content in $assistantMsg.content) {
                if ($content.type -eq "text") {
                    $textOutput += $content.text + "`n"
                } elseif ($content.type -eq "tool_use") {
                    $toolsCalled += $content
                    $textOutput += "[Tool Call: $($content.name)]`n"
                }
            }
        }
        
        if (-not [string]::IsNullOrWhiteSpace($textOutput)) {
            Write-MatrixLog -Message "Assistant Text: $($textOutput.Trim())"
            Add-UIChatMessage -Role "assistant" -Message $textOutput.Trim()
        }
        
        if ($toolsCalled.Count -gt 0) {
            $toolResults = @()
            foreach ($tc in $toolsCalled) {
                Add-UIChatMessage -Role "system" -Message "Executing tool $($tc.name)..."
                
                $argsHash = @{}
                $argLog = ""
                if ($tc.input -and $tc.input -isnot [string]) {
                    foreach ($key in $tc.input.psobject.properties.name) {
                        $argsHash[$key] = $tc.input.$key
                        $argLog += "$key=$($tc.input.$key) "
                    }
                }
                
                Write-MatrixLog -Message "Invoking Tool: $($tc.name) Args: $argLog"
                
                $toolRes = Invoke-MatrixTool -ToolName $tc.name -InputArgs $argsHash
                
                $toolResults += @{
                    type = "tool_result"
                    tool_use_id = $tc.id
                    content = $toolRes
                }
                Write-MatrixLog -Message "Tool Result ($($tc.name)): $toolRes"
            }
            
            Add-Message -Role "user" -Content $toolResults
            Add-UIChatMessage -Role "system" -Message "Sending tool results back to Matrix..."
            
            $global:CurrentTools = Get-MatrixTools
            
            Write-MatrixLog -Message "Requesting MatrixChat API (Follow-up)..."
            
            $global:GUI.Window.Dispatcher.InvokeAsync({
                $response = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $global:CurrentTools
                
                if ($response.error) {
                    Add-UIChatMessage -Role "system" -Message "API Error: $($response.error)"
                } elseif ($response.content) {
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

$LibRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($null -eq $LibRoot) { $LibRoot = "." }
. (Join-Path $LibRoot "Logger.ps1")

function Show-MatrixCLI {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "          Matrix AI Agent CLI" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan

    if (-not $global:Config.ApiKey) {
        Write-Host "Warning: API Key is not set in config.json!" -ForegroundColor Yellow
    }

    while ($true) {
        Write-Host ""
        $inputMsg = Read-Host "You"
        if ([string]::IsNullOrWhiteSpace($inputMsg)) { continue }
        if ($inputMsg -eq "exit" -or $inputMsg -eq "quit") { break }

        Add-Message -Role "user" -Content $inputMsg
        $tools = Get-MatrixTools
        
        Write-Host "Matrix is thinking..." -ForegroundColor DarkGray
        
        try {
            $response = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $tools
            
            if ($response.error) {
                Write-Host "API Error: $($response.error)" -ForegroundColor Red
            } else {
                Write-MatrixLog -Message "Assistant Response: $($response.content)"
                Add-Message -Role "assistant" -Content $response.content
                Process-AssistantMessageCLI -assistantMsg $response
                Prune-Context
            }
        } catch {
            Write-Host "Exception: $_" -ForegroundColor Red
        }
    }
}

function Process-AssistantMessageCLI {
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
        Write-Host $textOutput.Trim()
        Write-MatrixLog -Message "Assistant Text: $($textOutput.Trim())"
    }
    
    if ($toolsCalled.Count -gt 0) {
        $toolResults = @()
        foreach ($tc in $toolsCalled) {
            Write-Host "[Executing tool $($tc.name)...]" -ForegroundColor DarkCyan
            
            $argsHash = @{}
            if ($tc.input -and $tc.input -isnot [string]) {
                foreach ($key in $tc.input.psobject.properties.name) {
                    $argsHash[$key] = $tc.input.$key
                }
            }
            
            $toolRes = Invoke-MatrixTool -ToolName $tc.name -InputArgs $argsHash
            
            $toolResults += @{
                type = "tool_result"
                tool_use_id = $tc.id
                content = $toolRes
            }
        }
        
        Add-Message -Role "user" -Content $toolResults
        Write-MatrixLog -Message "Sending tool results: $($toolResults | ConvertTo-Json -Compress)"
        Write-Host "[Sending tool results back...]" -ForegroundColor DarkGray
        
        $tools = Get-MatrixTools
        
        try {
            $response = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $tools
            
            if ($response.error) {
                Write-Host "API Error: $($response.error)" -ForegroundColor Red
            } elseif ($response.content) {
                Add-Message -Role "assistant" -Content $response.content
                Process-AssistantMessageCLI -assistantMsg $response
                Prune-Context
            }
        } catch {
            Write-Host "Exception: $_" -ForegroundColor Red
        }
    }
}

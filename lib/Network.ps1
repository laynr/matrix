[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-MatrixChat {
    param(
        [hashtable]$Config,
        [array]$Messages,
        [array]$Tools
    )
    
    $providerName = [string]$Config.Provider
    if ($providerName -eq "Anthropic") {
        $headers = @{
            "x-api-key" = $Config.ApiKey
            "anthropic-version" = "2023-06-01"
            "content-type" = "application/json"
        }
        
        $bodyObj = @{
            model = $Config.Model
            max_tokens = 4096
            system = $Config.SystemPrompt
            messages = $Messages
        }
        
        if ($Tools -and $Tools.Count -gt 0) {
            Write-MatrixLog -Message "Passing $($Tools.Count) tools to bodyObj"
            $filteredTools = $Tools | Where-Object { $null -ne $_ -and $_ -is [hashtable] }
            if ($filteredTools) {
                $bodyObj.tools = @($filteredTools)
            } else {
                Write-MatrixLog -Level "WARN" -Message "All tools were filtered out!"
            }
        } else {
            Write-MatrixLog -Message "No tools provided to Invoke-MatrixChat"
        }
        
        $bodyJson = $bodyObj | ConvertTo-Json -Depth 10 -Compress
        
        Write-MatrixLog -Message "NETWORK REQUEST: $bodyJson"
        
        try {
            $response = Invoke-RestMethod -Uri $Config.Endpoint -Method Post -Headers $headers -Body $bodyJson
            $respJson = $response | ConvertTo-Json -Depth 5 -Compress
            Write-MatrixLog -Message "NETWORK RESPONSE: $respJson"
            return $response
        } catch {
            $errMsg = $_.Exception.Response.GetResponseStream()
            if ($errMsg) {
                $reader = New-Object System.IO.StreamReader($errMsg)
                $errBody = $reader.ReadToEnd()
                Write-MatrixLog -Level "ERROR" -Message "NETWORK ERROR: $errBody"
                return @{ error = $errBody; status = "error" }
            }
            Write-MatrixLog -Level "ERROR" -Message "NETWORK ERROR: $($_.Exception.Message)"
            return @{ error = $_.Exception.Message; status = "error" }
        }
    } else {
        # Framework for OpenAI or others
        throw "Provider $($Config.Provider) not yet fully implemented in Network.ps1"
    }
}

function Invoke-MatrixToolchain {
    param(
        [array]$MessageContent
    )
    
    $textOutput = ""
    $toolsCalled = @()
    $toolResults = @()
    $hasTools = $false

    if ($MessageContent) {
        foreach ($content in $MessageContent) {
            if ($content.type -eq "text") {
                $textOutput += $content.text + "`n"
            } elseif ($content.type -eq "tool_use") {
                $toolsCalled += $content
                $textOutput += "[Tool Call: $($content.name)]`n"
                $hasTools = $true
            }
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($textOutput)) {
        Write-MatrixLog -Message "Assistant Text: $($textOutput.Trim())"
    }
    
    if ($hasTools) {
        foreach ($tc in $toolsCalled) {
            $argsHash = @{}
            $argLog = ""
            if ($null -ne $tc.input -and $tc.input -isnot [string]) {
                $propNames = ($tc.input | Get-Member -MemberType NoteProperty).Name
                if ($propNames) {
                    foreach ($pName in $propNames) {
                        try {
                            $argsHash[$pName] = [string]$tc.input.$pName
                            $argLog += "$pName=$($argsHash[$pName]) "
                        } catch {
                            $argLog += "$pName=<Error> "
                        }
                    }
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
    }
    
    $outToolResults = $null
    if ($hasTools) {
        $outToolResults = $toolResults
    }

    return @{
        TextOutput = $textOutput.Trim()
        ToolResults = $outToolResults
        HasTools = $hasTools
        ToolsCalled = $toolsCalled
    }
}

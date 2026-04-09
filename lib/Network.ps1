[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Coerces a JSON-parsed value to the correct PowerShell type so tools receive
# booleans, ints, and doubles rather than everything as a string.
function Invoke-CoerceArg {
    param($Value)
    switch ($Value) {
        { $_ -is [bool]   } { return [bool]$_;   break }
        { $_ -is [long]   } { return [int]$_;    break }
        { $_ -is [double] } { return [double]$_; break }
        default             { return [string]$_ }
    }
}

# Calls the Ollama chat API and returns the raw response object.
# Response shape: { model, message: { role, content, tool_calls }, done }
function Invoke-MatrixChat {
    param(
        [hashtable]$Config,
        [array]$Messages,
        [array]$Tools
    )

    $body = @{
        model    = $Config.Model
        messages = $Messages
        stream   = $false
    }

    if ($Tools -and $Tools.Count -gt 0) {
        $body.tools = $Tools
    }

    $bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
    Write-MatrixLog -Message "REQUEST: $bodyJson"

    try {
        $response = Invoke-RestMethod `
            -Uri         $Config.Endpoint `
            -Method      Post `
            -ContentType "application/json" `
            -Body        $bodyJson `
            -TimeoutSec  120
        Write-MatrixLog -Message "RESPONSE: $($response | ConvertTo-Json -Depth 6 -Compress)"
        return $response
    } catch {
        $errMsg = $_.Exception.Message
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = [System.IO.StreamReader]::new($stream)
                $errMsg = $reader.ReadToEnd()
            }
        } catch {}
        Write-MatrixLog -Level "ERROR" -Message "NETWORK ERROR: $errMsg"
        return @{ error = $errMsg }
    }
}

# Parses an Ollama message object, executes any tool calls, and returns
# the text output plus tool result messages ready to append to history.
function Invoke-MatrixToolchain {
    param(
        [object]$Message   # Ollama message: { role, content, tool_calls }
    )

    $textOutput  = [string]$Message.content
    $toolsCalled = @()
    $toolResults = @()
    $hasTools    = $false

    if ($Message.tool_calls) {
        $hasTools    = $true
        $toolsCalled = @($Message.tool_calls)
    }

    foreach ($tc in $toolsCalled) {
        $name = $tc.function.name
        $rawArgs = $tc.function.arguments

        # arguments may arrive as a PSCustomObject, hashtable, or JSON string
        $argsHash = @{}
        if ($rawArgs -is [string] -and $rawArgs.Trim() -ne "") {
            try {
                $parsed = $rawArgs | ConvertFrom-Json
                $parsed.PSObject.Properties | ForEach-Object { $argsHash[$_.Name] = Invoke-CoerceArg $_.Value }
            } catch {}
        } elseif ($rawArgs -and $rawArgs.PSObject) {
            $rawArgs.PSObject.Properties | ForEach-Object { $argsHash[$_.Name] = Invoke-CoerceArg $_.Value }
        }

        Write-MatrixLog -Message "Invoking tool: $name  args: $($argsHash | ConvertTo-Json -Compress)"
        $result = Invoke-MatrixTool -ToolName $name -InputArgs $argsHash
        Write-MatrixLog -Message "Tool result ($name): $result"

        Write-Host "  [tool] $name" -ForegroundColor DarkCyan
        Write-Host "  [result] $result" -ForegroundColor DarkGray

        $toolResults += @{
            role    = "tool"
            content = $result
        }
    }

    return @{
        TextOutput   = $textOutput
        ToolResults  = $toolResults
        HasTools     = $hasTools
        ToolsCalled  = $toolsCalled
    }
}

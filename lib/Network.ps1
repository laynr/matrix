[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:MaxToolResultChars = 8000
$script:HttpClient         = $null

function Get-MatrixHttpClient {
    if (-not $script:HttpClient) {
        $script:HttpClient         = [System.Net.Http.HttpClient]::new()
        $script:HttpClient.Timeout = [TimeSpan]::FromSeconds(120)
    }
    return $script:HttpClient
}

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

# Truncates oversized tool results so they don't flood the context window.
function Limit-ToolResult {
    param([string]$Result)
    if (-not $Result -or $Result.Length -le $script:MaxToolResultChars) { return $Result }
    $omitted = $Result.Length - $script:MaxToolResultChars
    Write-MatrixLog "Tool result truncated: $omitted chars omitted"
    return $Result.Substring(0, $script:MaxToolResultChars) +
           "`n[... $omitted characters truncated — full result in err.log]"
}

# Blocking (non-streaming) chat call — used by the Windows GUI path.
# Injects system prompt and retries on transient failures.
# Returns the raw Ollama response object, or { error: "..." } on failure.
function Invoke-MatrixChat {
    param(
        [hashtable]$Config,
        [array]$Messages,
        [array]$Tools
    )

    $messagesWithSystem = if ($Config.SystemPrompt) {
        @(@{ role = "system"; content = $Config.SystemPrompt }) + $Messages
    } else { $Messages }

    $numCtx = if ($Config.NumCtx) { $Config.NumCtx } else { 8192 }
    $body = @{
        model      = $Config.Model
        messages   = $messagesWithSystem
        stream     = $false
        keep_alive = "-1"
        options    = @{ num_ctx = $numCtx }
    }
    if ($Tools -and $Tools.Count -gt 0) { $body.tools = $Tools }
    $bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
    Write-MatrixLog -Message "REQUEST (blocking): model=$($Config.Model) messages=$($messagesWithSystem.Count) num_ctx=$numCtx"

    $maxRetries = 3
    $delay      = 1

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $Config.Endpoint -Method Post `
                -ContentType "application/json" -Body $bodyJson -TimeoutSec 120
            Write-MatrixLog -Message "RESPONSE: content_len=$($response.message.content.Length)"
            return $response
        } catch {
            $msg         = $_.Exception.Message
            $isRateLimit = $msg -match "429|rate.limit|too.many"
            $isTransient = $msg -match "timeout|connect|503|502|reset|unavailable"
            if ($attempt -lt $maxRetries -and ($isRateLimit -or $isTransient)) {
                $wait = if ($isRateLimit) { $delay * 4 } else { $delay }
                Write-MatrixLog -Level "WARN" -Message "Retrying (attempt $attempt): $msg"
                Start-Sleep -Seconds $wait
                $delay *= 2
            } else {
                Write-MatrixLog -Level "ERROR" -Message "Network error (attempt $attempt): $msg"
                return @{ error = $msg }
            }
        }
    }
}

# Streams a chat response from Ollama, printing tokens to the console as they arrive.
# Injects the system prompt on every request (not stored in history to avoid pruning).
# Retries on transient failures with exponential backoff.
#
# Returns: { message: { role, content, tool_calls } }
#      or: { error: "..." }
function Invoke-MatrixStreamingChat {
    param(
        [hashtable]$Config,
        [array]$Messages,
        [array]$Tools
    )

    # System prompt prepended on every call — never stored in history
    $messagesWithSystem = if ($Config.SystemPrompt) {
        @(@{ role = "system"; content = $Config.SystemPrompt }) + $Messages
    } else {
        $Messages
    }

    $numCtx = if ($Config.NumCtx) { $Config.NumCtx } else { 8192 }
    $body = @{
        model      = $Config.Model
        messages   = $messagesWithSystem
        stream     = $true
        keep_alive = "-1"
        options    = @{ num_ctx = $numCtx }
    }
    if ($Tools -and $Tools.Count -gt 0) { $body.tools = $Tools }
    $bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
    Write-MatrixLog -Message "REQUEST (streaming): model=$($Config.Model) messages=$($messagesWithSystem.Count) num_ctx=$numCtx"

    $maxRetries = 3
    $delay      = 1

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        $reader = $null
        try {
            $client     = Get-MatrixHttpClient
            $reqContent = [System.Net.Http.StringContent]::new(
                $bodyJson, [Text.Encoding]::UTF8, "application/json")
            $httpResp   = $client.PostAsync($Config.Endpoint, $reqContent).GetAwaiter().GetResult()
            $httpResp.EnsureSuccessStatusCode() | Out-Null
            $reader     = [System.IO.StreamReader]::new(
                $httpResp.Content.ReadAsStreamAsync().GetAwaiter().GetResult())

            $fullContent = [System.Text.StringBuilder]::new()
            $toolCalls   = $null

            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $chunk = $line | ConvertFrom-Json -EA Stop
                    $token = $chunk.message.content
                    if ($token) {
                        [Console]::Write($token)
                        [void]$fullContent.Append($token)
                    }
                    if ($chunk.message.tool_calls) {
                        $toolCalls = $chunk.message.tool_calls
                    }
                } catch {}
            }

            Write-MatrixLog -Message "RESPONSE: content_len=$($fullContent.Length) has_tools=$($null -ne $toolCalls)"
            return @{
                message = @{
                    role       = "assistant"
                    content    = $fullContent.ToString()
                    tool_calls = $toolCalls
                }
            }

        } catch {
            $msg         = $_.Exception.Message
            $isRateLimit = $msg -match "429|rate.limit|too.many"
            $isTransient = $msg -match "timeout|connect|503|502|reset|unavailable"

            if ($attempt -lt $maxRetries -and ($isRateLimit -or $isTransient)) {
                $wait = if ($isRateLimit) { $delay * 4 } else { $delay }
                Write-Host "`n  [retry $attempt/$maxRetries] Waiting ${wait}s..." -ForegroundColor DarkYellow
                Write-MatrixLog -Level "WARN" -Message "Retrying (attempt $attempt): $msg"
                Start-Sleep -Seconds $wait
                $delay *= 2
            } else {
                Write-Host ""
                Write-MatrixLog -Level "ERROR" -Message "Network error (attempt $attempt): $msg"
                return @{ error = $msg }
            }
        } finally {
            if ($reader) { try { $reader.Dispose() } catch {} }
        }
    }
}

# Dispatches all tool calls in a message concurrently using PowerShell runspaces.
# Each tool runs in its own isolated runspace; results are collected in order.
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

    if (-not $hasTools) {
        return @{
            TextOutput  = $textOutput
            ToolResults = $toolResults
            HasTools    = $hasTools
            ToolsCalled = $toolsCalled
        }
    }

    # Parse arguments and launch all tools concurrently
    $runspaceList = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($tc in $toolsCalled) {
        $name    = $tc.function.name
        $rawArgs = $tc.function.arguments

        $argsHash = @{}
        if ($rawArgs -is [string] -and $rawArgs.Trim() -ne "") {
            try {
                $parsed = $rawArgs | ConvertFrom-Json
                $parsed.PSObject.Properties | ForEach-Object {
                    $argsHash[$_.Name] = Invoke-CoerceArg $_.Value
                }
            } catch {}
        } elseif ($rawArgs -and $rawArgs.PSObject) {
            $rawArgs.PSObject.Properties | ForEach-Object {
                $argsHash[$_.Name] = Invoke-CoerceArg $_.Value
            }
        }

        Write-MatrixLog -Message "Dispatching tool: $name  args: $($argsHash | ConvertTo-Json -Compress)"

        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($root, $toolName, $inputArgs)
            $global:MatrixRoot = $root
            . (Join-Path $root "lib" "Logger.ps1")
            . (Join-Path $root "lib" "ToolManager.ps1")
            Invoke-MatrixTool -ToolName $toolName -InputArgs $inputArgs
        }).AddArgument($global:MatrixRoot).AddArgument($name).AddArgument($argsHash)

        $runspaceList.Add(@{ PS = $ps; Handle = $ps.BeginInvoke(); Name = $name })
    }

    # Collect results in original order
    foreach ($rs in $runspaceList) {
        $raw = try {
            ($rs.PS.EndInvoke($rs.Handle) | Out-String).Trim()
        } catch {
            @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
        }
        $rs.PS.Dispose()

        $truncated = Limit-ToolResult $raw
        Write-MatrixLog -Message "Tool result ($($rs.Name)): $truncated"
        Write-Host "  [tool]   $($rs.Name)" -ForegroundColor DarkCyan
        Write-Host "  [result] $truncated" -ForegroundColor DarkGray

        $toolResults += @{ role = "tool"; content = $truncated }
    }

    return @{
        TextOutput  = $textOutput
        ToolResults = $toolResults
        HasTools    = $hasTools
        ToolsCalled = $toolsCalled
    }
}

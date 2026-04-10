[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$script:MaxToolResultChars = 8000
$script:HttpClient         = $null

function Get-MatrixHttpClient {
    if (-not $script:HttpClient) {
        $script:HttpClient         = [System.Net.Http.HttpClient]::new()
        $script:HttpClient.Timeout = [TimeSpan]::FromSeconds(120)
    }
    return $script:HttpClient
}

# Computes num_ctx from actual message payload + tool schemas so the KV cache
# is sized to fit the full prompt. Tools must be included — their schemas can
# easily exceed the message tokens on a fresh conversation.
# Override: set Config.NumCtx > 0 to pin a fixed value (e.g. for debugging).
function Get-DynamicNumCtx {
    param([array]$Messages, [array]$Tools, [int]$Override = 0, [int]$MaxCtx = 131072)
    if ($Override -gt 0) { return $Override }

    $msgChars = ($Messages | ForEach-Object {
        $c = if ($_.content -is [string]) { $_.content } else { $_.content | ConvertTo-Json -Compress }
        $c.Length
    } | Measure-Object -Sum).Sum

    $toolChars = if ($Tools -and $Tools.Count -gt 0) {
        ($Tools | ConvertTo-Json -Depth 10 -Compress).Length
    } else { 0 }

    # ~3.5 chars per token; 2x headroom for the model's response
    $needed  = [math]::Ceiling(($msgChars + $toolChars) / 3.5) * 2
    # Round up to nearest 512, minimum 4096 (tools alone often need 1500+ tokens)
    $rounded = [math]::Max(4096, [math]::Ceiling($needed / 512) * 512)
    return [math]::Min($MaxCtx, $rounded)
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
    Write-MatrixLog "Tool result truncated: $omitted chars omitted (total $($Result.Length))"
    return $Result.Substring(0, $script:MaxToolResultChars) +
           "`n[... $omitted characters omitted — result was truncated to fit context window]"
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

    $numCtx = Get-DynamicNumCtx -Messages $messagesWithSystem -Tools $Tools -Override ([int]$Config.NumCtx)
    $body = @{
        model      = $Config.Model
        messages   = $messagesWithSystem
        stream     = $false
        keep_alive = -1
        options    = @{ num_ctx = $numCtx }
    }
    if ($Tools -and $Tools.Count -gt 0) { $body.tools = $Tools }
    $bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
    Write-MatrixLog -Message "REQUEST (blocking): model=$($Config.Model) messages=$($messagesWithSystem.Count) num_ctx=$numCtx"

    $maxRetries = 3
    $delay      = 1

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-RestMethod -Uri $Config.Endpoint -Method Post `
                -ContentType "application/json" -Body $bodyJson -TimeoutSec 120
            $sw.Stop()
            $outLen    = $response.message.content.Length
            $outTok    = [math]::Ceiling($outLen / 3.5)
            $tokRate   = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($outTok / $sw.Elapsed.TotalSeconds, 1) } else { 0 }
            Write-MatrixLog -Message "RESPONSE: elapsed=$($sw.ElapsedMilliseconds)ms content_len=$outLen ~${outTok}tok ${tokRate}tok/s"
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

    $numCtx = Get-DynamicNumCtx -Messages $messagesWithSystem -Tools $Tools -Override ([int]$Config.NumCtx)
    $body = @{
        model      = $Config.Model
        messages   = $messagesWithSystem
        stream     = $true
        keep_alive = -1
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
            $sw         = [System.Diagnostics.Stopwatch]::StartNew()
            # ResponseHeadersRead: returns as soon as headers arrive so the body
            # streams live. The default (ResponseContentRead) buffers everything
            # first, making "streaming" appear as a single delayed dump.
            # PostAsync has no HttpCompletionOption overload — use SendAsync.
            $req        = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Post, $Config.Endpoint)
            $req.Content = $reqContent
            $httpResp   = $client.SendAsync(
                $req,
                [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
            ).GetAwaiter().GetResult()
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
                        [Console]::Out.Flush()
                        [void]$fullContent.Append($token)
                    }
                    if ($chunk.message.tool_calls) {
                        $toolCalls = $chunk.message.tool_calls
                    }
                } catch {}
            }

            $sw.Stop()
            $outTok  = [math]::Ceiling($fullContent.Length / 3.5)
            $tokRate = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($outTok / $sw.Elapsed.TotalSeconds, 1) } else { 0 }
            Write-MatrixLog -Message "RESPONSE: elapsed=$($sw.ElapsedMilliseconds)ms content_len=$($fullContent.Length) ~${outTok}tok ${tokRate}tok/s has_tools=$($null -ne $toolCalls)"
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
            if ($reader)     { try { $reader.Dispose()     } catch {} }
            if ($httpResp)   { try { $httpResp.Dispose()   } catch {} }
            if ($reqContent) { try { $reqContent.Dispose() } catch {} }
        }
    }
    return @{ error = "All $maxRetries attempts failed" }
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
        $preview = if ($truncated.Length -gt 200) { $truncated.Substring(0, 200) + '...' } else { $truncated }
        Write-Host "  [tool]   $($rs.Name)" -ForegroundColor DarkCyan
        Write-Host "  [result] $preview" -ForegroundColor DarkGray

        $toolResults += @{ role = "tool"; content = $truncated }
    }

    return @{
        TextOutput  = $textOutput
        ToolResults = $toolResults
        HasTools    = $hasTools
        ToolsCalled = $toolsCalled
    }
}

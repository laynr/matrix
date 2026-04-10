<#
.SYNOPSIS
Send a message to a Slack channel via an incoming webhook URL.

.PARAMETER WebhookUrl
The Slack incoming webhook URL.

.PARAMETER Text
The message text to send.

.PARAMETER Username
Display name for the bot sending the message.

.PARAMETER IconEmoji
Emoji to use as the bot's icon (e.g., :robot_face:).

.PARAMETER Channel
Optional channel to override the webhook's default channel (e.g., #general).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WebhookUrl,

    [Parameter(Mandatory)]
    [string]$Text,

    [string]$Username  = "Matrix Agent",
    [string]$IconEmoji = ":robot_face:",
    [string]$Channel   = ""
)

try {
    $payload = @{
        text        = $Text
        username    = $Username
        icon_emoji  = $IconEmoji
    }
    if ($Channel) { $payload['channel'] = $Channel }

    $body = $payload | ConvertTo-Json -Depth 3 -Compress

    $response = Invoke-WebRequest `
        -Uri             $WebhookUrl `
        -Method          POST `
        -Body            $body `
        -ContentType     "application/json" `
        -TimeoutSec      15 `
        -UseBasicParsing `
        -SkipHttpErrorCheck `
        -ErrorAction     Stop

    $statusCode = [int]$response.StatusCode

    return @{
        Success    = ($statusCode -lt 300)
        StatusCode = $statusCode
        Response   = $response.Content
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

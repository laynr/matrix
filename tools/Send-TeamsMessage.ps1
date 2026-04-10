<#
.SYNOPSIS
Send a message card to a Microsoft Teams channel via an incoming webhook URL.

.PARAMETER WebhookUrl
The Microsoft Teams incoming webhook URL.

.PARAMETER Title
Title of the message card.

.PARAMETER Text
Body text of the message card.

.PARAMETER ThemeColor
Hex color code for the card's theme stripe (default 0076D7).

.PARAMETER Facts
Optional hashtable of key-value pairs displayed as a facts table in the card.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WebhookUrl,

    [Parameter(Mandatory)]
    [string]$Title,

    [Parameter(Mandatory)]
    [string]$Text,

    [string]$ThemeColor     = "0076D7",
    [hashtable]$Facts       = @{}
)

try {
    $factsArray = @()
    if ($Facts.Count -gt 0) {
        foreach ($key in $Facts.Keys) {
            $factsArray += @{ name = $key; value = "$($Facts[$key])" }
        }
    }

    $payload = @{
        '@type'    = 'MessageCard'
        '@context' = 'http://schema.org/extensions'
        themeColor = $ThemeColor
        summary    = $Title
        sections   = @(
            @{
                activityTitle = $Title
                text          = $Text
                facts         = $factsArray
            }
        )
    }

    $body = $payload | ConvertTo-Json -Depth 5 -Compress

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

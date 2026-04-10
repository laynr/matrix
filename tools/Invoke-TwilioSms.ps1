<#
.SYNOPSIS
Send an SMS message via the Twilio REST API.

.PARAMETER AccountSid
Your Twilio Account SID.

.PARAMETER AuthToken
Your Twilio Auth Token.

.PARAMETER From
Sender phone number in E.164 format (e.g., +15551234567).

.PARAMETER To
Recipient phone number in E.164 format (e.g., +15559876543).

.PARAMETER Body
The SMS message text to send.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AccountSid,

    [Parameter(Mandatory)]
    [string]$AuthToken,

    [Parameter(Mandatory)]
    [string]$From,

    [Parameter(Mandatory)]
    [string]$To,

    [Parameter(Mandatory)]
    [string]$Body
)

try {
    $credentials = [Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes("$AccountSid`:$AuthToken")
    )

    $formBody = "From=$([uri]::EscapeDataString($From))&To=$([uri]::EscapeDataString($To))&Body=$([uri]::EscapeDataString($Body))"

    $url = "https://api.twilio.com/2010-04-01/Accounts/$AccountSid/Messages.json"

    $response = Invoke-WebRequest `
        -Uri             $url `
        -Method          POST `
        -Body            $formBody `
        -ContentType     "application/x-www-form-urlencoded" `
        -Headers         @{ Authorization = "Basic $credentials" } `
        -TimeoutSec      15 `
        -UseBasicParsing `
        -SkipHttpErrorCheck `
        -ErrorAction     Stop

    $data = $response.Content | ConvertFrom-Json

    if ($data.status -eq 'failed' -or $data.error_code) {
        return @{ error = "$($data.message)" } | ConvertTo-Json -Compress
    }

    if ([int]$response.StatusCode -ge 400) {
        $errMsg = if ($data.message) { "$($data.message)" } else { "HTTP $($response.StatusCode)" }
        return @{ error = $errMsg } | ConvertTo-Json -Compress
    }

    return @{
        MessageSid  = "$($data.sid)"
        Status      = "$($data.status)"
        From        = "$($data.from)"
        To          = "$($data.to)"
        Body        = "$($data.body)"
        DateCreated = "$($data.date_created)"
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

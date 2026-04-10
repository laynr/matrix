<#
.SYNOPSIS
Send a JSON payload to any HTTP webhook endpoint.

.PARAMETER Url
The webhook URL to POST the payload to.

.PARAMETER Payload
Hashtable of data to serialize and send as JSON.

.PARAMETER ContentType
Content-Type header for the request (default application/json).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Url,

    [Parameter(Mandatory)]
    [hashtable]$Payload,

    [string]$ContentType = "application/json"
)

try {
    $body = $Payload | ConvertTo-Json -Depth 5 -Compress

    $response = Invoke-WebRequest `
        -Uri             $Url `
        -Method          POST `
        -Body            $body `
        -ContentType     $ContentType `
        -TimeoutSec      15 `
        -UseBasicParsing `
        -SkipHttpErrorCheck `
        -ErrorAction     Stop

    $statusCode = [int]$response.StatusCode
    $preview    = $response.Content
    if ($preview.Length -gt 500) { $preview = $preview.Substring(0, 500) }

    return @{
        StatusCode = $statusCode
        Success    = ($statusCode -lt 300)
        Response   = $preview
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

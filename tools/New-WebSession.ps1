<#
.SYNOPSIS
Create a persistent cookie-jar session file for stateful HTTP requests.

.PARAMETER BaseUrl
Optional base URL associated with this session.

.PARAMETER UserAgent
User-Agent header string for requests in this session.

.PARAMETER Headers
Optional hashtable of default headers to include in every request.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl   = "",
    [string]$UserAgent = "Mozilla/5.0 (compatible; Matrix-Agent/1.0)",
    $Headers           = @{}   # hashtable or empty string — coerced below
)

try {
    # Model may pass empty string for an optional hashtable param; treat as no headers.
    if (-not ($Headers -is [hashtable])) { $Headers = @{} }

    $tmpDir = [System.IO.Path]::GetTempPath()

    $sessionFile = Join-Path $tmpDir "matrix-session-$([System.Guid]::NewGuid()).json"

    $session = @{
        BaseUrl   = $BaseUrl
        UserAgent = $UserAgent
        Headers   = $Headers
        Cookies   = @()
    }

    $session | ConvertTo-Json -Depth 3 -Compress | Set-Content $sessionFile -Encoding UTF8

    return @{
        SessionPath = $sessionFile
        BaseUrl     = $BaseUrl
        CookieCount = 0
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

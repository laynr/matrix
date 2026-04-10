<#
.SYNOPSIS
Execute a stateful HTTP request using a session file that persists cookies between calls.

.PARAMETER SessionPath
Path to the session file created by New-WebSession.

.PARAMETER Uri
The URL to request.

.PARAMETER Method
HTTP method (GET, POST, PUT, DELETE, etc.).

.PARAMETER Body
Optional request body string.

.PARAMETER ContentType
Content-Type header for requests with a body.

.PARAMETER UpdateSession
When true, save updated cookies back to the session file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SessionPath,

    [Parameter(Mandatory)]
    [string]$Uri,

    [string]$Method       = "GET",
    [string]$Body         = "",
    [string]$ContentType  = "application/json",
    [bool]$UpdateSession  = $true
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SessionPath)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "Session file not found: $resolved" } | ConvertTo-Json -Compress
    }

    $session = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json

    # Build cookie header
    $cookies = @()
    if ($session.Cookies) {
        foreach ($c in $session.Cookies) {
            $cookies += "$($c.Name)=$($c.Value)"
        }
    }

    # Build request headers
    $reqHeaders = @{ 'User-Agent' = $session.UserAgent }
    if ($session.Headers) {
        foreach ($key in $session.Headers.PSObject.Properties.Name) {
            $reqHeaders[$key] = $session.Headers.$key
        }
    }
    if ($cookies.Count -gt 0) {
        $reqHeaders['Cookie'] = $cookies -join '; '
    }

    # Make request
    $iwrArgs = @{
        Uri              = $Uri
        Method           = $Method
        Headers          = $reqHeaders
        TimeoutSec       = 15
        UseBasicParsing  = $true
        SkipHttpErrorCheck = $true
        ErrorAction      = 'Stop'
    }
    if ($Body) {
        $iwrArgs['Body']        = $Body
        $iwrArgs['ContentType'] = $ContentType
    }

    $response = Invoke-WebRequest @iwrArgs

    # Parse Set-Cookie headers
    $cookiesUpdated = 0
    $setCookieHeaders = @()

    if ($response.Headers['Set-Cookie']) {
        $raw = $response.Headers['Set-Cookie']
        if ($raw -is [string[]]) {
            $setCookieHeaders = $raw
        } elseif ($raw -is [string]) {
            # Split on commas not inside cookie values — split on comma followed by letter
            $setCookieHeaders = [regex]::Split($raw, ',\s*(?=[A-Za-z])')
        }
    }

    $cookieList = [System.Collections.Generic.List[object]]::new()
    if ($session.Cookies) {
        foreach ($c in $session.Cookies) {
            $cookieList.Add($c)
        }
    }

    foreach ($sc in $setCookieHeaders) {
        if (-not $sc.Trim()) { continue }
        $parts  = $sc.Trim() -split ';\s*'
        $kv     = $parts[0] -split '=', 2
        if ($kv.Count -lt 2) { continue }
        $name   = $kv[0].Trim()
        $value  = $kv[1].Trim()
        $domain = ''; $path = '/'; $expires = $null

        foreach ($p in $parts[1..($parts.Count-1)]) {
            if ($p -match '^domain=(.+)$')  { $domain  = $Matches[1].Trim() }
            if ($p -match '^path=(.+)$')    { $path    = $Matches[1].Trim() }
            if ($p -match '^expires=(.+)$') { $expires = $Matches[1].Trim() }
        }

        # Update existing or add new
        $existing = $cookieList | Where-Object { $_.Name -eq $name -and ($_.Domain -eq $domain -or $domain -eq '') } | Select-Object -First 1
        if ($existing) {
            $existing.Value   = $value
            if ($expires) { $existing.Expires = $expires }
        } else {
            $cookieList.Add(@{ Name=$name; Value=$value; Domain=$domain; Path=$path; Expires=$expires })
        }
        $cookiesUpdated++
    }

    if ($UpdateSession) {
        $session.Cookies = @($cookieList)
        $session | ConvertTo-Json -Depth 3 -Compress | Set-Content $resolved -Encoding UTF8
    }

    $contentTypeOut = if ($response.Headers['Content-Type']) { "$($response.Headers['Content-Type'])" } else { '' }

    return @{
        StatusCode      = [int]$response.StatusCode
        Content         = $response.Content
        ContentType     = $contentTypeOut
        CookiesUpdated  = $cookiesUpdated
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

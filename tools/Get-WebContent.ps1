<#
.SYNOPSIS
Fetches content from a URL and returns the response as plain text.

.PARAMETER Url
The URL to fetch.

.PARAMETER StripHtml
If true, removes HTML tags and returns readable text. Defaults to true.

.PARAMETER MaxChars
Maximum characters to return. Defaults to 4000.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Url,

    [bool]$StripHtml = $true,
    [int]$MaxChars   = 4000
)

try {
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop

    $body = $response.Content

    if ($StripHtml) {
        # Remove scripts and styles wholesale
        $body = $body -replace '(?si)<script[^>]*>.*?</script>', ''
        $body = $body -replace '(?si)<style[^>]*>.*?</style>', ''
        # Strip remaining tags
        $body = $body -replace '<[^>]+>', ' '
        # Collapse whitespace
        $body = $body -replace '[ \t]+', ' '
        $body = ($body -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join "`n"
        $body = $body -replace "`n{3,}", "`n`n"
    }

    if ($body.Length -gt $MaxChars) {
        $body = $body.Substring(0, $MaxChars) + "`n[truncated at $MaxChars chars]"
    }

    return @{
        Url        = $Url
        StatusCode = $response.StatusCode
        Content    = $body
    } | ConvertTo-Json -Depth 4 -Compress
} catch {
    return @{ error = "Failed to fetch '$Url': $($_.Exception.Message)" } | ConvertTo-Json -Compress
}

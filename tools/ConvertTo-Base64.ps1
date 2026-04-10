<#
.SYNOPSIS
Encodes a string or file to a Base64 string.

.PARAMETER Text
Text string to encode. Used when FilePath is not provided.

.PARAMETER FilePath
Path to a file whose raw bytes will be encoded. Takes priority over Text.
#>
[CmdletBinding()]
param(
    [string]$Text     = "",
    [string]$FilePath = ""
)

try {
    if ($FilePath) {
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
        if (-not (Test-Path -LiteralPath $resolved)) {
            return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
        }
        $bytes      = [System.IO.File]::ReadAllBytes($resolved)
        $sourceType = "File"
    } elseif ($Text) {
        $bytes      = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $sourceType = "Text"
    } else {
        return @{ error = "Provide either Text or FilePath parameter." } | ConvertTo-Json -Compress
    }

    $b64 = [Convert]::ToBase64String($bytes)

    return @{
        Base64           = $b64
        SourceType       = $sourceType
        OriginalSizeBytes = $bytes.Length
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

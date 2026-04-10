<#
.SYNOPSIS
Decodes a Base64 string to text or saves the raw bytes to a file.

.PARAMETER Base64
The Base64-encoded string to decode.

.PARAMETER FilePath
Optional output file path. When provided the decoded bytes are written to this file.

.PARAMETER Encoding
Text encoding to use when decoding to string (UTF8, ASCII, Unicode). Defaults to UTF8.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Base64,

    [string]$FilePath = "",
    [string]$Encoding = "UTF8"
)

try {
    $bytes = [Convert]::FromBase64String($Base64)

    if ($FilePath) {
        $dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
        [System.IO.File]::WriteAllBytes($dst, $bytes)
        return @{
            FilePath  = $dst
            SizeBytes = $bytes.Length
        } | ConvertTo-Json -Depth 3 -Compress
    }

    $enc  = [System.Text.Encoding]::GetEncoding($Encoding)
    $text = $enc.GetString($bytes)

    return @{
        Text      = $text
        SizeBytes = $bytes.Length
        Encoding  = $Encoding
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

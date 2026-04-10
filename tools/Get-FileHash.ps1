<#
.SYNOPSIS
Computes a cryptographic hash of a file using SHA256, SHA512, MD5, or SHA1.

.PARAMETER Path
Path to the file to hash.

.PARAMETER Algorithm
Hash algorithm to use: SHA256, SHA512, MD5, or SHA1. Defaults to SHA256.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [ValidateSet("SHA256","SHA512","MD5","SHA1")]
    [string]$Algorithm = "SHA256"
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
    }

    $info = Get-Item -LiteralPath $resolved
    if ($info.PSIsContainer) {
        return @{ error = "'$resolved' is a directory. Provide a file path." } | ConvertTo-Json -Compress
    }

    $h = Get-FileHash -LiteralPath $resolved -Algorithm $Algorithm

    return @{
        Hash      = $h.Hash
        Algorithm = $h.Algorithm
        Path      = $h.Path
        SizeBytes = $info.Length
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

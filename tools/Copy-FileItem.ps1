<#
.SYNOPSIS
Copies a file or directory to a new location.

.PARAMETER Source
Path to the source file or directory.

.PARAMETER Destination
Path to the destination file or directory.

.PARAMETER Overwrite
If true, overwrite existing files at the destination. Defaults to false.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Source,

    [Parameter(Mandatory)]
    [string]$Destination,

    [bool]$Overwrite = $false
)

try {
    $src = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
    $dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)

    if (-not (Test-Path -LiteralPath $src)) {
        return @{ error = "Source not found: $src" } | ConvertTo-Json -Compress
    }

    $isDir = (Get-Item -LiteralPath $src).PSIsContainer

    if (-not $Overwrite -and (Test-Path -LiteralPath $dst)) {
        return @{ error = "Destination already exists. Set Overwrite=true to replace it." } | ConvertTo-Json -Compress
    }

    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force:$Overwrite -ErrorAction Stop

    return @{
        Source      = $src
        Destination = $dst
        IsDirectory = $isDir
        Overwrite   = $Overwrite
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

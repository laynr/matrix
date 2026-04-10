<#
.SYNOPSIS
Move or rename a file or directory to a new location.

.PARAMETER Source
Path to the file or directory to move.

.PARAMETER Destination
Target path to move the source to.

.PARAMETER Overwrite
When true, overwrite the destination if it already exists.
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

    if ((Test-Path -LiteralPath $dst) -and -not $Overwrite) {
        return @{ error = "Destination already exists: $dst. Set Overwrite=true to replace it." } | ConvertTo-Json -Compress
    }

    Move-Item -LiteralPath $src -Destination $dst -Force:$Overwrite

    return @{
        Source      = $src
        Destination = $dst
        IsDirectory = $isDir
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

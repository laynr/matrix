<#
.SYNOPSIS
Deletes a file or directory. Requires Confirm=false to actually delete.

.PARAMETER Path
Path to the file or directory to delete.

.PARAMETER Recurse
If true, recursively delete directory contents. Defaults to false.

.PARAMETER Confirm
Safety guard — must be explicitly set to false to perform deletion. Defaults to true.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [bool]$Recurse = $false,
    [bool]$Confirm = $true
)

try {
    if ($Confirm) {
        return @{
            error = "Confirm must be explicitly set to false to delete. Set Confirm=false to proceed. Path: $Path"
        } | ConvertTo-Json -Compress
    }

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "Path not found: $resolved" } | ConvertTo-Json -Compress
    }

    $item     = Get-Item -LiteralPath $resolved
    $isDir    = $item.PSIsContainer

    if ($isDir -and -not $Recurse) {
        $children = @(Get-ChildItem -LiteralPath $resolved -ErrorAction SilentlyContinue)
        if ($children.Count -gt 0) {
            return @{ error = "Directory is not empty. Set Recurse=true to delete it and its contents." } | ConvertTo-Json -Compress
        }
    }

    Remove-Item -LiteralPath $resolved -Recurse:$Recurse -Force -ErrorAction Stop

    return @{
        Path         = $resolved
        Deleted      = $true
        WasDirectory = $isDir
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

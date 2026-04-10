<#
.SYNOPSIS
Perform a line-level diff of two text files and report added and removed lines.

.PARAMETER PathA
Path to the first (original) file.

.PARAMETER PathB
Path to the second (modified) file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PathA,

    [Parameter(Mandatory)]
    [string]$PathB
)

try {
    $resolvedA = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PathA)
    $resolvedB = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PathB)

    if (-not (Test-Path -LiteralPath $resolvedA)) {
        return @{ error = "File not found: $resolvedA" } | ConvertTo-Json -Compress
    }
    if (-not (Test-Path -LiteralPath $resolvedB)) {
        return @{ error = "File not found: $resolvedB" } | ConvertTo-Json -Compress
    }

    $linesA = @(Get-Content -LiteralPath $resolvedA -Encoding UTF8)
    $linesB = @(Get-Content -LiteralPath $resolvedB -Encoding UTF8)

    $diff = Compare-Object -ReferenceObject $linesA -DifferenceObject $linesB -PassThru -CaseSensitive 2>$null

    $added   = @($diff | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { "$_" })
    $removed = @($diff | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { "$_" })

    return @{
        AreSame      = ($added.Count -eq 0 -and $removed.Count -eq 0)
        AddedCount   = $added.Count
        RemovedCount = $removed.Count
        AddedLines   = $added
        RemovedLines = $removed
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

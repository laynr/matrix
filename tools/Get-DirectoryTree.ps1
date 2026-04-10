<#
.SYNOPSIS
Returns a recursive summary of a directory tree including file and size counts per level.

.PARAMETER Path
Path to the root directory to summarise.

.PARAMETER MaxDepth
Maximum recursion depth. Defaults to 3.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [int]$MaxDepth = 3
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "Path not found: $resolved" } | ConvertTo-Json -Compress
    }

    $rootItem = Get-Item -LiteralPath $resolved
    if (-not $rootItem.PSIsContainer) {
        return @{ error = "'$resolved' is a file, not a directory." } | ConvertTo-Json -Compress
    }

    $totalFiles = 0
    $totalDirs  = 0
    $totalBytes = 0

    function Build-Tree {
        param([string]$Dir, [int]$Depth)

        $node = @{
            Name          = [System.IO.Path]::GetFileName($Dir)
            Path          = $Dir
            FileCount     = 0
            DirCount      = 0
            TotalSizeBytes = 0
            Children      = @()
        }

        $items = Get-ChildItem -LiteralPath $Dir -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                $node.DirCount++
                $script:totalDirs++
                if ($Depth -lt $MaxDepth) {
                    $child = Build-Tree -Dir $item.FullName -Depth ($Depth + 1)
                    $node.Children  += $child
                    $node.TotalSizeBytes += $child.TotalSizeBytes
                }
            } else {
                $node.FileCount++
                $node.TotalSizeBytes += $item.Length
                $script:totalFiles++
                $script:totalBytes += $item.Length
            }
        }
        return $node
    }

    $tree = Build-Tree -Dir $resolved -Depth 1

    return @{
        Root           = $resolved
        MaxDepth       = $MaxDepth
        TotalFiles     = $totalFiles
        TotalDirs      = $totalDirs
        TotalSizeBytes = $totalBytes
        Tree           = $tree
    } | ConvertTo-Json -Depth 6 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

<#
.SYNOPSIS
Searches for files by name pattern or by text content within files.

.PARAMETER Path
Directory to search in. Defaults to the current directory.

.PARAMETER NamePattern
Wildcard pattern to match file names (e.g. "*.log", "report*").

.PARAMETER ContentPattern
Text or regex pattern to search for inside files.

.PARAMETER Recurse
If true, searches subdirectories recursively. Defaults to true.

.PARAMETER MaxResults
Maximum number of results to return. Defaults to 50.
#>
[CmdletBinding()]
param(
    [string]$Path           = ".",
    [string]$NamePattern    = "*",
    [string]$ContentPattern = "",
    [bool]$Recurse          = $true,
    [int]$MaxResults        = 50
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path $resolved)) {
        return @{ error = "Directory not found: $resolved" } | ConvertTo-Json -Compress
    }

    $getParams = @{
        Path    = $resolved
        Filter  = $NamePattern
        File    = $true
        Recurse = $Recurse
        ErrorAction = "SilentlyContinue"
    }

    $files = Get-ChildItem @getParams

    if ($ContentPattern) {
        $matches = $files | Select-Object -First ($MaxResults * 5) | ForEach-Object {
            try {
                $hits = Select-String -Path $_.FullName -Pattern $ContentPattern -ErrorAction SilentlyContinue
                if ($hits) {
                    @{
                        File    = $_.FullName
                        Matches = @($hits | Select-Object -First 3 | ForEach-Object {
                            "Line $($_.LineNumber): $($_.Line.Trim())"
                        })
                    }
                }
            } catch {}
        } | Where-Object { $_ } | Select-Object -First $MaxResults

        return @{
            SearchPath     = $resolved
            NamePattern    = $NamePattern
            ContentPattern = $ContentPattern
            ResultCount    = @($matches).Count
            Results        = @($matches)
        } | ConvertTo-Json -Depth 3 -Compress
    }

    $results = $files | Select-Object -First $MaxResults | ForEach-Object {
        @{
            Path         = $_.FullName
            SizeBytes    = $_.Length
            LastModified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    return @{
        SearchPath  = $resolved
        NamePattern = $NamePattern
        ResultCount = @($results).Count
        Results     = @($results)
    } | ConvertTo-Json -Depth 3 -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

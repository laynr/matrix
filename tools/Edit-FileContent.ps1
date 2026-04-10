<#
.SYNOPSIS
Find and replace text in an existing file, with optional regex support.

.PARAMETER Path
Path to the file to edit.

.PARAMETER Find
The text or pattern to search for.

.PARAMETER Replace
The replacement text.

.PARAMETER UseRegex
When true, treat Find as a regular expression pattern.

.PARAMETER ReplaceAll
When true, replace all occurrences; when false, replace only the first.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Find,

    [Parameter(Mandatory)]
    [string]$Replace,

    [bool]$UseRegex   = $false,
    [bool]$ReplaceAll = $false
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
    }
    if ((Get-Item -LiteralPath $resolved).PSIsContainer) {
        return @{ error = "Path is a directory, not a file: $resolved" } | ConvertTo-Json -Compress
    }

    $original = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)
    $origLen  = $original.Length

    if ($UseRegex) {
        $pattern = $Find
        $rx = [System.Text.RegularExpressions.Regex]::new($pattern)
        $count = $rx.Matches($original).Count
        if ($ReplaceAll) {
            $updated = $rx.Replace($original, $Replace)
        } else {
            $updated = $rx.Replace($original, $Replace, 1)
            $count   = if ($count -gt 0) { 1 } else { 0 }
        }
    } else {
        $escaped = [System.Text.RegularExpressions.Regex]::Escape($Find)
        $rx      = [System.Text.RegularExpressions.Regex]::new($escaped)
        $count   = $rx.Matches($original).Count
        if ($ReplaceAll) {
            $updated = $original.Replace($Find, $Replace)
        } else {
            if ($count -gt 0) {
                $idx     = $original.IndexOf($Find)
                $updated = $original.Substring(0, $idx) + $Replace + $original.Substring($idx + $Find.Length)
                $count   = 1
            } else {
                $updated = $original
                $count   = 0
            }
        }
    }

    if ($count -gt 0) {
        [System.IO.File]::WriteAllText($resolved, $updated, [System.Text.Encoding]::UTF8)
    }

    return @{
        Path              = $resolved
        ReplacementsCount = $count
        OriginalLength    = $origLen
        NewLength         = $updated.Length
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

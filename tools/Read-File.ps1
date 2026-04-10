<#
.SYNOPSIS
Reads the contents of a file and returns them as text.

.PARAMETER Path
The path to the file to read. Absolute or relative.

.PARAMETER StartLine
Optional. First line to return (1-based). Defaults to 1.

.PARAMETER EndLine
Optional. Last line to return. Defaults to end of file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Path,

    [int]$StartLine = 1,
    [int]$EndLine   = 0
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path $resolved)) {
        return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
    }

    $info = Get-Item $resolved
    if ($info.PSIsContainer) {
        return @{ error = "'$resolved' is a directory, not a file." } | ConvertTo-Json -Compress
    }

    $lines = @(Get-Content $resolved -Encoding UTF8)

    $total = $lines.Count
    $from  = [math]::Max(1, $StartLine) - 1
    $to    = if ($EndLine -gt 0) { [math]::Min($EndLine, $total) - 1 } else { $total - 1 }

    $selected = $lines[$from..$to]
    $content  = $selected -join "`n"

    return @{
        Path      = $resolved
        TotalLines = $total
        ReturnedLines = "$($from + 1)-$($to + 1)"
        Content   = $content
    } | ConvertTo-Json -Depth 5 -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

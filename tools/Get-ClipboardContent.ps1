<#
.SYNOPSIS
Retrieves the current text content of the system clipboard.
#>
[CmdletBinding()]
param()

try {
    $content = Get-Clipboard -ErrorAction Stop
    if ($null -eq $content) { $content = "" }
    # Get-Clipboard can return an array of lines; join with newline
    if ($content -is [array]) { $content = $content -join "`n" }

    return @{
        Content   = "$content"
        SizeChars = $content.Length
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = "Clipboard unavailable: $($_.Exception.Message)" } | ConvertTo-Json -Compress
}

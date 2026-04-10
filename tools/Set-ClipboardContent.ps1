<#
.SYNOPSIS
Sets the system clipboard to the given text string.

.PARAMETER Text
The text to place on the clipboard.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Text
)

try {
    Set-Clipboard -Value $Text -ErrorAction Stop

    return @{
        Success   = $true
        SizeChars = $Text.Length
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = "Clipboard unavailable: $($_.Exception.Message)" } | ConvertTo-Json -Compress
}

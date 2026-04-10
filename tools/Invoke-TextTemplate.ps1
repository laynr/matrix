<#
.SYNOPSIS
Fills a template string by replacing {{key}} placeholders with values from a Variables hashtable.

.PARAMETER Template
Template string containing {{key}} placeholders.

.PARAMETER Variables
Hashtable mapping placeholder names to replacement values.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Template,

    [Parameter(Mandatory)]
    [hashtable]$Variables
)

try {
    $result       = $Template
    $replacements = 0

    foreach ($key in $Variables.Keys) {
        $placeholder = "{{$key}}"
        $count       = ([regex]::Matches($result, [regex]::Escape($placeholder))).Count
        if ($count -gt 0) {
            $result       = $result.Replace($placeholder, "$($Variables[$key])")
            $replacements += $count
        }
    }

    return @{
        Result           = $result
        VariableCount    = $Variables.Count
        ReplacementsMade = $replacements
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

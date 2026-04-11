<#
.SYNOPSIS
Fills a template string by replacing {{key}} placeholders with values from a Variables string (JSON object or key=val,key2=val2).

.PARAMETER Template
Template string containing {{key}} placeholders.

.PARAMETER Variables
Variables as a JSON object ({"key":"val"}) or comma-separated key=value pairs (key=val,key2=val2).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Template,

    [Parameter(Mandatory)]
    [string]$Variables
)

try {
    # Parse Variables: try JSON first, then fall back to key=value,key=value
    $varsTable = @{}
    $trimmed = $Variables.Trim()
    if ($trimmed.StartsWith('{')) {
        $parsed = $trimmed | ConvertFrom-Json
        $parsed.PSObject.Properties | ForEach-Object { $varsTable[$_.Name] = $_.Value }
    } else {
        foreach ($pair in ($trimmed -split ',')) {
            $parts = $pair.Trim() -split '=', 2
            if ($parts.Count -eq 2) { $varsTable[$parts[0].Trim()] = $parts[1].Trim() }
        }
    }

    $result       = $Template
    $replacements = 0

    foreach ($key in $varsTable.Keys) {
        $placeholder = "{{$key}}"
        $count       = ([regex]::Matches($result, [regex]::Escape($placeholder))).Count
        if ($count -gt 0) {
            $result       = $result.Replace($placeholder, "$($varsTable[$key])")
            $replacements += $count
        }
    }

    return @{
        Result           = $result
        VariableCount    = $varsTable.Keys.Count
        ReplacementsMade = $replacements
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

<#
.SYNOPSIS
Converts data between formats: JSON, CSV, and list (one item per line).

.PARAMETER Data
The input data as a string.

.PARAMETER From
The format of the input data. Accepted values: json, csv, list.

.PARAMETER To
The desired output format. Accepted values: json, csv, list, table.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Data,

    [Parameter(Mandatory=$true)]
    [ValidateSet("json","csv","list")]
    [string]$From,

    [Parameter(Mandatory=$true)]
    [ValidateSet("json","csv","list","table")]
    [string]$To
)

try {
    # ── Parse input ───────────────────────────────────────────────────────────
    $objects = switch ($From) {
        "json" {
            $parsed = $Data | ConvertFrom-Json -ErrorAction Stop
            if ($parsed -is [array]) { $parsed } else { @($parsed) }
        }
        "csv" {
            $Data | ConvertFrom-Csv -ErrorAction Stop
        }
        "list" {
            $Data -split "`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object   { $_ } |
                ForEach-Object { [PSCustomObject]@{ Value = $_ } }
        }
    }

    # ── Render output ─────────────────────────────────────────────────────────
    $result = switch ($To) {
        "json"  { $objects | ConvertTo-Json -Depth 10 -Compress }
        "csv"   { $objects | ConvertTo-Csv -NoTypeInformation }
        "list"  {
            $props = ($objects | Select-Object -First 1).PSObject.Properties.Name
            if ($props.Count -eq 1) {
                ($objects | ForEach-Object { $_.$($props[0]) }) -join "`n"
            } else {
                ($objects | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join "`n"
            }
        }
        "table" {
            $objects | Format-Table -AutoSize | Out-String
        }
    }

    return @{
        From   = $From
        To     = $To
        Count  = @($objects).Count
        Output = $result
    } | ConvertTo-Json -Depth 4 -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

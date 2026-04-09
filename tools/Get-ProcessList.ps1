<#
.SYNOPSIS
Lists running processes, optionally filtered by name. Returns name, CPU, and memory usage.

.PARAMETER Name
Optional name filter (supports wildcards, e.g. "node*", "python"). Leave blank to list all.

.PARAMETER Top
Number of processes to return, sorted by memory usage descending. Defaults to 20.
#>
[CmdletBinding()]
param(
    [string]$Name = "",
    [int]$Top     = 20
)

try {
    $procs = if ($Name) {
        Get-Process -Name $Name -ErrorAction SilentlyContinue
    } else {
        Get-Process -ErrorAction SilentlyContinue
    }

    if (-not $procs) {
        return @{ error = "No processes found matching '$Name'." } | ConvertTo-Json -Compress
    }

    $results = $procs |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First $Top |
        ForEach-Object {
            @{
                Name       = $_.ProcessName
                PID        = $_.Id
                MemoryMB   = [math]::Round($_.WorkingSet64 / 1MB, 1)
                CPU        = if ($_.CPU) { [math]::Round($_.CPU, 1) } else { $null }
            }
        }

    return @{
        Filter      = if ($Name) { $Name } else { "*" }
        TotalShown  = @($results).Count
        Processes   = @($results)
    } | ConvertTo-Json -Depth 5 -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

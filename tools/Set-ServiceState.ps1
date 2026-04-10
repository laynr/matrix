<#
.SYNOPSIS
Starts, stops, or restarts a named system service and returns the previous and new state.

.PARAMETER Name
The name of the service to control.

.PARAMETER Action
The action to perform: Start, Stop, or Restart.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(Mandatory)]
    [ValidateSet("Start","Stop","Restart")]
    [string]$Action
)

try {
    $svc = Get-Service -Name $Name -ErrorAction Stop
    $prevStatus = $svc.Status.ToString()

    switch ($Action) {
        "Start"   { Start-Service   -Name $Name -ErrorAction Stop }
        "Stop"    { Stop-Service    -Name $Name -ErrorAction Stop }
        "Restart" { Restart-Service -Name $Name -ErrorAction Stop }
    }

    # Wait up to 10s for status change
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 500
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    } while ($svc -and $svc.Status.ToString() -eq $prevStatus -and (Get-Date) -lt $deadline)

    $newStatus = if ($svc) { $svc.Status.ToString() } else { "Unknown" }

    return @{
        Name           = $Name
        Action         = $Action
        PreviousStatus = $prevStatus
        NewStatus      = $newStatus
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

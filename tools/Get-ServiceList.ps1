<#
.SYNOPSIS
Lists system services with their name, status, and start type, with optional wildcard filtering.

.PARAMETER Name
Wildcard pattern to filter service names. Defaults to * (all services).
#>
[CmdletBinding()]
param(
    [string]$Name = "*"
)

try {
    $services = Get-Service -Name $Name -ErrorAction SilentlyContinue

    $result = @($services | ForEach-Object {
        $svc = $_
        $startType = $null
        try { $startType = $svc.StartType.ToString() } catch { }

        @{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            Status      = $svc.Status.ToString()
            StartType   = $startType
        }
    })

    return @{
        ServiceCount = $result.Count
        Services     = $result
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

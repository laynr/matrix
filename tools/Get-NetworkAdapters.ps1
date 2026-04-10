<#
.SYNOPSIS
Lists all network adapters with their IP addresses, MAC, gateway, and status.
#>
[CmdletBinding()]
param()

try {
    Add-Type -AssemblyName System.Net.NetworkInformation -ErrorAction SilentlyContinue

    $ifaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()

    $adapters = foreach ($iface in $ifaces) {
        $props      = $iface.GetIPProperties()
        $unicast    = @($props.UnicastAddresses | ForEach-Object { $_.Address.ToString() })
        $gateways   = @($props.GatewayAddresses | ForEach-Object { $_.Address.ToString() })
        $mac        = $iface.GetPhysicalAddress().ToString()
        # Format MAC as XX:XX:XX:XX:XX:XX
        if ($mac.Length -eq 12) {
            $mac = ($mac -replace '(.{2})(?=.)', '$1:')
        }

        @{
            Name        = $iface.Name
            Description = $iface.Description
            MacAddress  = $mac
            Status      = $iface.OperationalStatus.ToString()
            SpeedMbps   = if ($iface.Speed -gt 0) { [math]::Round($iface.Speed / 1MB, 0) } else { $null }
            IPAddresses = $unicast
            Gateway     = if ($gateways.Count -gt 0) { $gateways[0] } else { $null }
            Type        = $iface.NetworkInterfaceType.ToString()
        }
    }

    return @{
        AdapterCount = $adapters.Count
        Adapters     = @($adapters)
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

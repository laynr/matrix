<#
.SYNOPSIS
Tests a hostname via DNS resolution, ICMP ping, and optional TCP port check.

.PARAMETER Hostname
The hostname or IP address to test.

.PARAMETER Port
Optional TCP port to check for connectivity.

.PARAMETER TimeoutMs
Timeout in milliseconds for ping and TCP checks. Defaults to 2000.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Hostname,

    [int]$Port      = 0,
    [int]$TimeoutMs = 2000
)

try {
    $result = @{
        Hostname    = $Hostname
        DnsResolved = $false
        IpAddress   = $null
        Reachable   = $false
        RoundtripMs = $null
        PortOpen    = $null
    }

    # DNS resolve
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($Hostname)
        if ($addrs.Count -gt 0) {
            $result.DnsResolved = $true
            $result.IpAddress   = $addrs[0].ToString()
        }
    } catch {
        $result.DnsResolved = $false
    }

    # ICMP ping
    try {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        $reply = $ping.Send($Hostname, $TimeoutMs)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            $result.Reachable   = $true
            $result.RoundtripMs = $reply.RoundtripTime
        }
        $ping.Dispose()
    } catch {
        $result.Reachable = $false
    }

    # TCP port check (optional)
    if ($Port -gt 0) {
        try {
            $tc = [System.Net.Sockets.TcpClient]::new()
            $connected = $tc.ConnectAsync($Hostname, $Port).Wait($TimeoutMs)
            $result.PortOpen = $connected -and $tc.Connected
            $tc.Dispose()
        } catch {
            $result.PortOpen = $false
        }
    }

    return $result | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

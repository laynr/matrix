<#
.SYNOPSIS
Lists active TCP network connections with local/remote addresses, state, and process info.

.PARAMETER State
Optional filter by connection state (e.g. Established, Listen, TimeWait).
#>
[CmdletBinding()]
param(
    [string]$State = ""
)

try {
    $connections = @()

    if ($IsWindows) {
        $tcpConns = Get-NetTCPConnection -ErrorAction SilentlyContinue
        if ($State) {
            $tcpConns = $tcpConns | Where-Object { $_.State -like "*$State*" }
        }
        foreach ($c in $tcpConns) {
            $procName = $null
            $procId   = $c.OwningProcess
            if ($procId -gt 0) {
                $proc     = Get-Process -Id $procId -ErrorAction SilentlyContinue
                $procName = if ($proc) { $proc.ProcessName } else { $null }
            }
            $connections += @{
                LocalAddress  = $c.LocalAddress
                LocalPort     = $c.LocalPort
                RemoteAddress = $c.RemoteAddress
                RemotePort    = $c.RemotePort
                State         = $c.State.ToString()
                ProcessName   = $procName
                PID           = $procId
            }
        }
    } elseif ($IsLinux) {
        # ss -tn: numeric, tcp, no listening; -a includes listening
        $lines = & ss -tn -a 2>/dev/null | Select-Object -Skip 1
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+' | Where-Object { $_ -ne "" }
            if ($parts.Count -lt 5) { continue }
            $stateVal = $parts[0]
            if ($State -and $stateVal -notlike "*$State*") { continue }

            # local = parts[3], peer = parts[4]
            $localRaw  = $parts[3]
            $remoteRaw = $parts[4]

            $splitLocal  = $localRaw  -match '^(.+):(\d+)$'
            $splitRemote = $remoteRaw -match '^(.+):(\d+)$'

            $connections += @{
                LocalAddress  = if ($splitLocal)  { $Matches[1] } else { $localRaw }
                LocalPort     = if ($splitLocal)  { [int]$Matches[2] } else { $null }
                RemoteAddress = if ($splitRemote) { $Matches[1] } else { $remoteRaw }
                RemotePort    = if ($splitRemote) { [int]$Matches[2] } else { $null }
                State         = $stateVal
                ProcessName   = $null
                PID           = $null
            }
        }
    } elseif ($IsMacOS) {
        # netstat -an -p tcp
        $lines = & netstat -an -p tcp 2>/dev/null | Select-Object -Skip 2
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+' | Where-Object { $_ -ne "" }
            if ($parts.Count -lt 5) { continue }
            # proto recv-q send-q local foreign state
            $stateVal  = if ($parts.Count -ge 6) { $parts[5] } else { $parts[4] }
            if ($State -and $stateVal -notlike "*$State*") { continue }

            $localRaw  = $parts[3]
            $remoteRaw = $parts[4]

            # macOS uses dot notation: 127.0.0.1.8080
            $lDot  = $localRaw.LastIndexOf('.')
            $rDot  = $remoteRaw.LastIndexOf('.')

            $connections += @{
                LocalAddress  = if ($lDot -gt 0) { $localRaw.Substring(0, $lDot)  } else { $localRaw }
                LocalPort     = if ($lDot -gt 0) { $localRaw.Substring($lDot + 1)  } else { $null }
                RemoteAddress = if ($rDot -gt 0) { $remoteRaw.Substring(0, $rDot) } else { $remoteRaw }
                RemotePort    = if ($rDot -gt 0) { $remoteRaw.Substring($rDot + 1) } else { $null }
                State         = $stateVal
                ProcessName   = $null
                PID           = $null
            }
        }
    } else {
        return @{ error = "Unsupported platform." } | ConvertTo-Json -Compress
    }

    return @{
        ConnectionCount = $connections.Count
        Connections     = @($connections)
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

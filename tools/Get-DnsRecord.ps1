<#
.SYNOPSIS
Perform a DNS record lookup for a hostname, returning records of the specified type.

.PARAMETER Hostname
The hostname or domain to query (e.g., github.com).

.PARAMETER Type
DNS record type to query: A, MX, TXT, NS, CNAME, or ANY. Defaults to A.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Hostname,

    [ValidateSet('A','MX','TXT','NS','CNAME','ANY')]
    [string]$Type = "A"
)

try {
    $records = @()

    if ($IsWindows) {
        $resolved = Resolve-DnsName -Name $Hostname -Type $Type -ErrorAction SilentlyContinue
        if ($resolved) {
            foreach ($r in $resolved) {
                $str = switch ($r.Type) {
                    'A'     { $r.IPAddress }
                    'AAAA'  { $r.IPAddress }
                    'MX'    { "$($r.Preference) $($r.NameExchange)" }
                    'TXT'   { $r.Strings -join ' ' }
                    'NS'    { $r.NameHost }
                    'CNAME' { $r.NameHost }
                    'SOA'   { "$($r.PrimaryServer) $($r.Administrator)" }
                    default { "$($r.Name) $($r.Type) $($r.RecordData)" }
                }
                if ($str) { $records += "$str" }
            }
        }
    } else {
        # macOS / Linux — use .NET BCL (no external tools required)
        if ($Type -in @('A', 'AAAA', 'ANY')) {
            $addrs = [System.Net.Dns]::GetHostAddresses($Hostname) | Where-Object {
                $Type -eq 'ANY' -or
                ($Type -eq 'A'    -and $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) -or
                ($Type -eq 'AAAA' -and $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6)
            }
            $records = @($addrs | ForEach-Object { $_.ToString() })
        } else {
            return @{
                error = "Record type '$Type' lookups require 'dig' or 'nslookup' which are not pre-installed on this platform. Only A and AAAA lookups are supported without additional tools."
            } | ConvertTo-Json -Compress
        }
    }

    $records = @($records | Where-Object { $_.Trim() -ne '' } | Select-Object -Unique)

    return @{
        Hostname    = $Hostname
        Type        = $Type
        Records     = $records
        RecordCount = $records.Count
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

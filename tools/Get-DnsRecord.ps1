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
        # macOS / Linux — use nslookup
        $queryType = if ($Type -eq 'ANY') { 'any' } else { $Type.ToLower() }
        $output = & nslookup "-type=$queryType" $Hostname 2>/dev/null

        if ($output) {
            $inAnswer = $false
            foreach ($line in $output) {
                $line = $line.Trim()
                if ($line -match '^Non-authoritative answer|^Authoritative answers') {
                    $inAnswer = $true; continue
                }
                if (-not $inAnswer -and $line -match '^Name:\s+\S') { $inAnswer = $true }
                if (-not $inAnswer) { continue }

                # Parse common record types
                if ($line -match 'address\s+(.+)$')        { $records += $Matches[1].Trim() }
                elseif ($line -match 'mail exchanger\s+(.+)$') { $records += $Matches[1].Trim() }
                elseif ($line -match 'name server\s*=\s*(.+)$') { $records += $Matches[1].Trim() }
                elseif ($line -match 'canonical name\s*=\s*(.+)$') { $records += $Matches[1].Trim() }
                elseif ($line -match 'text\s*=\s*"(.+)"$') { $records += $Matches[1].Trim() }
                elseif ($line -match '"\s*(.+?)\s*"')       { $records += $Matches[1].Trim() }
                elseif ($line -match '^Name:\s+(.+)$')      { $records += $Matches[1].Trim() }
            }
        }

        # Fallback: try dig if nslookup returned nothing
        if ($records.Count -eq 0) {
            $dig = Get-Command 'dig' -ErrorAction SilentlyContinue
            if ($dig) {
                $digOut = & dig +short $Hostname $Type 2>/dev/null
                if ($digOut) { $records = @($digOut | Where-Object { $_.Trim() }) }
            }
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

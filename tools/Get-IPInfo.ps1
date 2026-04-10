<#
.SYNOPSIS
Returns the public IP address and geolocation information for this machine or a given IP address.

.PARAMETER IPAddress
Optional. An IP address to look up. Defaults to the current machine's public IP.
#>
[CmdletBinding()]
param(
    [string]$IPAddress = ""
)

try {
    $url = if ($IPAddress) {
        "https://ipinfo.io/$IPAddress/json"
    } else {
        "https://ipinfo.io/json"
    }

    $data = Invoke-RestMethod -Uri $url -TimeoutSec 15 -ErrorAction Stop

    if ($data.error) {
        return @{ error = $data.error.message } | ConvertTo-Json -Compress
    }

    # loc is "lat,lon" — split for convenience
    $lat, $lon = if ($data.loc) { $data.loc -split ',' } else { $null, $null }

    return @{
        IP          = $data.ip
        City        = $data.city
        Region      = $data.region
        Country     = $data.country
        Postal      = $data.postal
        Latitude    = $lat
        Longitude   = $lon
        Timezone    = $data.timezone
        ISP         = $data.org
        Hostname    = $data.hostname
    } | ConvertTo-Json -Depth 3 -Compress
} catch {
    return @{ error = "IP lookup failed: $($_.Exception.Message)" } | ConvertTo-Json -Compress
}

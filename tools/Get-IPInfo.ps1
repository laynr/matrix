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
        "https://ipapi.co/$IPAddress/json/"
    } else {
        "https://ipapi.co/json/"
    }

    $data = Invoke-RestMethod -Uri $url -TimeoutSec 10 -ErrorAction Stop

    if ($data.error) {
        return @{ error = $data.reason } | ConvertTo-Json -Compress
    }

    return @{
        IP          = $data.ip
        City        = $data.city
        Region      = $data.region
        Country     = $data.country_name
        CountryCode = $data.country_code
        Postal      = $data.postal
        Latitude    = $data.latitude
        Longitude   = $data.longitude
        Timezone    = $data.timezone
        ISP         = $data.org
    } | ConvertTo-Json -Compress
} catch {
    return @{ error = "IP lookup failed: $($_.Exception.Message)" } | ConvertTo-Json -Compress
}

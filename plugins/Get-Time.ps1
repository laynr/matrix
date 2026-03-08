<#
.SYNOPSIS
Gets the current system time and timezone.

.DESCRIPTION
This tool determines the local system's date, time, and timezone information. It should be used whenever the user asks for the current time or date.
#>
[CmdletBinding()]
param()

$date = Get-Date
$timezone = [System.TimeZoneInfo]::Local

$result = @{
    Time = $date.ToString("yyyy-MM-dd HH:mm:ss")
    TimeZone = $timezone.Id
    UtcOffset = $timezone.BaseUtcOffset.ToString()
}

return $result | ConvertTo-Json -Depth 5 -Compress

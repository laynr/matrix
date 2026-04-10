<#
.SYNOPSIS
Gets the current system time and timezone.

.DESCRIPTION
This tool determines the local system's date, time, and timezone information. ONLY USE THIS TOOL if the user explicitly asks "What time is it" or "What is today's date". DO NOT use this tool to add context to other queries.
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

return $result | ConvertTo-Json -Depth 3 -Compress

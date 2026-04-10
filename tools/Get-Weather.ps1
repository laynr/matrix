<#
.SYNOPSIS
Gets the current real-time weather forecast for a specified city using wttr.in.

.DESCRIPTION
This tool fetches real-time weather information from the internet. Use this when the user asks for the weather in a specific location. Do not use this tool if the user is not explicitly asking about the weather.

.PARAMETER City
The city name to fetch weather for (e.g. "London", "New York", "Tokyo").
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$City
)

try {
    $encodedCity = [uri]::EscapeDataString($City)
    $url = "https://wttr.in/${encodedCity}?format=j1"
    
    $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
    $current = $response.current_condition[0]
    $area = $response.nearest_area[0]

    $result = @{
        Location = "$($area.areaName[0].value), $($area.country[0].value)"
        Temperature = "$($current.temp_C) C / $($current.temp_F) F"
        FeelsLike = "$($current.FeelsLikeC) C / $($current.FeelsLikeF) F"
        Condition = $current.weatherDesc[0].value
        Humidity = "$($current.humidity)%"
        Wind = "$($current.windspeedKmph) km/h $($current.winddir16Point)"
        ObservationTime = $current.observation_time
    }

    return $result | ConvertTo-Json -Depth 5 -Compress
} catch {
    return @{ error = "Failed to fetch weather for '$City': $($_.Exception.Message)" } | ConvertTo-Json -Compress
}

<#
.SYNOPSIS
Converts a value between units of measurement. Supports temperature, length, weight, data size, and speed.

.PARAMETER Value
The numeric value to convert.

.PARAMETER From
The unit to convert from (e.g. "C", "km", "kg", "MB", "mph").

.PARAMETER To
The unit to convert to (e.g. "F", "miles", "lbs", "GB", "kph").
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [double]$Value,

    [Parameter(Mandatory=$true)]
    [string]$From,

    [Parameter(Mandatory=$true)]
    [string]$To
)

$From = $From.Trim().ToLower()
$To   = $To.Trim().ToLower()

# Conversion table — normalise everything to a base unit first, then to target
# Base units: kelvin (temp), metres (length), kilograms (weight), bytes (data), m/s (speed)
$toBase = @{
    # Temperature (store offset separately — handled below)
    "c" = "temp_c"; "celsius" = "temp_c"
    "f" = "temp_f"; "fahrenheit" = "temp_f"
    "k" = "temp_k"; "kelvin" = "temp_k"
    # Length → metres
    "m" = 1.0; "metre" = 1.0; "meter" = 1.0; "metres" = 1.0; "meters" = 1.0
    "km" = 1000.0; "kilometre" = 1000.0; "kilometer" = 1000.0
    "cm" = 0.01; "centimetre" = 0.01; "centimeter" = 0.01
    "mm" = 0.001; "millimetre" = 0.001; "millimeter" = 0.001
    "mi" = 1609.344; "mile" = 1609.344; "miles" = 1609.344
    "ft" = 0.3048; "foot" = 0.3048; "feet" = 0.3048
    "in" = 0.0254; "inch" = 0.0254; "inches" = 0.0254
    "yd" = 0.9144; "yard" = 0.9144; "yards" = 0.9144
    # Weight → kilograms
    "kg" = 1.0; "kilogram" = 1.0; "kilograms" = 1.0
    "g"  = 0.001; "gram" = 0.001; "grams" = 0.001
    "mg" = 0.000001; "milligram" = 0.000001
    "lb" = 0.453592; "lbs" = 0.453592; "pound" = 0.453592; "pounds" = 0.453592
    "oz" = 0.0283495; "ounce" = 0.0283495; "ounces" = 0.0283495
    "t"  = 1000.0; "tonne" = 1000.0; "tonnes" = 1000.0
    "ton" = 907.185; "tons" = 907.185  # US short ton
    # Data → bytes
    "b"   = 1.0; "byte" = 1.0; "bytes" = 1.0
    "kb"  = 1024.0; "kilobyte" = 1024.0; "kilobytes" = 1024.0
    "mb"  = 1048576.0; "megabyte" = 1048576.0; "megabytes" = 1048576.0
    "gb"  = 1073741824.0; "gigabyte" = 1073741824.0; "gigabytes" = 1073741824.0
    "tb"  = 1099511627776.0; "terabyte" = 1099511627776.0; "terabytes" = 1099511627776.0
    "kib" = 1024.0; "mib" = 1048576.0; "gib" = 1073741824.0; "tib" = 1099511627776.0
    # Speed → m/s
    "mps"  = 1.0; "m/s" = 1.0
    "kph"  = 0.277778; "kmh" = 0.277778; "km/h" = 0.277778
    "mph"  = 0.44704; "mi/h" = 0.44704
    "knot" = 0.514444; "knots" = 0.514444; "kt" = 0.514444
}

try {
    # Temperature — special-case non-linear conversions
    $tempUnits = @("temp_c","temp_f","temp_k")
    $fromType  = $toBase[$From]
    $toType    = $toBase[$To]

    if ($null -eq $fromType) { return @{ error = "Unknown unit: '$From'" } | ConvertTo-Json -Compress }
    if ($null -eq $toType)   { return @{ error = "Unknown unit: '$To'" }   | ConvertTo-Json -Compress }

    if ($fromType -in $tempUnits -or $toType -in $tempUnits) {
        if ($fromType -notin $tempUnits -or $toType -notin $tempUnits) {
            return @{ error = "Cannot mix temperature units with other unit types." } | ConvertTo-Json -Compress
        }
        # Convert to Kelvin first
        $kelvin = switch ($fromType) {
            "temp_c" { $Value + 273.15 }
            "temp_f" { ($Value + 459.67) * 5/9 }
            "temp_k" { $Value }
        }
        $result = switch ($toType) {
            "temp_c" { $kelvin - 273.15 }
            "temp_f" { $kelvin * 9/5 - 459.67 }
            "temp_k" { $kelvin }
        }
    } else {
        # Same physical dimension check (rough: same magnitude class)
        $baseValue = $Value * [double]$fromType
        $result    = $baseValue / [double]$toType
    }

    return @{
        Input  = "$Value $From"
        Output = "$([math]::Round($result, 6)) $To"
        Result = [math]::Round($result, 6)
    } | ConvertTo-Json -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

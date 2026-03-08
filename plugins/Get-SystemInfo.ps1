<#
.SYNOPSIS
Retrieves basic local system information such as OS version, Memory, and CPU load.

.DESCRIPTION
This tool fetches live diagnostics from the local host machine. Use this when the user asks about the computer's specs, operating system, or current resource status.
#>
[CmdletBinding()]
param()

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $cpu = Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average -ErrorAction Stop
    
    $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
    
    $result = @{
        OSArchitecture = $os.OSArchitecture
        OSCaption = $os.Caption
        OSVersion = $os.Version
        CPULoadPercent = $cpu.Average
        TotalMemoryGB = $totalMemoryGB
        FreeMemoryGB = $freeMemoryGB
        UsedMemoryGB = $usedMemoryGB
    }
    
    return $result | ConvertTo-Json -Depth 5 -Compress
} catch {
    return @{ error = "Failed to retrieve system info: $($_.Exception.Message)" } | ConvertTo-Json -Compress
}

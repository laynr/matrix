<#
.SYNOPSIS
Retrieves local system information: OS, architecture, CPU, and memory.

.DESCRIPTION
Cross-platform tool. Works on Windows, macOS, and Linux via PowerShell 7+.
#>
[CmdletBinding()]
param()

$os   = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$fw   = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription

$result = @{
    OS            = $os
    Architecture  = [string]$arch
    Framework     = $fw
}

# ── Memory ────────────────────────────────────────────────────────────────────
try {
    if ($IsWindows) {
        $mem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $result.TotalMemoryGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 2)
        $result.FreeMemoryGB  = [math]::Round($mem.FreePhysicalMemory / 1MB, 2)

    } elseif ($IsMacOS) {
        $totalBytes = sysctl -n hw.memsize 2>$null
        $result.TotalMemoryGB = [math]::Round([long]$totalBytes / 1GB, 2)
        # vm_stat reports pages; page size is 4096 bytes on Apple Silicon
        $vmStat    = vm_stat 2>$null
        $freePages = ($vmStat | Select-String "Pages free:"     ).ToString() -replace "[^\d]"
        $specPages = ($vmStat | Select-String "Pages speculative").ToString() -replace "[^\d]"
        $pageSize  = 4096
        $freeBytes = ([long]$freePages + [long]$specPages) * $pageSize
        $result.FreeMemoryGB = [math]::Round($freeBytes / 1GB, 2)

    } elseif ($IsLinux) {
        $memInfo = Get-Content /proc/meminfo -ErrorAction Stop
        $total   = ($memInfo | Select-String "MemTotal:").ToString()  -replace "[^\d]"
        $free    = ($memInfo | Select-String "MemAvailable:").ToString() -replace "[^\d]"
        $result.TotalMemoryGB = [math]::Round([long]$total / 1MB, 2)
        $result.FreeMemoryGB  = [math]::Round([long]$free  / 1MB, 2)
    }
    $result.UsedMemoryGB = [math]::Round($result.TotalMemoryGB - $result.FreeMemoryGB, 2)
} catch {
    $result.MemoryError = $_.Exception.Message
}

# ── CPU load ──────────────────────────────────────────────────────────────────
try {
    if ($IsWindows) {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop |
               Measure-Object -Property LoadPercentage -Average
        $result.CPULoadPercent = [math]::Round($cpu.Average, 1)
    } elseif ($IsMacOS) {
        $top = top -l 1 -n 0 2>$null | Select-String "CPU usage"
        if ($top) {
            $user   = [double](($top.ToString() -replace '.*?(\d+\.\d+)% user.*','$1'))
            $sys    = [double](($top.ToString() -replace '.*?(\d+\.\d+)% sys.*','$1'))
            $result.CPULoadPercent = [math]::Round($user + $sys, 1)
        }
    } elseif ($IsLinux) {
        # One-shot CPU idle reading from /proc/stat
        $stat1 = (Get-Content /proc/stat)[0] -split '\s+'
        Start-Sleep -Milliseconds 200
        $stat2 = (Get-Content /proc/stat)[0] -split '\s+'
        $idle1 = [long]$stat1[4]; $total1 = ($stat1[1..8] | Measure-Object -Sum).Sum
        $idle2 = [long]$stat2[4]; $total2 = ($stat2[1..8] | Measure-Object -Sum).Sum
        $result.CPULoadPercent = [math]::Round((1 - ($idle2 - $idle1) / ($total2 - $total1)) * 100, 1)
    }
} catch {
    $result.CPUError = $_.Exception.Message
}

return $result | ConvertTo-Json -Depth 3 -Compress

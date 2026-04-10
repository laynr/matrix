<#
.SYNOPSIS
Lists scheduled tasks from the Windows Task Scheduler or crontab on Linux and macOS.

.PARAMETER Name
Wildcard filter for task names (Windows only). Defaults to * (all tasks).
#>
[CmdletBinding()]
param(
    [string]$Name = "*"
)

try {
    $tasks    = @()
    $platform = ""

    if ($IsWindows) {
        $platform = "Windows"
        $raw = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        foreach ($t in $raw) {
            $tasks += @{
                TaskName    = $t.TaskName
                TaskPath    = $t.TaskPath
                State       = $t.State.ToString()
                Description = $t.Description
            }
        }
    } elseif ($IsMacOS -or $IsLinux) {
        $platform = if ($IsMacOS) { "macOS" } else { "Linux" }
        $crontab  = & crontab -l 2>/dev/null
        foreach ($line in $crontab) {
            $line = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
            # cron format: min hour dom month dow command
            $parts = $line -split '\s+', 6
            if ($parts.Count -ge 6) {
                $schedule = "$($parts[0]) $($parts[1]) $($parts[2]) $($parts[3]) $($parts[4])"
                $command  = $parts[5]
            } else {
                $schedule = $line
                $command  = $line
            }
            $tasks += @{
                TaskName    = $command
                TaskPath    = $null
                State       = "Ready"
                Description = $schedule
            }
        }

        # Also check /etc/crontab and /etc/cron.d on Linux
        if ($IsLinux) {
            $cronFiles = @("/etc/crontab") + @(Get-ChildItem "/etc/cron.d" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
            foreach ($cf in $cronFiles) {
                if (-not (Test-Path $cf)) { continue }
                foreach ($line in (Get-Content $cf -ErrorAction SilentlyContinue)) {
                    $line = $line.Trim()
                    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
                    $tasks += @{
                        TaskName    = $line
                        TaskPath    = $cf
                        State       = "Ready"
                        Description = "system crontab"
                    }
                }
            }
        }
    } else {
        return @{ error = "Unsupported platform." } | ConvertTo-Json -Compress
    }

    return @{
        Platform  = $platform
        TaskCount = $tasks.Count
        Tasks     = @($tasks)
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

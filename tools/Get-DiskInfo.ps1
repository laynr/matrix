<#
.SYNOPSIS
Lists all disk drives and volumes with capacity, free space, and filesystem type.
#>
[CmdletBinding()]
param()

try {
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }

    $result = foreach ($d in $drives) {
        $total  = $d.TotalSize
        $free   = $d.AvailableFreeSpace
        $used   = $total - $free
        $pctFree = if ($total -gt 0) { [math]::Round($free / $total * 100, 1) } else { 0 }

        @{
            Name        = $d.Name
            Label       = $d.VolumeLabel
            FileSystem  = $d.DriveFormat
            DriveType   = $d.DriveType.ToString()
            TotalGB     = [math]::Round($total  / 1GB, 2)
            FreeGB      = [math]::Round($free   / 1GB, 2)
            UsedGB      = [math]::Round($used   / 1GB, 2)
            PercentFree = $pctFree
        }
    }

    return @{
        DriveCount = @($result).Count
        Drives     = @($result)
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

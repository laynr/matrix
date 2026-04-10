function Write-MatrixLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )

    $logPath = Join-Path $global:MatrixRoot "err.log"
    $line    = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $mutex   = $null
    try {
        $mutexName = if ($IsWindows) { 'Global\MatrixLogMutex' } else { 'MatrixLogMutex' }
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        [void]$mutex.WaitOne(3000)
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } finally {
        try { $mutex.ReleaseMutex() } catch {}
        if ($mutex) { $mutex.Dispose() }
    }
}

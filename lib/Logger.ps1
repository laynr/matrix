function Write-MatrixLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $logPath = Join-Path $global:MatrixRoot "err.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message | Out-File $logPath -Append -Encoding UTF8
}

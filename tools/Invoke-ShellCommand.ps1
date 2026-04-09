<#
.SYNOPSIS
Runs a shell command and returns its stdout and stderr output.

.PARAMETER Command
The command to execute (e.g. "ls -la", "git status", "npm list").

.PARAMETER WorkingDirectory
Directory to run the command in. Defaults to the current directory.

.PARAMETER TimeoutSeconds
Maximum seconds to wait for the command to finish. Defaults to 30.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Command,

    [string]$WorkingDirectory = "",
    [int]$TimeoutSeconds      = 30
)

try {
    # Split command into executable + arguments
    $parts = $Command.Trim() -split '\s+', 2
    $exe   = $parts[0]
    $args  = if ($parts.Count -gt 1) { $parts[1] } else { "" }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $exe
    $psi.Arguments              = $args
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    } elseif ($WorkingDirectory) {
        return @{ error = "Working directory not found: $WorkingDirectory" } | ConvertTo-Json -Compress
    }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)

    if (-not $exited) {
        $proc.Kill()
        return @{ error = "Command timed out after $TimeoutSeconds seconds." } | ConvertTo-Json -Compress
    }

    return @{
        Command    = $Command
        ExitCode   = $proc.ExitCode
        Stdout     = $stdout.TrimEnd()
        Stderr     = $stderr.TrimEnd()
    } | ConvertTo-Json -Depth 4 -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

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
    # Route through the platform shell so quoted arguments and shell syntax work correctly.
    # Using ArgumentList (not Arguments string) passes the command as a single atomic argument,
    # avoiding the naive whitespace-split that breaks paths or args containing spaces.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    if ($IsWindows) {
        $psi.FileName = "cmd.exe"
        $psi.ArgumentList.Add("/c")
        $psi.ArgumentList.Add($Command)
    } else {
        $psi.FileName = "/bin/sh"
        $psi.ArgumentList.Add("-c")
        $psi.ArgumentList.Add($Command)
    }
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
    # Read streams asynchronously to prevent deadlock when buffer fills
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)

    if (-not $exited) {
        try { $proc.Kill() } catch {}
        return @{ error = "Command timed out after $TimeoutSeconds seconds." } | ConvertTo-Json -Compress
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    return @{
        Command    = $Command
        ExitCode   = $proc.ExitCode
        Stdout     = $stdout.TrimEnd()
        Stderr     = $stderr.TrimEnd()
    } | ConvertTo-Json -Depth 3 -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}

# Animated spinner while waiting for Ollama. Runs animation in a separate
# PowerShell instance so the main thread can do the actual API call.
function Invoke-WithSpinner {
    param([scriptblock]$Action, [string]$Label = "thinking")

    $done = [System.Threading.ManualResetEventSlim]::new($false)
    $ps   = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($evt, $lbl)
        $frames = '⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏'
        $i = 0
        while (-not $evt.IsSet) {
            [Console]::Write("`r  $($frames[$i % 10]) $lbl...")
            [System.Threading.Thread]::Sleep(80)
            $i++
        }
        [Console]::Write("`r" + (' ' * ($lbl.Length + 16)) + "`r")
    }).AddArgument($done).AddArgument($Label) | Out-Null

    $handle = $ps.BeginInvoke()
    try   { return & $Action }
    finally {
        $done.Set()
        [void]$ps.EndInvoke($handle)
        $ps.Dispose()
    }
}

function Show-MatrixCLI {
    # Read version from .version file if present
    $versionFile = Join-Path $global:MatrixRoot ".version"
    $versionStr  = ""
    if (Test-Path $versionFile) {
        try {
            $v = Get-Content $versionFile -Raw | ConvertFrom-Json
            if ($v.PublishedAt) {
                $versionStr = "  Version  : $([datetime]$v.PublishedAt | Get-Date -Format 'yyyy-MM-dd')"
            }
        } catch {}
    }

    Write-Host ""
    Write-Host "  +----------------------------------+" -ForegroundColor Cyan
    Write-Host "  |          M A T R I X             |" -ForegroundColor Cyan
    Write-Host "  |     AI Agent  *  Ollama           |" -ForegroundColor Cyan
    Write-Host "  +----------------------------------+" -ForegroundColor Cyan
    Write-Host "  Model    : $($global:Config.Model)"
    Write-Host "  Endpoint : $($global:Config.Endpoint)"
    if ($versionStr) { Write-Host $versionStr }
    $tools = Get-MatrixTools
    Write-Host "  Tools    : $($tools.Count) loaded"
    Write-Host ""
    Write-Host "  Type 'reload' to rescan tools.  Type 'exit' to quit."
    Write-Host ("─" * 42)

    while ($true) {
        Write-Host ""
        $inputMsg = Read-Host "You"
        if ([string]::IsNullOrWhiteSpace($inputMsg)) { continue }

        switch ($inputMsg.Trim().ToLower()) {
            "exit"   { return }
            "quit"   { return }
            "reload" {
                # Force cache invalidation by clearing mtime table
                $script:ToolCacheMtime = @{}
                $tools = Get-MatrixTools
                Write-Host "  Tools reloaded: $($tools.Count) ($( ($tools | ForEach-Object { $_.function.name }) -join ', '))" -ForegroundColor Cyan
                continue
            }
        }

        Add-Message -Role "user" -Content $inputMsg

        try {
            $response = Invoke-WithSpinner -Action {
                Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $tools
            }

            if ($response.error) {
                Write-Host "  [error] $($response.error)" -ForegroundColor Red
                continue
            }

            $msg = $response.message
            Process-OllamaMessage -Msg $msg -Tools $tools
            Prune-Context

        } catch {
            Write-Host "  [exception] $_" -ForegroundColor Red
        }
    }
}

# Handles one assistant message: prints text, executes tool calls, recurses for the follow-up.
function Process-OllamaMessage {
    param(
        [object]$Msg,
        [array]$Tools,
        [int]$Depth = 0
    )

    if ($Depth -ge 10) {
        Write-Host "  [warn] Max tool call depth reached — stopping." -ForegroundColor Yellow
        return
    }

    $result = Invoke-MatrixToolchain -Message $Msg

    # Print text response (may be empty if the model only called tools)
    if (-not [string]::IsNullOrWhiteSpace($result.TextOutput)) {
        Write-Host ""
        Write-Host "Matrix: $($result.TextOutput)"
    }

    if ($result.HasTools) {
        # Add the assistant's tool-call message to history
        Add-Message -Role "assistant" -Content $result.TextOutput

        # Add each tool result as a separate "tool" message
        foreach ($tr in $result.ToolResults) {
            Add-Message -Role $tr.role -Content $tr.content
        }

        $followUp = Invoke-WithSpinner -Label "processing" -Action {
            Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $Tools
        }

        if ($followUp.error) {
            Write-Host "  [error] $($followUp.error)" -ForegroundColor Red
        } elseif ($followUp.message) {
            Process-OllamaMessage -Msg $followUp.message -Tools $Tools -Depth ($Depth + 1)
        }
    } else {
        # Plain text reply — add to history
        Add-Message -Role "assistant" -Content $result.TextOutput
    }
}

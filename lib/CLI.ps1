# ── Spinner ───────────────────────────────────────────────────────────────────
# Use Start-MatrixSpinner / Stop-MatrixSpinner so the actual API call stays in
# the caller's scope (avoids PowerShell dynamic-scope issues with & $action).

function Start-MatrixSpinner {
    param([string]$Label = "thinking")

    # Braille frames on UTF-8 terminals; ASCII fallback for old Windows consoles
    $frames = if ($IsWindows -and [Console]::OutputEncoding.CodePage -ne 65001) {
        @('|', '/', '-', '\')
    } else {
        @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    }

    $done = [System.Threading.ManualResetEventSlim]::new($false)
    $ps   = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($evt, $lbl, $fr)
        $i = 0
        while (-not $evt.IsSet) {
            [Console]::Write("`r  $($fr[$i % $fr.Count]) $lbl...")
            [System.Threading.Thread]::Sleep(80)
            $i++
        }
        # Clear spinner line completely
        [Console]::Write("`r" + (' ' * ($lbl.Length + 16)) + "`r")
    }).AddArgument($done).AddArgument($Label).AddArgument($frames) | Out-Null

    return [PSCustomObject]@{
        Done   = $done
        PS     = $ps
        Handle = $ps.BeginInvoke()
    }
}

function Stop-MatrixSpinner {
    param($Spinner)
    if (-not $Spinner) { return }
    $Spinner.Done.Set()
    [void]$Spinner.PS.EndInvoke($Spinner.Handle)
    $Spinner.PS.Dispose()
}

# ── CLI entry point ───────────────────────────────────────────────────────────
function Show-MatrixCLI {
    # Version from .version file
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
                # Force full cache rebuild
                $script:ToolCache      = $null
                $script:ToolCacheMtime = @{}
                $tools = Get-MatrixTools
                Write-Host "  Tools reloaded: $($tools.Count) ($( ($tools | ForEach-Object { $_.function.name }) -join ', '))" -ForegroundColor Cyan
                continue
            }
        }

        Add-Message -Role "user" -Content $inputMsg

        try {
            # Spinner runs in background thread; API call runs inline (correct scope)
            $sp       = Start-MatrixSpinner
            $response = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $tools
            Stop-MatrixSpinner $sp

            if ($response.error) {
                Write-Host "  [error] $($response.error)" -ForegroundColor Red
                continue
            }

            Process-OllamaMessage -Msg $response.message -Tools $tools
            Prune-Context

        } catch {
            Write-Host "  [exception] $_" -ForegroundColor Red
        }
    }
}

# Handles one assistant message: prints text, executes tool calls, recurses for follow-up.
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

    if (-not [string]::IsNullOrWhiteSpace($result.TextOutput)) {
        Write-Host ""
        Write-Host "Matrix: $($result.TextOutput)"
    }

    if ($result.HasTools) {
        Add-Message -Role "assistant" -Content $result.TextOutput
        foreach ($tr in $result.ToolResults) {
            Add-Message -Role $tr.role -Content $tr.content
        }

        $sp      = Start-MatrixSpinner "processing"
        $followUp = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $Tools
        Stop-MatrixSpinner $sp

        if ($followUp.error) {
            Write-Host "  [error] $($followUp.error)" -ForegroundColor Red
        } elseif ($followUp.message) {
            Process-OllamaMessage -Msg $followUp.message -Tools $Tools -Depth ($Depth + 1)
        }
    } else {
        Add-Message -Role "assistant" -Content $result.TextOutput
    }
}

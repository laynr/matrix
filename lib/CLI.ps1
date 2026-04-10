# ── Spinner ───────────────────────────────────────────────────────────────────
# Utility spinner for long-running operations (not used in the streaming agent
# loop — streaming output provides live feedback on its own).

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
    $Spinner.Done.Dispose()
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
                $script:ToolCache      = $null
                $script:ToolCacheMtime = @{}
                $tools = Get-MatrixTools
                Write-Host "  Tools reloaded: $($tools.Count) ($( ($tools | ForEach-Object { $_.function.name }) -join ', '))" -ForegroundColor Cyan
                if ($script:ToolDiscoveryErrors -and $script:ToolDiscoveryErrors.Count -gt 0) {
                    foreach ($e in $script:ToolDiscoveryErrors) {
                        Write-Host "  [warn] '$($e.Name)' failed to load: $($e.Error)" -ForegroundColor Yellow
                    }
                }
                continue
            }
        }

        Add-Message -Role "user" -Content $inputMsg

        try {
            Process-OllamaMessage -Tools $tools
            Prune-Context
        } catch {
            Write-Host "  [exception] $_" -ForegroundColor Red
        }
    }
}

# Streams one assistant response, executes any tool calls, and recurses for
# follow-up responses until the model stops calling tools.
function Process-OllamaMessage {
    param(
        [array]$Tools,
        [int]$Depth = 0
    )

    if ($Depth -ge 10) {
        Write-Host "  [warn] Max tool call depth reached — stopping." -ForegroundColor Yellow
        return
    }

    # Print prefix then stream — tokens appear live as the model generates them
    Write-Host ""
    Write-Host -NoNewline "  Matrix: " -ForegroundColor Cyan
    $response = Invoke-MatrixStreamingChat -Config $global:Config -Messages (Get-Messages) -Tools $Tools
    Write-Host ""  # newline after last token (or after blank tool-only response)

    if ($response.error) {
        Write-Host "  [error] $($response.error)" -ForegroundColor Red
        return
    }

    # Dispatch any tool calls (runs in parallel runspaces)
    $result = Invoke-MatrixToolchain -Message $response.message

    # Always record the assistant turn
    Add-Message -Role "assistant" -Content $result.TextOutput

    if ($result.HasTools) {
        foreach ($tr in $result.ToolResults) {
            Add-Message -Role $tr.role -Content $tr.content
        }
        # Follow-up: model synthesizes tool results into a final answer
        Process-OllamaMessage -Tools $Tools -Depth ($Depth + 1)
    }
}

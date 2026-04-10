# ── CLI helpers ───────────────────────────────────────────────────────────────

function Show-MatrixError {
    param([string]$Message)
    $inner  = "  $Message  "
    $width  = [math]::Max($inner.Length, 10)
    $bar    = "─" * $width
    Write-Host ""
    Write-Host "  ┌$bar┐" -ForegroundColor Red
    Write-Host "  │$inner│" -ForegroundColor Red
    Write-Host "  └$bar┘" -ForegroundColor Red
    Write-Host ""
}

function Show-ContextStatus {
    if ($global:MatrixMessages.Count -eq 0) { return }
    $total = Get-ContextTokenCount
    if ($total -le 0) { return }
    $max   = if ($global:Config.MaxTokens) { $global:Config.MaxTokens } else { 100000 }
    $pct   = [math]::Round($total / $max * 100)
    $color = if ($pct -ge 90) { "Red" } elseif ($pct -ge 75) { "Yellow" } elseif ($pct -ge 50) { "DarkYellow" } else { "DarkGray" }
    Write-Host "  [ctx ~$total tok · $pct%]" -ForegroundColor $color
}

function Show-MatrixHelp {
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor Cyan
    Write-Host "    exit    " -NoNewline -ForegroundColor White
    Write-Host "— quit Matrix"
    Write-Host "    quit    " -NoNewline -ForegroundColor White
    Write-Host "— quit Matrix"
    Write-Host "    reload  " -NoNewline -ForegroundColor White
    Write-Host "— rescan tools/ directory"
    Write-Host "    clear   " -NoNewline -ForegroundColor White
    Write-Host "— reset conversation history"
    Write-Host "    tools   " -NoNewline -ForegroundColor White
    Write-Host "— list loaded tools with descriptions"
    Write-Host "    help    " -NoNewline -ForegroundColor White
    Write-Host "— show this help"
    Write-Host ""
}

function Show-MatrixToolsList {
    $t = Get-MatrixTools
    Write-Host ""
    Write-Host "  Loaded tools ($($t.Count)):" -ForegroundColor Cyan
    foreach ($tool in ($t | Sort-Object { $_.function.name })) {
        Write-Host "    $($tool.function.name.PadRight(26))" -NoNewline -ForegroundColor White
        Write-Host " $($tool.function.description)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ── CLI entry point ───────────────────────────────────────────────────────────
function Show-MatrixCLI {
    $versionStr = ""
    $versionFile = Join-Path $global:MatrixRoot ".version"
    if (Test-Path $versionFile) {
        try {
            $v = Get-Content $versionFile -Raw | ConvertFrom-Json
            if ($v.PublishedAt) {
                $versionStr = "$([datetime]$v.PublishedAt | Get-Date -Format 'yyyy-MM-dd')"
            }
        } catch {}
    }

    $tools  = Get-MatrixTools
    $max    = if ($global:Config.MaxTokens)   { $global:Config.MaxTokens }   else { 100000 }
    $sumAt  = if ($global:Config.SummarizeAt) { $global:Config.SummarizeAt } else { 75000 }
    $ep     = $global:Config.Endpoint
    if ($ep.Length -gt 45) { $ep = $ep.Substring(0, 42) + '...' }
    $sep    = "─" * 52

    Write-Host ""
    Write-Host "  $sep" -ForegroundColor DarkCyan
    Write-Host "   M A T R I X  ·  AI Agent  ·  Ollama" -ForegroundColor Cyan
    Write-Host "  $sep" -ForegroundColor DarkCyan
    Write-Host "   Model    : $($global:Config.Model)"
    Write-Host "   Endpoint : $ep"
    Write-Host "   Context  : $max max tokens · summarize at $sumAt" -ForegroundColor DarkGray
    Write-Host "   Tools    : $($tools.Count) loaded"
    if ($versionStr) { Write-Host "   Version  : $versionStr" -ForegroundColor DarkGray }
    Write-Host "  $sep" -ForegroundColor DarkCyan
    Write-Host "   Type 'help' for commands · 'exit' to quit" -ForegroundColor DarkGray
    Write-Host ""

    # Report any broken tools discovered at startup
    if ($script:ToolDiscoveryErrors -and $script:ToolDiscoveryErrors.Count -gt 0) {
        foreach ($e in $script:ToolDiscoveryErrors) {
            Write-Host "  [warn] '$($e.Name)' failed to load: $($e.Error)" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    while ($true) {
        Show-ContextStatus
        Write-Host ""
        $inputMsg = Read-Host "You"
        if ([string]::IsNullOrWhiteSpace($inputMsg)) { continue }

        switch ($inputMsg.Trim().ToLower()) {
            "exit"   { return }
            "quit"   { return }
            "reload" {
                Reset-ToolCache
                $tools = Get-MatrixTools
                Write-Host "  Tools reloaded: $($tools.Count) ($( ($tools | ForEach-Object { $_.function.name }) -join ', '))" -ForegroundColor Cyan
                if ($script:ToolDiscoveryErrors -and $script:ToolDiscoveryErrors.Count -gt 0) {
                    foreach ($e in $script:ToolDiscoveryErrors) {
                        Write-Host "  [warn] '$($e.Name)' failed to load: $($e.Error)" -ForegroundColor Yellow
                    }
                }
                continue
            }
            "clear" {
                Clear-Messages
                Write-Host "  Context cleared." -ForegroundColor DarkGray
                continue
            }
            "help" {
                Show-MatrixHelp
                continue
            }
            "tools" {
                Show-MatrixToolsList
                continue
            }
        }

        Add-Message -Role "user" -Content $inputMsg

        try {
            Process-OllamaMessage -Tools $tools
            Prune-Context
        } catch {
            Show-MatrixError $_
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

    $maxDepth = if ($global:Config.MaxDepth) { $global:Config.MaxDepth } else { 10 }
    if ($Depth -ge $maxDepth) {
        Write-Host "  [warn] Max tool call depth ($maxDepth) reached — stopping." -ForegroundColor Yellow
        return
    }

    # Turn separator + streaming prefix
    Write-Host ""
    Write-Host ("  " + "─" * 50) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host -NoNewline "  Matrix ▸ " -ForegroundColor Cyan
    $response = Invoke-MatrixStreamingChat -Config $global:Config -Messages (Get-Messages) -Tools $Tools
    Write-Host ""  # newline after last streamed token

    if ($response.error) {
        Show-MatrixError $response.error
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

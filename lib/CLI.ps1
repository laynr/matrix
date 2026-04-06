$LibRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($null -eq $LibRoot) { $LibRoot = "." }
. (Join-Path $LibRoot "Logger.ps1")

function Show-MatrixCLI {
    Write-Host ""
    Write-Host "  +----------------------------------+" -ForegroundColor Cyan
    Write-Host "  |          M A T R I X             |" -ForegroundColor Cyan
    Write-Host "  |     AI Agent  *  Ollama           |" -ForegroundColor Cyan
    Write-Host "  +----------------------------------+" -ForegroundColor Cyan
    Write-Host "  Model    : $($global:Config.Model)"
    Write-Host "  Endpoint : $($global:Config.Endpoint)"
    $tools = Get-MatrixTools
    Write-Host "  Tools    : $($tools.Count) loaded ($( ($tools | ForEach-Object { $_.function.name }) -join ', '))"
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
                $tools = Get-MatrixTools
                Write-Host "  Tools reloaded: $($tools.Count) ($( ($tools | ForEach-Object { $_.function.name }) -join ', '))" -ForegroundColor Cyan
                continue
            }
        }

        Add-Message -Role "user" -Content $inputMsg
        $tools = Get-MatrixTools

        Write-Host "  thinking..." -ForegroundColor DarkGray

        try {
            $response = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $tools

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
        [array]$Tools
    )

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

        Write-Host "  [sending tool results...]" -ForegroundColor DarkGray

        $followUp = Invoke-MatrixChat -Config $global:Config -Messages (Get-Messages) -Tools $Tools
        if ($followUp.error) {
            Write-Host "  [error] $($followUp.error)" -ForegroundColor Red
        } elseif ($followUp.message) {
            Process-OllamaMessage -Msg $followUp.message -Tools $Tools
        }
    } else {
        # Plain text reply — add to history
        Add-Message -Role "assistant" -Content $result.TextOutput
    }
}

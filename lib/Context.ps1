$global:MatrixMessages = @()

function Get-TokenCount {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return [math]::Ceiling($Text.Length / 3.5)
}

function Add-Message {
    param(
        [string]$Role,
        $Content
    )
    $global:MatrixMessages += @{
        role    = $Role
        content = $Content
    }
}

function Get-Messages {
    return $global:MatrixMessages
}

function Clear-Messages {
    $global:MatrixMessages = @()
}

# Asks Ollama to summarize old conversation turns into a single system message,
# freeing up context space while preserving key facts and decisions.
# Returns $true on success, $false if summarization is not applicable or fails.
function Invoke-ContextSummary {
    $msgs  = $global:MatrixMessages
    $count = $msgs.Count
    if ($count -le 8) { return $false }

    # Keep the first user message (msgs[0]) and last 6 messages; summarize everything between.
    # Note: the system prompt is NOT stored in MatrixMessages — it is injected fresh on every
    # API call in Network.ps1. msgs[0] is always the first user turn.
    $toSummarize = @($msgs[1..($count - 7)])
    $toKeep      = @($msgs[($count - 6)..($count - 1)])

    if ($toSummarize.Count -lt 2) { return $false }

    $convText = ($toSummarize | ForEach-Object {
        $c = if ($_.content -is [string]) { $_.content } else { $_.content | ConvertTo-Json -Depth 2 -Compress }
        "$($_.role): $c"
    }) -join "`n"

    $summaryBody = @{
        model    = $global:Config.Model
        messages = @(
            @{
                role    = "user"
                content = "Summarize the following conversation turns concisely in 3-5 sentences, preserving key facts, files, decisions, and any unresolved tasks:`n`n$convText"
            }
        )
        stream   = $false
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $resp = Invoke-RestMethod -Uri $global:Config.Endpoint -Method Post `
            -ContentType "application/json" -Body $summaryBody -TimeoutSec 60 -EA Stop
        $summary = $resp.message.content
        if ([string]::IsNullOrWhiteSpace($summary)) { return $false }

        $summaryMsg = @{
            role    = "system"
            content = "[Earlier conversation summary] $summary"
        }
        # Rebuild: original first-user-turn + summary + recent 6 messages
        $global:MatrixMessages = @($msgs[0], $summaryMsg) + $toKeep
        Write-Host "  [context] Summarized $($toSummarize.Count) old turns to save space." -ForegroundColor DarkGray
        Write-MatrixLog -Message "Context summarized: compressed $($toSummarize.Count) messages"
        return $true
    } catch {
        Write-MatrixLog -Level "WARN" -Message "Context summarization failed: $_"
        return $false
    }
}

# Two-phase context management:
#   Phase A — summarize old turns with Ollama at 75% token budget
#   Phase B — smart prune (keep msgs[0] = first user turn, msgs[1] = second user turn, last 6)
#             if summarization fails or is not applicable
function Prune-Context {
    param([int]$MaxTokens = 100000, [int]$SummarizeAt = 75000)

    $total = ($global:MatrixMessages | ForEach-Object {
        $c = if ($_.content -is [string]) { $_.content } else { $_.content | ConvertTo-Json -Depth 3 -Compress }
        Get-TokenCount $c
    } | Measure-Object -Sum).Sum

    # Show token budget once it becomes relevant
    if ($total -gt ($MaxTokens * 0.5)) {
        $pct   = [math]::Round($total / $MaxTokens * 100)
        $color = if ($pct -ge 90) { "Red" } elseif ($pct -ge 75) { "Yellow" } else { "DarkGray" }
        Write-Host "  [context: ~$total tokens, $pct%]" -ForegroundColor $color
    }

    if ($total -lt $SummarizeAt) { return }

    # Phase A: ask the model to summarize old turns
    $summarized = Invoke-ContextSummary
    if ($summarized) { return }

    # Phase B: hard prune — keep system[0], original user task[1], last 6 messages
    $msgs = $global:MatrixMessages
    if ($msgs.Count -gt 9) {
        $global:MatrixMessages = @($msgs[0], $msgs[1]) + @($msgs[($msgs.Count - 6)..($msgs.Count - 1)])
        Write-Host "  [context] Pruned old turns (summarization unavailable)." -ForegroundColor DarkGray
        Write-MatrixLog -Message "Context hard-pruned: kept first two user turns + last 6"
    }
}

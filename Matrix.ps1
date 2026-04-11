#!/usr/bin/env pwsh
# Matrix AI Agent — cross-platform entry point
# Requires PowerShell 7+ (pwsh). Run with: pwsh Matrix.ps1 [-CLI]
param(
    [switch]$CLI   # force CLI mode; default on non-Windows
)

$ErrorActionPreference = "Stop"

# On non-Windows there is no WPF — always use CLI
if (-not $IsWindows) { $CLI = $true }

$global:MatrixRoot = $PSScriptRoot

# Dot-source libs using Join-Path (safe on all platforms)
. (Join-Path $global:MatrixRoot "lib" "Config.ps1")
. (Join-Path $global:MatrixRoot "lib" "Context.ps1")
. (Join-Path $global:MatrixRoot "lib" "Network.ps1")
. (Join-Path $global:MatrixRoot "lib" "ToolManager.ps1")
. (Join-Path $global:MatrixRoot "lib" "Logger.ps1")

$logPath = Join-Path $global:MatrixRoot "err.log"
if (Test-Path $logPath) { Remove-Item $logPath -Force }
Write-MatrixLog -Message "Matrix starting (pwsh $($PSVersionTable.PSVersion))"

$global:Config = Load-Config
Clear-Messages

# ── Auto-update: silently pull latest release on launch ───────────────────────
function Invoke-MatrixUpdate {
    $versionFile = Join-Path $global:MatrixRoot ".version"
    $releaseApi  = "https://api.github.com/repos/laynr/matrix/releases/latest"
    $releaseZip  = "https://github.com/laynr/matrix/releases/latest/download/matrix-release.zip"

    $local = $null
    if (Test-Path $versionFile) {
        try { $local = Get-Content $versionFile -Raw | ConvertFrom-Json } catch {}
    }

    # Check at most once per hour — avoid hammering the API on every launch
    if ($local -and $local.CheckedAt) {
        try {
            if (((Get-Date) - [datetime]$local.CheckedAt).TotalHours -lt 1) { return }
        } catch {}
    }

    try {
        $release    = Invoke-RestMethod $releaseApi -TimeoutSec 5 -ErrorAction Stop
        $remoteDate = [datetime]$release.published_at
        $localDate  = if ($local -and $local.PublishedAt) { [datetime]$local.PublishedAt } else { [datetime]::MinValue }

        # Always update the checked-at timestamp
        @{ PublishedAt = $release.published_at; CheckedAt = (Get-Date -Format "o") } |
            ConvertTo-Json | Set-Content $versionFile -Encoding UTF8

        if ($remoteDate -le $localDate) { return }   # already current

        Write-Host "  [update] New version available — updating..." -ForegroundColor Cyan

        $tmpZip     = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".zip")
        $tmpExtract = Join-Path ([IO.Path]::GetTempPath()) "matrix-update-$PID"

        Invoke-WebRequest $releaseZip -OutFile $tmpZip -TimeoutSec 60 -ErrorAction Stop
        Expand-Archive $tmpZip -DestinationPath $tmpExtract -Force

        # Remove tools that no longer exist in the new release (keeps tools dir clean)
        $newToolNames = @(Get-ChildItem (Join-Path $tmpExtract "tools") -Filter "*.ps1").BaseName
        Get-ChildItem (Join-Path $global:MatrixRoot "tools") -Filter "*.ps1" |
            Where-Object { $_.BaseName -notin $newToolNames } |
            ForEach-Object { Remove-Item $_.FullName -Force }

        # Sync Matrix.ps1, lib/, tools/
        Copy-Item (Join-Path $tmpExtract "Matrix.ps1") $global:MatrixRoot -Force
        Copy-Item (Join-Path $tmpExtract "lib")        $global:MatrixRoot -Recurse -Force
        Copy-Item (Join-Path $tmpExtract "tools")      $global:MatrixRoot -Recurse -Force

        Remove-Item $tmpZip, $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "  [update] Done. Run 'reload' for new tools; core changes apply next launch." -ForegroundColor Green
        Write-Host ""

    } catch {
        # Silent fail — an update error must never prevent Matrix from starting
    }
}

$updatePS = [PowerShell]::Create()
[void]$updatePS.AddScript({
    param($root)
    $global:MatrixRoot = $root
    . (Join-Path $root "lib" "Config.ps1")
    . (Join-Path $root "lib" "Logger.ps1")
    Invoke-MatrixUpdate
}).AddArgument($global:MatrixRoot)
[void]$updatePS.BeginInvoke()
# Fire-and-forget: update writes .version and prints a notice if a new release
# is available. The notice may appear after the prompt — acceptable trade-off
# for instant startup instead of a 5-second blocking network call.

if ($CLI) {
    . (Join-Path $global:MatrixRoot "lib" "CLI.ps1")
    Show-MatrixCLI
} else {
    # GUI — Windows only
    . (Join-Path $global:MatrixRoot "lib" "GUI.ps1")

    $global:PendingAttachment = $null   # @{ Name; Content } when a file is queued
    # Thread-safe cancel flag — checked by background streaming runspace each token
    $global:CancelToken = [hashtable]::Synchronized(@{ Cancel = $false })

    # ── Async helpers ─────────────────────────────────────────────────────────

    # Streams a chat response on a background runspace. Tokens are enqueued to a
    # ConcurrentQueue and drained by a 50ms DispatcherTimer into $LiveTextBlock.
    # Calls $OnComplete on the UI thread when the stream finishes.
    function Start-ChatAsync {
        param(
            [hashtable]   $Config,
            [array]       $Messages,
            [array]       $Tools,
            [string]      $ToolCatalog,
            [scriptblock] $OnComplete,
            [System.Windows.Controls.TextBlock]$LiveTextBlock   # pre-created bubble TB
        )
        $root       = $global:MatrixRoot
        $cancelTok  = $global:CancelToken
        $tokenQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($root, $cfg, $msgs, $tools, $catalog, $queue, $cancel)
            $global:MatrixRoot = $root
            . (Join-Path $root "lib" "Logger.ps1")
            . (Join-Path $root "lib" "Config.ps1")
            . (Join-Path $root "lib" "Network.ps1")
            Invoke-MatrixStreamingChatToQueue `
                -Config $cfg -Messages $msgs -Tools $tools -ToolCatalog $catalog `
                -TokenQueue $queue -CancelToken $cancel
        }).AddArgument($root).AddArgument($Config).AddArgument($Messages
        ).AddArgument($Tools).AddArgument($ToolCatalog
        ).AddArgument($tokenQueue).AddArgument($cancelTok)

        $handle = $ps.BeginInvoke()
        $liveTB = $LiveTextBlock

        $timer          = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(50)
        $timer.Tag      = @{ PS = $ps; Handle = $handle; OnComplete = $OnComplete
                              Queue = $tokenQueue; LiveTB = $liveTB }
        $timer.add_Tick({
            param($src, $e)
            $s = $src.Tag

            # Drain token queue into the live TextBlock
            if ($s.LiveTB) {
                $t = ""
                $any = $false
                while ($s.Queue.TryDequeue([ref]$t)) {
                    # Skip null sentinel (tool-call signal)
                    if ($t -and $t -ne [char]0x00) {
                        $s.LiveTB.Text += $t
                        $any = $true
                    }
                }
                if ($any) { $global:GUI.ChatScrollViewer.ScrollToEnd() }
            }

            if (-not $s.Handle.IsCompleted) { return }
            $src.Stop()
            try {
                $raw  = $s.PS.EndInvoke($s.Handle)
                $resp = if ($raw -and $raw.Count -gt 0) { $raw[0] } else { @{ error = "No response returned" } }
            } catch {
                $resp = @{ error = $_.Exception.Message }
            } finally {
                try { $s.PS.Dispose() } catch {}
            }
            & $s.OnComplete $resp
        })
        $timer.Start()
    }

    # Runs Invoke-MatrixToolchain on a background runspace so tool execution never
    # blocks the WPF dispatcher thread. Calls $OnComplete on the UI thread with the result.
    function Start-ToolchainAsync {
        param(
            [object]      $Message,
            [scriptblock] $OnComplete
        )
        $root = $global:MatrixRoot
        $ps   = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($root, $msg)
            $global:MatrixRoot = $root
            . (Join-Path $root "lib" "Logger.ps1")
            . (Join-Path $root "lib" "Config.ps1")
            . (Join-Path $root "lib" "Network.ps1")
            . (Join-Path $root "lib" "ToolManager.ps1")
            Invoke-MatrixToolchain -Message $msg
        }).AddArgument($root).AddArgument($Message)

        $handle         = $ps.BeginInvoke()
        $timer          = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $timer.Tag      = @{ PS = $ps; Handle = $handle; OnComplete = $OnComplete }
        $timer.add_Tick({
            param($src, $e)
            $s = $src.Tag
            if (-not $s.Handle.IsCompleted) { return }
            $src.Stop()
            try {
                $raw    = $s.PS.EndInvoke($s.Handle)
                $result = if ($raw -and $raw.Count -gt 0) { $raw[0] } else {
                    @{ HasTools = $false; TextOutput = ""; ToolResults = @(); ToolsCalled = @() }
                }
            } catch {
                $result = @{ HasTools = $false; TextOutput = ""; ToolResults = @()
                             ToolsCalled = @(); Error = $_.Exception.Message }
            } finally {
                try { $s.PS.Dispose() } catch {}
            }
            & $s.OnComplete $result
        })
        $timer.Start()
    }

    function Restore-Input {
        $global:GUI.SendBtn.IsEnabled      = $true
        $global:GUI.InputBox.IsEnabled     = $true
        $global:GUI.CancelBtn.Visibility   = "Collapsed"
        $global:GUI.SendBtn.Visibility     = "Visible"
        $global:GUI.StatusLabel.Text       = "Ready"
        $global:GUI.StatusLabel.Foreground =
            ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#6B7280")
        $global:GUI.InputBox.Focus() | Out-Null
    }

    function Invoke-CancelRequest {
        $global:CancelToken.Cancel = $true
        Add-UIChatMessage -Role "system" -Message "Request cancelled." | Out-Null
        Restore-Input
    }

    # ── Core message flow ─────────────────────────────────────────────────────

    # Handles the assistant message after a streaming response completes.
    # Shows tool status cards before dispatching, updates them in-place after.
    function Process-AssistantMessage {
        param(
            $assistantMsg,          # raw Ollama response object
            [int]   $Depth       = 0,
            [array] $Tools       = @(),
            [string]$ToolCatalog = ""
        )

        $maxDepth = if ($global:Config.MaxDepth) { $global:Config.MaxDepth } else { 10 }
        if ($Depth -ge $maxDepth) {
            Add-UIChatMessage -Role "system" -Message "[warn] Max tool call depth ($maxDepth) reached — stopping." | Out-Null
            Update-ContextDisplay
            Prune-Context
            Restore-Input
            return
        }

        $msg = $assistantMsg.message

        # No tool calls — we're done.
        if (-not $msg.tool_calls -or $msg.tool_calls.Count -eq 0) {
            Update-ContextDisplay
            Prune-Context
            Restore-Input
            return
        }

        # ── Tool path ──────────────────────────────────────────────────────────
        # 1. Show a status card for each tool BEFORE dispatching (⟳ running)
        $statusCards = @()
        foreach ($tc in $msg.tool_calls) {
            $name = $tc.function.name
            $rawArgs = $tc.function.arguments
            $argPreview = ""
            try {
                $parsed = if ($rawArgs -is [string]) { $rawArgs | ConvertFrom-Json } else { $rawArgs }
                $argPreview = ($parsed.PSObject.Properties | Select-Object -First 2 | ForEach-Object {
                    $v = [string]$_.Value; if ($v.Length -gt 20) { $v = $v.Substring(0,17)+"..." }
                    "$($_.Name)=$v"
                }) -join ", "
            } catch {}
            $card = Add-ToolStatusCard -Name $name -ArgPreview $argPreview
            $statusCards += $card
        }

        $captureTools   = $Tools
        $captureCatalog = $ToolCatalog
        $captureDepth   = $Depth
        $captureCards   = $statusCards

        # 2. Run the toolchain off the UI thread
        Start-ToolchainAsync -Message $msg -OnComplete {
            param($result)

            # 3. Update each card to ✓ or ✗
            for ($i = 0; $i -lt $captureCards.Count; $i++) {
                if ($i -ge $result.ToolsCalled.Count) { break }
                $toolName = $result.ToolsCalled[$i].function.name
                $card = $captureCards[$i]
                $isError = $result.ToolResults -and
                           $result.ToolResults.Count -gt $i -and
                           $result.ToolResults[$i].content -match '"error"\s*:'
                if ($isError) {
                    $card.Text       = "  ✗  $toolName"
                    $card.Foreground = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#EF4444")
                } else {
                    $card.Text       = "  ✓  $toolName"
                    $card.Foreground = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#10B981")
                }
            }

            if ($result.Error) {
                Add-UIChatMessage -Role "system" -Message "Tool error: $($result.Error)" | Out-Null
                Update-ContextDisplay
                Prune-Context
                Restore-Input
                return
            }

            if (-not $result.HasTools) {
                # Toolchain returned no tools (shouldn't happen here, but guard)
                Update-ContextDisplay
                Prune-Context
                Restore-Input
                return
            }

            # 4. Store tool results and send follow-up request
            foreach ($tr in $result.ToolResults) {
                Add-Message -Role $tr.role -Content $tr.content
            }

            $global:GUI.StatusLabel.Text = "Thinking..."
            $liveTB = New-LiveMessageBubble

            Start-ChatAsync -Config $global:Config -Messages (Get-Messages) `
                -Tools $captureTools -ToolCatalog $captureCatalog `
                -LiveTextBlock $liveTB -OnComplete {
                param($resp)
                if ($resp.error -eq "cancelled") {
                    Restore-Input
                    return
                }
                if ($resp.error) {
                    Add-UIChatMessage -Role "system" -Message "Error: $($resp.error)" | Out-Null
                    Update-ContextDisplay
                    Restore-Input
                    return
                }
                Add-Message -Role "assistant" -Content $resp.message.content
                Process-AssistantMessage -assistantMsg $resp `
                    -Depth ($captureDepth + 1) `
                    -Tools $captureTools -ToolCatalog $captureCatalog
            }
        }
    }

    function Invoke-Send {
        $text = $global:GUI.InputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($text) -and -not $global:PendingAttachment) { return }

        $global:GUI.InputBox.Text      = ""
        $global:GUI.SendBtn.IsEnabled  = $false
        $global:GUI.InputBox.IsEnabled = $false
        $global:GUI.CancelBtn.Visibility = "Visible"
        $global:GUI.StatusLabel.Text   = "Thinking..."
        $global:GUI.StatusLabel.Foreground =
            ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#9CA3AF")

        # Reset cancel flag for this request
        $global:CancelToken.Cancel = $false

        # Build message content — prepend attachment if one is queued
        $msgContent = $text
        if ($global:PendingAttachment) {
            $att        = $global:PendingAttachment
            $block      = "``````$($att.Name)`n$($att.Content)`n```````n"
            $msgContent = if ($text) { "$block$text" } else { $block.TrimEnd() }
            $global:PendingAttachment = $null
            if ($global:GUI.AttachLabel) {
                $global:GUI.AttachLabel.Text       = ""
                $global:GUI.AttachLabel.Visibility = "Collapsed"
            }
        }

        Add-UIChatMessage -Role "user" -Message $(if ($text) { $text } else { "(attachment)" }) | Out-Null
        Add-Message -Role "user" -Content $msgContent

        $selTools   = Select-MatrixTools `
                          -UserMessage    $text `
                          -MaxTokenBudget ($global:Config.ToolBudgetTokens ?? 6000) `
                          -MaxCount       ($global:Config.MaxToolCount ?? 25) `
                          -CoreTools      ($global:Config.CoreTools ?? @())
        $selCatalog = Get-MatrixToolCatalog

        # Pre-create live assistant bubble — tokens stream into it as they arrive
        $liveTB = New-LiveMessageBubble

        Start-ChatAsync -Config $global:Config -Messages (Get-Messages) `
            -Tools $selTools -ToolCatalog $selCatalog `
            -LiveTextBlock $liveTB -OnComplete {
            param($resp)
            if ($resp.error -eq "cancelled") {
                Restore-Input
                return
            }
            if ($resp.error) {
                Add-UIChatMessage -Role "system" -Message "Error: $($resp.error)" | Out-Null
                Update-ContextDisplay
                Restore-Input
                return
            }
            Add-Message -Role "assistant" -Content $resp.message.content
            Process-AssistantMessage -assistantMsg $resp -Tools $selTools -ToolCatalog $selCatalog
        }
    }

    $null = Get-MatrixTools        # populate tool cache so Select-MatrixTools works
    $null = Get-MatrixRunspacePool # pre-warm runspaces before first message

    Show-MatrixGUI
}

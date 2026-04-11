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

    $global:TotalInputTokens  = 0
    $global:TotalOutputTokens = 0
    $global:PendingAttachment = $null   # @{ Name; Content } when a file is queued

    # Runs Invoke-MatrixChat on a background runspace so the WPF dispatcher thread
    # is never blocked. Polls every 250 ms with a DispatcherTimer; calls $OnComplete
    # on the UI thread once the runspace finishes.
    function Start-ChatAsync {
        param(
            [hashtable]   $Config,
            [array]       $Messages,
            [array]       $Tools,
            [string]      $ToolCatalog,
            [scriptblock] $OnComplete
        )
        $root = $global:MatrixRoot
        $ps   = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($root, $cfg, $msgs, $tools, $catalog)
            $global:MatrixRoot = $root
            . (Join-Path $root "lib" "Logger.ps1")
            . (Join-Path $root "lib" "Config.ps1")
            . (Join-Path $root "lib" "Network.ps1")
            Invoke-MatrixChat -Config $cfg -Messages $msgs -Tools $tools -ToolCatalog $catalog
        }).AddArgument($root).AddArgument($Config).AddArgument($Messages
        ).AddArgument($Tools).AddArgument($ToolCatalog)

        $handle = $ps.BeginInvoke()
        $timer  = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(250)
        $timer.Tag = @{ PS = $ps; Handle = $handle; OnComplete = $OnComplete }
        $timer.add_Tick({
            param($src, $e)
            $s = $src.Tag
            if (-not $s.Handle.IsCompleted) { return }
            $src.Stop()
            try {
                $raw  = $s.PS.EndInvoke($s.Handle)
                $resp = if ($raw -and $raw.Count -gt 0) { $raw[0] } else { @{ error = "No response returned" } }
            } catch {
                $resp = @{ error = $_.Exception.Message }
            } finally {
                $s.PS.Dispose()
            }
            & $s.OnComplete $resp
        })
        $timer.Start()
    }

    function Restore-Input {
        $global:GUI.SendBtn.IsEnabled  = $true
        $global:GUI.InputBox.IsEnabled = $true
        $global:GUI.InputBox.Focus() | Out-Null
    }

    function Process-AssistantMessage {
        param(
            $assistantMsg,
            [int]   $Depth       = 0,
            [array] $Tools       = @(),
            [string]$ToolCatalog = ""
        )
        $maxDepth = if ($global:Config.MaxDepth) { $global:Config.MaxDepth } else { 10 }
        if ($Depth -ge $maxDepth) {
            Add-UIChatMessage -Role "system" -Message "[warn] Max tool call depth ($maxDepth) reached — stopping."
            Restore-Input
            return
        }

        $result = Invoke-MatrixToolchain -Message $assistantMsg.message
        if (-not [string]::IsNullOrWhiteSpace($result.TextOutput)) {
            Add-UIChatMessage -Role "assistant" -Message $result.TextOutput
        }

        if (-not $result.HasTools) {
            Prune-Context
            Restore-Input
            return
        }

        foreach ($tc in $result.ToolsCalled) {
            Add-UIChatMessage -Role "system" -Message "Executing tool $($tc.function.name)..."
        }
        foreach ($tr in $result.ToolResults) {
            Add-Message -Role $tr.role -Content $tr.content
        }
        Add-UIChatMessage -Role "system" -Message "Sending tool results..."

        $captureTools   = $Tools
        $captureCatalog = $ToolCatalog
        $captureDepth   = $Depth

        Start-ChatAsync -Config $global:Config -Messages (Get-Messages) -Tools $captureTools -ToolCatalog $captureCatalog -OnComplete {
            param($resp)
            if ($resp.error) {
                Add-UIChatMessage -Role "system" -Message "Error: $($resp.error)"
                Restore-Input
            } else {
                Add-Message -Role "assistant" -Content $resp.message.content
                Process-AssistantMessage -assistantMsg $resp -Depth ($captureDepth + 1) -Tools $captureTools -ToolCatalog $captureCatalog
                Prune-Context
            }
        }
    }

    function Invoke-Send {
        $text = $global:GUI.InputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($text) -and -not $global:PendingAttachment) { return }
        $global:GUI.InputBox.Text        = ""
        $global:GUI.SendBtn.IsEnabled    = $false
        $global:GUI.InputBox.IsEnabled   = $false

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

        Add-UIChatMessage -Role "user" -Message $(if ($text) { $text } else { "(attachment)" })
        Add-Message -Role "user" -Content $msgContent
        Add-UIChatMessage -Role "system" -Message "Thinking..."

        $selTools   = Select-MatrixTools `
                          -UserMessage    $text `
                          -MaxTokenBudget ($global:Config.ToolBudgetTokens ?? 6000) `
                          -MaxCount       ($global:Config.MaxToolCount ?? 25) `
                          -CoreTools      ($global:Config.CoreTools ?? @())
        $selCatalog = Get-MatrixToolCatalog

        Start-ChatAsync -Config $global:Config -Messages (Get-Messages) -Tools $selTools -ToolCatalog $selCatalog -OnComplete {
            param($resp)
            if ($resp.error) {
                Add-UIChatMessage -Role "system" -Message "Error: $($resp.error)"
                Restore-Input
            } else {
                Add-Message -Role "assistant" -Content $resp.message.content
                Process-AssistantMessage -assistantMsg $resp -Tools $selTools -ToolCatalog $selCatalog
            }
        }
    }

    $null = Get-MatrixTools        # populate tool cache so Select-MatrixTools works
    $null = Get-MatrixRunspacePool # pre-warm runspaces before first message

    Show-MatrixGUI
}

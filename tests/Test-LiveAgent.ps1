#!/usr/bin/env pwsh
# Live agent integration test — requires a running Ollama instance.
#
# Suite 1 — "use all tools": full E2E smoke test, all 15 tools in context.
# Suite 2 — per-tool: one test per discovered tool, passing only that tool
#            to the API so the model either calls it or returns no tool call.

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Test-Framework.ps1")

$global:MatrixRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $global:MatrixRoot "lib" "Logger.ps1")
. (Join-Path $global:MatrixRoot "lib" "Config.ps1")
. (Join-Path $global:MatrixRoot "lib" "ToolManager.ps1")
. (Join-Path $global:MatrixRoot "lib" "Network.ps1")
. (Join-Path $global:MatrixRoot "lib" "Context.ps1")

function Write-MatrixLog { param($Message, $Level = "INFO") }

$global:Config = Load-Config

# ── Prerequisites ─────────────────────────────────────────────────────────────

Start-Suite "Live agent prerequisites"

$ollamaUp = $false
try {
    Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -EA Stop | Out-Null
    $ollamaUp = $true
} catch {}
Assert-True "Ollama reachable at localhost:11434" $ollamaUp

if (-not $ollamaUp) {
    Write-Host "  [skip] Ollama not running — skipping live agent tests." -ForegroundColor Yellow
    $failed = Show-TestSummary
    exit $failed
}

$modelAvailable = $false
try {
    $tags  = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -EA Stop
    $names = $tags.models | ForEach-Object { $_.name }
    $modelAvailable = $global:Config.Model -in $names
} catch {}
Assert-True "Model '$($global:Config.Model)' is available" $modelAvailable

if (-not $modelAvailable) {
    Write-Host "  [skip] Model not available — skipping live agent tests." -ForegroundColor Yellow
    $failed = Show-TestSummary
    exit $failed
}

# ── Shared agent loop harness ─────────────────────────────────────────────────
# $Tools: tool schemas to expose. Defaults to all tools if omitted.
# Passing a single-tool array constrains the model to that tool only.

function Invoke-AgentConversation {
    param(
        [string]$Prompt,
        [array] $Tools     = $null,
        [int]   $MaxDepth  = 12
    )

    if (-not $Tools) { $Tools = Get-MatrixTools }

    Clear-Messages
    Add-Message -Role "user" -Content $Prompt

    $allCalled   = [System.Collections.Generic.List[string]]::new()
    $toolErrors  = [System.Collections.Generic.List[string]]::new()
    $finalText   = ""
    $anyText     = ""      # non-empty if any turn produced text
    $streamError = $null
    $depth       = 0

    while ($depth -lt $MaxDepth) {
        $response = Invoke-MatrixStreamingChat `
            -Config $global:Config -Messages (Get-Messages) -Tools $Tools

        if ($response.error) { $streamError = $response.error; break }

        $result    = Invoke-MatrixToolchain -Message $response.message
        $finalText = $result.TextOutput
        if (-not [string]::IsNullOrWhiteSpace($result.TextOutput)) {
            $anyText = $result.TextOutput
        }
        Add-Message -Role "assistant" -Content $result.TextOutput

        if ($result.HasTools) {
            foreach ($tc in $result.ToolsCalled) { $allCalled.Add($tc.function.name) }

            for ($i = 0; $i -lt $result.ToolResults.Count; $i++) {
                $tr  = $result.ToolResults[$i]
                $tcN = if ($i -lt $result.ToolsCalled.Count) {
                    $result.ToolsCalled[$i].function.name
                } else { "unknown" }
                Add-Message -Role $tr.role -Content $tr.content
                try { $obj = $tr.content | ConvertFrom-Json -EA Stop } catch { $obj = $null }
                if ($obj -and $obj.error) { $toolErrors.Add("${tcN}: $($obj.error)") }
            }
            $depth++
        } else {
            break
        }
    }

    return @{
        StreamError = $streamError
        ToolsCalled = @($allCalled)
        ToolErrors  = @($toolErrors)
        FinalText   = $finalText   # text from the last turn (may be empty)
        AnyText     = $anyText     # non-empty if any turn produced text
        Depth       = $depth
        TotalTools  = $Tools.Count
    }
}

# ── Suite 1: full E2E — ask agent to use all tools ────────────────────────────

Start-Suite "Live agent — use all tools"

Write-Host "  Prompt: 'do something that uses all your tools'" -ForegroundColor DarkGray
Write-Host "  This may take 60–180 s depending on the model..." -ForegroundColor DarkGray
Write-Host ""

$run = Invoke-AgentConversation -Prompt "do something that uses all your tools"

Assert-True "no streaming error"  ($null -eq $run.StreamError)

if ($run.StreamError) {
    Write-Host "  [error] $($run.StreamError)" -ForegroundColor Red
    $failed = Show-TestSummary
    exit $failed
}

Assert-True "at least one tool was called"       ($run.ToolsCalled.Count -ge 1)
# The model may call tools on the final turn with no trailing text — check any turn
Assert-True "at least one turn produced text"    (-not [string]::IsNullOrWhiteSpace($run.AnyText))
# Depth limit is a safety cap; warn but don't fail — model calling many tools is OK
if ($run.Depth -ge 12) {
    Write-Host "  [warn] agent hit MaxDepth ($($run.Depth)) — model may be looping" -ForegroundColor Yellow
}

# External services (IPInfo, Weather, WebContent) can return {"error":...} legitimately.
# Fail only if the majority of calls errored — that would indicate a Matrix bug.
$errorRate = if ($run.ToolsCalled.Count -gt 0) {
    $run.ToolErrors.Count / $run.ToolsCalled.Count
} else { 0 }
Assert-True "tool error rate below 50% ($($run.ToolErrors.Count)/$($run.ToolsCalled.Count) errored)" `
    ($errorRate -lt 0.5)
if ($run.ToolErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Tool errors (graceful — external services may be unavailable):" -ForegroundColor DarkGray
    foreach ($e in $run.ToolErrors) { Write-Host "    $e" -ForegroundColor DarkGray }
}

# Coverage — at least 3 distinct tools called. Per-tool suite tests all 15 individually;
# this just confirms the E2E multi-tool loop works. Model selection is non-deterministic.
$uniqueTools = @($run.ToolsCalled | Sort-Object -Unique)
Assert-True "at least 3 distinct tools used ($($uniqueTools.Count)/$($run.TotalTools))" `
    ($uniqueTools.Count -ge 3)

Write-Host ""
Write-Host "  Tools called — $($run.ToolsCalled.Count) calls, $($uniqueTools.Count) unique:" -ForegroundColor DarkGray
foreach ($t in $uniqueTools) { Write-Host "    + $t" -ForegroundColor DarkGray }

$allToolNames = Get-MatrixTools | ForEach-Object { $_.function.name }
$notCalled    = @($allToolNames | Where-Object { $_ -notin $uniqueTools })
if ($notCalled.Count -gt 0) {
    Write-Host ""
    Write-Host "  Not called ($($notCalled.Count)):" -ForegroundColor DarkGray
    foreach ($t in $notCalled) { Write-Host "    - $t" -ForegroundColor DarkGray }
}

# ── Suite 2: per-tool — one targeted test per discovered tool ─────────────────
#
# Each test passes ONLY the tool under test to the API, so the model can't
# call anything else. Prompts are looked up by name; unknown tools fall back
# to a generic "use the <name> tool" prompt.

Start-Suite "Live agent — per-tool"

# Targeted prompts chosen to reliably elicit a tool call with minimal args.
$tmpFile = [IO.Path]::GetTempPath() + "matrix_test_$([int](Get-Date -UFormat %s)).txt"
$ToolPrompts = @{
    # ── Core / always-reliable ────────────────────────────────────────────────
    'Get-Time'              = "What time is it right now?"
    'Get-SystemInfo'        = "What are the CPU load and memory stats on this machine?"
    'Get-Weather'           = "What is the current weather in Honolulu, Hawaii?"
    'Get-WikipediaSummary'  = "Give me a Wikipedia summary of the PowerShell programming language."
    'Invoke-Math'           = "What is 17 multiplied by 23?"
    'Read-File'             = "Read the file at: $($global:MatrixRoot)/README.md"
    'Write-FileContent'     = "Write the text 'Matrix per-tool test' to the file: $tmpFile"
    'Find-Files'            = "Find all .ps1 files in the directory: $($global:MatrixRoot)/tools"
    'Get-WebContent'        = "Fetch the content from https://example.com"
    'Get-ProcessList'       = "List the top 5 running processes by memory usage."
    'Get-EnvVariable'       = "What is the value of the PATH environment variable?"
    'Get-IPInfo'            = "What is my current public IP address?"
    'Convert-Units'         = "Convert 100 kilometers to miles."
    'Convert-DataFormat'    = "Convert this CSV to JSON: name,age`nAlice,30`nBob,25"

    # ── Encoding / hashing ────────────────────────────────────────────────────
    'ConvertTo-Base64'      = "Encode the text 'hello world' to Base64."
    'ConvertFrom-Base64'    = "Decode this Base64 string back to plain text: aGVsbG8gd29ybGQ="
    'Get-FileHash'          = "Get the SHA256 hash of the file: $($global:MatrixRoot)/README.md"

    # ── Network / web ─────────────────────────────────────────────────────────
    'Get-DnsRecord'         = "Look up the DNS A records for example.com."
    'Get-RssFeed'           = "Fetch the latest headlines from the RSS feed at https://feeds.bbci.co.uk/news/rss.xml"
    'Get-StockQuote'        = "Get the current stock price for AAPL."
    'Get-CurrencyRate'      = "What is the current USD to EUR exchange rate?"
    'Get-ActiveConnections' = "List active network connections on this machine."
    'Get-NetworkAdapters'   = "List all network adapters on this machine."
    'Get-CertificateInfo'   = "Check the SSL certificate details for https://example.com"
    'Invoke-HttpRequest'    = "Make an HTTP GET request to https://httpbin.org/get"
    'Test-NetworkHost'      = "Test if the host example.com is reachable on port 80."
    'New-WebSession'        = "Create a new persistent web session file at $($env:TMPDIR ?? '/tmp')/matrix-session-new.json."
    'Invoke-WebSession'     = "Fetch https://httpbin.org/get using a persistent web session stored at $($env:TMPDIR ?? '/tmp')/matrix-session.json"

    # ── Disk / files ──────────────────────────────────────────────────────────
    'Get-DiskInfo'          = "Show disk usage information for this machine."
    'Get-DirectoryTree'     = "Show the directory tree for: $($global:MatrixRoot)/lib"
    'Copy-FileItem'         = "Copy the file $($global:MatrixRoot)/README.md to $($env:TMPDIR ?? '/tmp')/matrix-copy-readme.md"
    'Move-FileItem'         = "Move the file $($env:TMPDIR ?? '/tmp')/matrix-move-src.txt to $($env:TMPDIR ?? '/tmp')/matrix-move-dst.txt."
    'Sort-FileItems'        = "Group the files in $($global:MatrixRoot)/lib into subfolders by file extension."
    'New-ZipArchive'        = "Create a zip archive of $($global:MatrixRoot)/lib and save it to $($env:TMPDIR ?? '/tmp')/matrix-lib.zip."
    'Expand-ZipArchive'     = "Extract the archive $($env:TMPDIR ?? '/tmp')/matrix-lib.zip to $($env:TMPDIR ?? '/tmp')/matrix-extract/"
    'Compare-FileContent'   = "Compare the file $($global:MatrixRoot)/README.md with itself and report if they are identical."
    'Edit-FileContent'      = "In the file $($env:TMPDIR ?? '/tmp')/matrix-edit-test.txt, replace all occurrences of 'foo' with 'bar'."

    # ── Text / regex ──────────────────────────────────────────────────────────
    'Get-RegexMatches'      = "Find all numbers in this text: 'There are 42 items and 7 categories'"
    'Invoke-TextTemplate'   = "Fill the template 'Hello {{name}}, you have {{count}} messages.' with name=Alice and count=5."

    # ── Crypto / secrets ──────────────────────────────────────────────────────
    'New-SecureToken'       = "Generate a secure random token."
    'Protect-String'        = "Encrypt the text 'hello matrix' using the password 'testpass123'."
    'Unprotect-String'      = "Decrypt this AES-encrypted ciphertext 'SGVsbG8gTWF0cml4' using the password 'testpass123'."

    # ── Clipboard ─────────────────────────────────────────────────────────────
    'Get-ClipboardContent'  = "What text is currently on the clipboard?"
    'Set-ClipboardContent'  = "Set the clipboard text to 'Matrix per-tool test'."

    # ── System / processes / services ─────────────────────────────────────────
    'Get-ServiceList'       = "List all running services on this machine."
    'Get-EventLogEntries'   = "Show the last 5 system log entries."
    'Get-ScheduledTaskList' = "List all scheduled tasks on this machine."

    # ── Office / documents ────────────────────────────────────────────────────
    'Write-DocxFile'        = "Create a Word document at $($env:TMPDIR ?? '/tmp')/matrix-test.docx with the paragraph 'Hello from Matrix'."
    'Read-DocxFile'         = "Read the Word document at: $($env:TMPDIR ?? '/tmp')/matrix-test.docx"
    'Write-XlsxFile'        = "Write a spreadsheet to $($env:TMPDIR ?? '/tmp')/matrix-test.xlsx with rows: [{Name:'Alice',Age:30},{Name:'Bob',Age:25}]."
    'Read-XlsxFile'         = "Read the spreadsheet at: $($env:TMPDIR ?? '/tmp')/matrix-test.xlsx"
    'Write-PdfFile'         = "Create a PDF at $($env:TMPDIR ?? '/tmp')/matrix-test.pdf with the lines 'Hello World' and 'Matrix Agent'."
    'Read-PdfFile'          = "Read the PDF document at: $($env:TMPDIR ?? '/tmp')/matrix-test.pdf"
    'Write-PptxFile'        = "Create a PowerPoint at $($env:TMPDIR ?? '/tmp')/matrix-test.pptx with one slide titled 'Matrix Introduction'."
    'Read-PptxFile'         = "Read the PowerPoint presentation at: $($env:TMPDIR ?? '/tmp')/matrix-test.pptx"

    # ── Images ────────────────────────────────────────────────────────────────
    'Get-ImageMetadata'     = "Get the EXIF metadata for the image at: $($env:TMPDIR ?? '/tmp')/matrix-test.jpg"
    'Search-Images'         = "Search for images of 'sunset over ocean' online."
    'Sort-ImageFiles'       = "Organize the image files in $($env:TMPDIR ?? '/tmp') into date-based subfolders."

    # ── Notifications / messaging ─────────────────────────────────────────────
    'Send-SystemNotification' = "Send a system notification with title 'Matrix Test' and message 'Per-tool suite running'."
    'Send-SlackMessage'     = "Send the Slack message 'Matrix per-tool test' to webhook URL https://hooks.slack.com/services/TEST/TEST/testtoken"
    'Send-TeamsMessage'     = "Post a Teams message titled 'Matrix Alert' with body 'Per-tool test' to https://outlook.office.com/webhook/test"
}

$allTools    = Get-MatrixTools
$perToolFail = 0

foreach ($toolSchema in ($allTools | Sort-Object { $_.function.name })) {
    $name   = $toolSchema.function.name
    $prompt = if ($ToolPrompts.ContainsKey($name)) {
        $ToolPrompts[$name]
    } else {
        "Use the $name tool to demonstrate its functionality."
    }

    Write-Host ""
    Write-Host "  Testing: $name" -ForegroundColor DarkGray

    $tr = Invoke-AgentConversation -Prompt $prompt -Tools @($toolSchema) -MaxDepth 3

    # 1. No streaming/HTTP error
    $noErr = $null -eq $tr.StreamError
    Assert-True "[$name] no streaming error" $noErr
    if (-not $noErr) {
        Write-Host "    error: $($tr.StreamError)" -ForegroundColor Red
        $perToolFail++
        continue
    }

    # 2. Tool was actually called (model may sometimes answer without tools —
    #    that's a model quality issue, not a Matrix bug, so we warn not fail)
    $wasCalled = $tr.ToolsCalled -contains $name
    if (-not $wasCalled) {
        Write-Host "    [warn] model answered without calling $name (non-deterministic)" -ForegroundColor Yellow
    }
    Assert-True "[$name] tool was called" $wasCalled

    # 3. If called, result must be valid JSON (tool errors from external services are OK)
    if ($wasCalled -and $tr.ToolErrors.Count -gt 0) {
        Write-Host "    [warn] tool returned error field: $($tr.ToolErrors -join '; ')" -ForegroundColor Yellow
    }

    # 4. Agent completed the conversation — tool called OR text produced counts as a response
    $responded = $wasCalled -or (-not [string]::IsNullOrWhiteSpace($tr.AnyText))
    Assert-True "[$name] agent completed a response" $responded
}

# Clean up temp file if Write-FileContent created it
if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -EA SilentlyContinue }

$failed = Show-TestSummary
exit $failed

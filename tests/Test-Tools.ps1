#!/usr/bin/env pwsh
# Matrix Tool Tests — unit tests for every tool in tools/.
# Calls each tool directly (no Ollama required) and validates output shape,
# JSON validity, error handling, and cross-platform behaviour.

param(
    [switch]$SchemaOnly   # only validate schemas, skip live calls
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Test-Framework.ps1")

# ── Get-Time ─────────────────────────────────────────────────────────────────
Start-Suite "Get-Time"
Test-ToolSchema "Get-Time"
$out = Invoke-Tool "Get-Time"
Assert-ValidJson  "returns valid JSON"        $out
Assert-NoError    "no error field"            $out
$obj = Get-ToolOutput $out
Assert-HasKey     "has Time field"    $obj "Time"
Assert-HasKey     "has TimeZone field" $obj "TimeZone"
Assert-True       "Time is non-empty" (-not [string]::IsNullOrWhiteSpace($obj.Time))

# ── Get-SystemInfo ────────────────────────────────────────────────────────────
Start-Suite "Get-SystemInfo"
Test-ToolSchema "Get-SystemInfo"
$out = Invoke-Tool "Get-SystemInfo"
Assert-ValidJson  "returns valid JSON"       $out
Assert-NoError    "no error field"           $out
$obj = Get-ToolOutput $out
Assert-HasKey     "has OS field"    $obj "OS"
Assert-HasKey     "has Architecture" $obj "Architecture"
Assert-True       "TotalMemoryGB is numeric" ($null -ne $obj.TotalMemoryGB -and [double]::TryParse("$($obj.TotalMemoryGB)", [ref]$null))

# ── Get-Weather ───────────────────────────────────────────────────────────────
Start-Suite "Get-Weather"
Test-ToolSchema "Get-Weather"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-Weather" @{ City = "London" }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error for London"   $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Temperature"  $obj "Temperature"
    Assert-HasKey     "has Condition"    $obj "Condition"

    $out2 = Invoke-Tool "Get-Weather" @{ City = "ZZZNOTACITY999" }
    Assert-ValidJson  "invalid city returns JSON" $out2
    # Should return either an error or a graceful response — not throw
}

# ── Get-WikipediaSummary ──────────────────────────────────────────────────────
Start-Suite "Get-WikipediaSummary"
Test-ToolSchema "Get-WikipediaSummary"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-WikipediaSummary" @{ Topic = "PowerShell" }
    Assert-ValidJson  "returns valid JSON"       $out
    Assert-NoError    "no error"                 $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Title"   $obj "Title"
    Assert-HasKey     "has Extract" $obj "Extract"
    Assert-True       "Extract non-empty" (-not [string]::IsNullOrWhiteSpace($obj.Extract))

    $out2 = Invoke-Tool "Get-WikipediaSummary" @{ Topic = "ZZZNOPAGEXYZ123" }
    Assert-ValidJson  "missing topic returns JSON" $out2
}

# ── Invoke-Math ───────────────────────────────────────────────────────────────
Start-Suite "Invoke-Math"
Test-ToolSchema "Invoke-Math"
$out = Invoke-Tool "Invoke-Math" @{ Expression = "2 + 2" }
Assert-ValidJson  "returns valid JSON"       $out
Assert-NoError    "no error"                 $out
$obj = Get-ToolOutput $out
Assert-Equal      "2+2 = 4"  4  $obj.Result

$out2 = Invoke-Tool "Invoke-Math" @{ Expression = "10 * (3 + 2)" }
$obj2 = Get-ToolOutput $out2
Assert-Equal      "10*(3+2) = 50"  50  $obj2.Result

$out3 = Invoke-Tool "Invoke-Math" @{ Expression = "1 / 0" }
Assert-ValidJson  "division by zero returns JSON"  $out3
# Should be an error or Infinity — not throw

# ── Read-File ─────────────────────────────────────────────────────────────────
Start-Suite "Read-File"
Test-ToolSchema "Read-File"

$tmpFile = [IO.Path]::GetTempFileName()
"Line1`nLine2`nLine3`nLine4`nLine5" | Set-Content $tmpFile -Encoding UTF8

$out = Invoke-Tool "Read-File" @{ Path = $tmpFile }
Assert-ValidJson  "returns valid JSON"           $out
Assert-NoError    "no error on existing file"    $out
$obj = Get-ToolOutput $out
Assert-Equal      "TotalLines = 5"  5  $obj.TotalLines
Assert-True       "Content is string" ($obj.Content -is [string])

$out2 = Invoke-Tool "Read-File" @{ Path = $tmpFile; StartLine = 2; EndLine = 3 }
$obj2 = Get-ToolOutput $out2
Assert-Equal      "Range returns lines 2-3"  "2-3"  $obj2.ReturnedLines

$out3 = Invoke-Tool "Read-File" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "matrix-no-such-file-xyzabc.txt") }
Assert-ValidJson  "missing file returns JSON"  $out3
$obj3 = Get-ToolOutput $out3
Assert-True       "missing file has error field"  ($null -ne $obj3.error)

Remove-Item $tmpFile -Force -EA SilentlyContinue

# ── Write-FileContent ─────────────────────────────────────────────────────────
Start-Suite "Write-FileContent"
Test-ToolSchema "Write-FileContent"

$tmpFile = [IO.Path]::GetTempFileName()
Remove-Item $tmpFile -Force  # start fresh

$out = Invoke-Tool "Write-FileContent" @{ Path = $tmpFile; Content = "Hello"; Overwrite = $true }
Assert-ValidJson  "returns valid JSON"    $out
Assert-NoError    "no error on write"     $out
Assert-True       "file was created"      (Test-Path $tmpFile)
$content = Get-Content $tmpFile -Raw
Assert-True       "content matches"       ($content.Trim() -eq "Hello")

$out2 = Invoke-Tool "Write-FileContent" @{ Path = $tmpFile; Content = " World"; Append = $true }
Assert-NoError    "no error on append"    $out2
$content2 = Get-Content $tmpFile -Raw
Assert-True       "append worked"         ($content2 -match "Hello")

# Overwrite guard: existing file without Overwrite or Append should fail
$out3 = Invoke-Tool "Write-FileContent" @{ Path = $tmpFile; Content = "New" }
$obj3 = Get-ToolOutput $out3
Assert-True       "overwrite guard returns error"  ($null -ne $obj3.error)

Remove-Item $tmpFile -Force -EA SilentlyContinue

# ── Find-Files ────────────────────────────────────────────────────────────────
Start-Suite "Find-Files"
Test-ToolSchema "Find-Files"

$tmpDir  = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-find-$PID"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
"alpha content" | Set-Content (Join-Path $tmpDir "alpha.txt")
"beta content"  | Set-Content (Join-Path $tmpDir "beta.txt")
"gamma"         | Set-Content (Join-Path $tmpDir "gamma.log")

$out = Invoke-Tool "Find-Files" @{ Path = $tmpDir; NamePattern = "*.txt" }
Assert-ValidJson  "returns valid JSON"     $out
Assert-NoError    "no error"               $out
$obj = Get-ToolOutput $out
Assert-Equal      "finds 2 txt files"  2  $obj.ResultCount

$out2 = Invoke-Tool "Find-Files" @{ Path = $tmpDir; ContentPattern = "beta" }
$obj2 = Get-ToolOutput $out2
Assert-True       "content search finds 1 result"  ($obj2.ResultCount -ge 1)

$out3 = Invoke-Tool "Find-Files" @{ Path = "/no/such/path"; NamePattern = "*" }
Assert-ValidJson  "bad path returns JSON"  $out3
$obj3 = Get-ToolOutput $out3
Assert-True       "bad path has error"     ($null -ne $obj3.error)

Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue

# ── Get-WebContent ────────────────────────────────────────────────────────────
Start-Suite "Get-WebContent"
Test-ToolSchema "Get-WebContent"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-WebContent" @{ Url = "https://example.com" }
    Assert-ValidJson  "returns valid JSON"          $out
    Assert-NoError    "no error for example.com"    $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Content field"   $obj "Content"
    Assert-True       "Content non-empty"   (-not [string]::IsNullOrWhiteSpace($obj.Content))

    $out2 = Invoke-Tool "Get-WebContent" @{ Url = "https://httpbin.org/status/404" }
    Assert-ValidJson  "404 returns JSON"  $out2
}

# ── Get-ProcessList ───────────────────────────────────────────────────────────
Start-Suite "Get-ProcessList"
Test-ToolSchema "Get-ProcessList"
$out = Invoke-Tool "Get-ProcessList" @{ Top = 5 }
Assert-ValidJson  "returns valid JSON"     $out
Assert-NoError    "no error"               $out
$obj = Get-ToolOutput $out
Assert-True       "Processes is an array"  ($obj.Processes -is [array] -or $obj.Processes.Count -ge 1)
Assert-True       "TotalShown <= 5"        ($obj.TotalShown -le 5)

$out2 = Invoke-Tool "Get-ProcessList" @{ Name = "pwsh" }
Assert-ValidJson  "filter by name returns JSON"  $out2
# pwsh is always running (we are in it)
$obj2 = Get-ToolOutput $out2
Assert-True       "finds pwsh process"   ($null -eq $obj2.error -and $obj2.TotalShown -ge 1)

# ── Invoke-ShellCommand ───────────────────────────────────────────────────────
Start-Suite "Invoke-ShellCommand"
Test-ToolSchema "Invoke-ShellCommand"

$cmd = if ($IsWindows) { "echo hello" } else { "echo hello" }
$out = Invoke-Tool "Invoke-ShellCommand" @{ Command = $cmd }
Assert-ValidJson  "returns valid JSON"    $out
Assert-NoError    "no error"              $out
$obj = Get-ToolOutput $out
Assert-True       "stdout contains hello" ($obj.Stdout -match "hello")
Assert-Equal      "exit code 0"  0  $obj.ExitCode

$out2 = Invoke-Tool "Invoke-ShellCommand" @{ Command = "sleep 999"; TimeoutSeconds = 1 }
Assert-ValidJson  "timeout returns JSON"  $out2
$obj2 = Get-ToolOutput $out2
Assert-True       "timeout returns error"  ($null -ne $obj2.error)

# ── Get-EnvVariable ───────────────────────────────────────────────────────────
Start-Suite "Get-EnvVariable"
Test-ToolSchema "Get-EnvVariable"

# Set a known test variable
$env:MATRIX_TEST_VAR = "matrix_test_value"

$out = Invoke-Tool "Get-EnvVariable" @{ Name = "MATRIX_TEST_VAR" }
Assert-ValidJson  "returns valid JSON"    $out
Assert-NoError    "no error"              $out
$obj = Get-ToolOutput $out
Assert-Equal      "correct value"  "matrix_test_value"  $obj.Value

$out2 = Invoke-Tool "Get-EnvVariable" @{ Name = "MATRIX_NONEXISTENT_XYZABC" }
$obj2 = Get-ToolOutput $out2
Assert-True       "missing var returns error"  ($null -ne $obj2.error)

$out3 = Invoke-Tool "Get-EnvVariable"
Assert-ValidJson  "all vars returns JSON"  $out3
Assert-NoError    "no error for all vars"  $out3
$obj3 = Get-ToolOutput $out3
Assert-True       "Variables is an array"  ($obj3.Variables.Count -gt 0)

Remove-Item Env:MATRIX_TEST_VAR -EA SilentlyContinue

# ── Convert-Units ─────────────────────────────────────────────────────────────
Start-Suite "Convert-Units"
Test-ToolSchema "Convert-Units"

$out = Invoke-Tool "Convert-Units" @{ Value = 100; From = "c"; To = "f" }
Assert-ValidJson  "returns valid JSON"        $out
Assert-NoError    "no error C→F"              $out
$obj = Get-ToolOutput $out
Assert-Equal      "100C = 212F"  212  $obj.Result

$out2 = Invoke-Tool "Convert-Units" @{ Value = 1; From = "km"; To = "miles" }
$obj2 = Get-ToolOutput $out2
Assert-True       "1km ≈ 0.62 miles"  ([math]::Abs($obj2.Result - 0.621371) -lt 0.001)

$out3 = Invoke-Tool "Convert-Units" @{ Value = 1; From = "gb"; To = "mb" }
$obj3 = Get-ToolOutput $out3
Assert-Equal      "1 GB = 1024 MB"  1024  $obj3.Result

$out4 = Invoke-Tool "Convert-Units" @{ Value = 1; From = "unknownunit"; To = "km" }
$obj4 = Get-ToolOutput $out4
Assert-True       "unknown unit returns error"  ($null -ne $obj4.error)

# ── Get-IPInfo ────────────────────────────────────────────────────────────────
Start-Suite "Get-IPInfo"
Test-ToolSchema "Get-IPInfo"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-IPInfo" @{ IPAddress = "8.8.8.8" }
    Assert-ValidJson  "returns valid JSON"      $out
    Assert-NoError    "no error for 8.8.8.8"    $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has IP field"     $obj "IP"
    Assert-HasKey     "has Country field" $obj "Country"

    $out2 = Invoke-Tool "Get-IPInfo" @{ IPAddress = "999.999.999.999" }
    Assert-ValidJson  "invalid IP returns JSON"  $out2
}

# ── Convert-DataFormat ────────────────────────────────────────────────────────
Start-Suite "Convert-DataFormat"
Test-ToolSchema "Convert-DataFormat"

$out = Invoke-Tool "Convert-DataFormat" @{
    Data = '[{"Name":"Alice","Age":30},{"Name":"Bob","Age":25}]'
    From = "json"
    To   = "csv"
}
Assert-ValidJson  "returns valid JSON"    $out
Assert-NoError    "no error JSON→CSV"     $out
$obj = Get-ToolOutput $out
Assert-Equal      "Count = 2"  2  $obj.Count
Assert-True       "Output contains Alice" ([bool]($obj.Output -match "Alice"))

$out2 = Invoke-Tool "Convert-DataFormat" @{
    Data = "Alice`nBob`nCharlie"
    From = "list"
    To   = "json"
}
Assert-ValidJson  "list→json returns valid JSON"  $out2
Assert-NoError    "no error list→JSON"            $out2
$obj2 = Get-ToolOutput $out2
Assert-Equal      "3 items"  3  $obj2.Count

$out3 = Invoke-Tool "Convert-DataFormat" @{
    Data = "not,valid,json,{"
    From = "json"
    To   = "csv"
}
Assert-ValidJson  "bad input returns JSON"  $out3
$obj3 = Get-ToolOutput $out3
Assert-True       "bad JSON returns error"  ($null -ne $obj3.error)

# ── Invoke-HttpRequest ────────────────────────────────────────────────────────
Start-Suite "Invoke-HttpRequest"
Test-ToolSchema "Invoke-HttpRequest"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Invoke-HttpRequest" @{ Uri = "https://httpbin.org/get" }
    Assert-ValidJson  "returns valid JSON"           $out
    Assert-NoError    "no error for valid URL"        $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has StatusCode"    $obj "StatusCode"
    Assert-HasKey     "has Content"       $obj "Content"
    Assert-Equal      "status 200"  200  $obj.StatusCode

    $out2 = Invoke-Tool "Invoke-HttpRequest" @{
        Uri    = "https://httpbin.org/post"
        Method = "POST"
        Body   = '{"test":1}'
    }
    Assert-ValidJson  "POST returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "POST status 200"  200  $obj2.StatusCode

    $out3 = Invoke-Tool "Invoke-HttpRequest" @{ Uri = "https://this-host-does-not-exist-xyzabc.invalid" }
    Assert-ValidJson  "bad URL returns JSON"  $out3
    $obj3 = Get-ToolOutput $out3
    Assert-True       "bad URL has error"  ($null -ne $obj3.error)
}

# ── Test-NetworkHost ──────────────────────────────────────────────────────────
Start-Suite "Test-NetworkHost"
Test-ToolSchema "Test-NetworkHost"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Test-NetworkHost" @{ Hostname = "localhost" }
    Assert-ValidJson  "returns valid JSON"        $out
    Assert-NoError    "no error for localhost"     $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Reachable"    $obj "Reachable"
    Assert-HasKey     "has DnsResolved"  $obj "DnsResolved"
    Assert-True       "localhost resolves"  ($obj.DnsResolved -eq $true)

    $out2 = Invoke-Tool "Test-NetworkHost" @{ Hostname = "localhost"; Port = 65534 }
    Assert-ValidJson  "port check returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "has PortOpen field"   ($null -ne $obj2.PortOpen -or $obj2.PortOpen -eq $false)

    $out3 = Invoke-Tool "Test-NetworkHost" @{ Hostname = "this-host-does-not-exist-xyzabc.invalid" }
    Assert-ValidJson  "bad host returns JSON"  $out3
    $obj3 = Get-ToolOutput $out3
    Assert-True       "bad host not resolved"  ($obj3.DnsResolved -eq $false)
}

# ── Get-NetworkAdapters ───────────────────────────────────────────────────────
Start-Suite "Get-NetworkAdapters"
Test-ToolSchema "Get-NetworkAdapters"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-NetworkAdapters"
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has AdapterCount"  $obj "AdapterCount"
    Assert-HasKey     "has Adapters"      $obj "Adapters"
    Assert-True       "at least one adapter"  ($obj.AdapterCount -ge 1)
}

# ── Get-DiskInfo ──────────────────────────────────────────────────────────────
Start-Suite "Get-DiskInfo"
Test-ToolSchema "Get-DiskInfo"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-DiskInfo"
    Assert-ValidJson  "returns valid JSON"  $out
    Assert-NoError    "no error"            $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has DriveCount"  $obj "DriveCount"
    Assert-HasKey     "has Drives"      $obj "Drives"
    Assert-True       "at least one drive"   ($obj.DriveCount -ge 1)
    $first = if ($obj.Drives -is [array]) { $obj.Drives[0] } else { $obj.Drives }
    Assert-True       "first drive has TotalGB > 0"  ($first.TotalGB -gt 0)
}

# ── Get-FileHash ──────────────────────────────────────────────────────────────
Start-Suite "Get-FileHash"
Test-ToolSchema "Get-FileHash"
if (-not $SchemaOnly) {
    $tmpFile = [IO.Path]::GetTempFileName()
    "matrix hash test" | Set-Content $tmpFile -Encoding UTF8

    $out = Invoke-Tool "Get-FileHash" @{ Path = $tmpFile }
    Assert-ValidJson  "returns valid JSON"  $out
    Assert-NoError    "no error"            $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Hash"       $obj "Hash"
    Assert-HasKey     "has Algorithm"  $obj "Algorithm"
    Assert-HasKey     "has SizeBytes"  $obj "SizeBytes"
    Assert-True       "Hash is 64 hex chars (SHA256)"  ($obj.Hash -match '^[0-9A-F]{64}$')
    Assert-Equal      "Algorithm is SHA256"  "SHA256"  $obj.Algorithm

    $out2 = Invoke-Tool "Get-FileHash" @{ Path = $tmpFile; Algorithm = "MD5" }
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "MD5 algorithm"  "MD5"  $obj2.Algorithm
    Assert-True       "MD5 is 32 hex chars"  ($obj2.Hash -match '^[0-9A-F]{32}$')

    $out3 = Invoke-Tool "Get-FileHash" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "matrix-no-file-hash-xyz.txt") }
    Assert-ValidJson  "missing file returns JSON"  $out3
    $obj3 = Get-ToolOutput $out3
    Assert-True       "missing file has error"  ($null -ne $obj3.error)

    Remove-Item $tmpFile -Force -EA SilentlyContinue
}

# ── Get-ActiveConnections ─────────────────────────────────────────────────────
Start-Suite "Get-ActiveConnections"
Test-ToolSchema "Get-ActiveConnections"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-ActiveConnections"
    Assert-ValidJson  "returns valid JSON"      $out
    Assert-NoError    "no error"                $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has ConnectionCount"  $obj "ConnectionCount"
    Assert-HasKey     "has Connections"      $obj "Connections"
    Assert-True       "ConnectionCount is non-negative"  ($obj.ConnectionCount -ge 0)
}

# ── New-ZipArchive ────────────────────────────────────────────────────────────
Start-Suite "New-ZipArchive"
Test-ToolSchema "New-ZipArchive"
if (-not $SchemaOnly) {
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) "matrix-zip-src-$PID"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    "file one"  | Set-Content (Join-Path $tmpDir "a.txt") -Encoding UTF8
    "file two"  | Set-Content (Join-Path $tmpDir "b.txt") -Encoding UTF8
    $zipPath = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-$PID.zip"

    $out = Invoke-Tool "New-ZipArchive" @{ SourcePath = $tmpDir; DestinationPath = $zipPath }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has SizeBytes"     $obj "SizeBytes"
    Assert-HasKey     "has EntryCount"    $obj "EntryCount"
    Assert-True       "SizeBytes > 0"     ($obj.SizeBytes -gt 0)
    Assert-True       "EntryCount = 2"    ($obj.EntryCount -eq 2)
    Assert-True       "zip file exists"   (Test-Path $zipPath)

    # Overwrite guard
    $out2 = Invoke-Tool "New-ZipArchive" @{ SourcePath = $tmpDir; DestinationPath = $zipPath; Overwrite = $false }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "no-overwrite returns error"  ($null -ne $obj2.error)

    # Overwrite=true replaces
    $out3 = Invoke-Tool "New-ZipArchive" @{ SourcePath = $tmpDir; DestinationPath = $zipPath; Overwrite = $true }
    Assert-NoError    "overwrite=true succeeds"  $out3

    Remove-Item $tmpDir  -Recurse -Force -EA SilentlyContinue
    # keep $zipPath for Expand test below
}

# ── Expand-ZipArchive ─────────────────────────────────────────────────────────
Start-Suite "Expand-ZipArchive"
Test-ToolSchema "Expand-ZipArchive"
if (-not $SchemaOnly) {
    $zipPath  = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-$PID.zip"
    $xDst     = Join-Path ([IO.Path]::GetTempPath()) "matrix-zip-dst-$PID"

    if (Test-Path $zipPath) {
        $out = Invoke-Tool "Expand-ZipArchive" @{ SourcePath = $zipPath; DestinationPath = $xDst }
        Assert-ValidJson  "returns valid JSON"    $out
        Assert-NoError    "no error"              $out
        $obj = Get-ToolOutput $out
        Assert-HasKey     "has EntryCount"    $obj "EntryCount"
        Assert-HasKey     "has Files"         $obj "Files"
        Assert-True       "EntryCount = 2"    ($obj.EntryCount -eq 2)
        Assert-True       "extracted dir exists"  (Test-Path $xDst)
    } else {
        # Create a fresh zip for this test
        $tmpFile = [IO.Path]::GetTempFileName()
        "hello" | Set-Content $tmpFile
        Invoke-Tool "New-ZipArchive" @{ SourcePath = $tmpFile; DestinationPath = $zipPath; Overwrite = $true } | Out-Null
        $out = Invoke-Tool "Expand-ZipArchive" @{ SourcePath = $zipPath; DestinationPath = $xDst }
        Assert-ValidJson  "returns valid JSON"  $out
        Assert-NoError    "no error"            $out
        Remove-Item $tmpFile -Force -EA SilentlyContinue
    }

    $out2 = Invoke-Tool "Expand-ZipArchive" @{
        SourcePath      = (Join-Path ([IO.Path]::GetTempPath()) "no-such-file-xyz.zip")
        DestinationPath = $xDst
    }
    Assert-ValidJson  "bad source returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "bad source has error"  ($null -ne $obj2.error)

    Remove-Item $xDst    -Recurse -Force -EA SilentlyContinue
    Remove-Item $zipPath -Force         -EA SilentlyContinue
}

# ── Get-DirectoryTree ─────────────────────────────────────────────────────────
Start-Suite "Get-DirectoryTree"
Test-ToolSchema "Get-DirectoryTree"
if (-not $SchemaOnly) {
    $toolsDir = Join-Path $PSScriptRoot ".." "tools"
    $out = Invoke-Tool "Get-DirectoryTree" @{ Path = $toolsDir }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has TotalFiles"   $obj "TotalFiles"
    Assert-HasKey     "has Tree"         $obj "Tree"
    Assert-True       "TotalFiles >= 15"  ($obj.TotalFiles -ge 15)

    $out2 = Invoke-Tool "Get-DirectoryTree" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "no-dir-xyz-$PID") }
    Assert-ValidJson  "bad path returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "bad path has error"  ($null -ne $obj2.error)
}

# ── Copy-FileItem ─────────────────────────────────────────────────────────────
Start-Suite "Copy-FileItem"
Test-ToolSchema "Copy-FileItem"
if (-not $SchemaOnly) {
    $src = [IO.Path]::GetTempFileName()
    "copy test content" | Set-Content $src -Encoding UTF8
    $dst = Join-Path ([IO.Path]::GetTempPath()) "matrix-copy-dst-$PID.txt"

    $out = Invoke-Tool "Copy-FileItem" @{ Source = $src; Destination = $dst }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-True       "destination exists"   (Test-Path $dst)
    Assert-Equal      "IsDirectory=false"  $false  $obj.IsDirectory

    # Overwrite guard
    $out2 = Invoke-Tool "Copy-FileItem" @{ Source = $src; Destination = $dst; Overwrite = $false }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "existing dest returns error"  ($null -ne $obj2.error)

    # Overwrite=true
    $out3 = Invoke-Tool "Copy-FileItem" @{ Source = $src; Destination = $dst; Overwrite = $true }
    Assert-NoError    "overwrite=true succeeds"  $out3

    Remove-Item $src -Force -EA SilentlyContinue
    Remove-Item $dst -Force -EA SilentlyContinue
}

# ── Remove-FileItem ───────────────────────────────────────────────────────────
Start-Suite "Remove-FileItem"
Test-ToolSchema "Remove-FileItem"
if (-not $SchemaOnly) {
    $tmpFile = [IO.Path]::GetTempFileName()
    "to be deleted" | Set-Content $tmpFile -Encoding UTF8

    # Confirm=$true (default) — should NOT delete
    $out = Invoke-Tool "Remove-FileItem" @{ Path = $tmpFile }
    Assert-ValidJson  "returns valid JSON (Confirm=true)"   $out
    $obj = Get-ToolOutput $out
    Assert-True       "Confirm=true returns error"   ($null -ne $obj.error)
    Assert-True       "file still exists after Confirm=true guard"  (Test-Path $tmpFile)

    # Confirm=$false — should delete
    $out2 = Invoke-Tool "Remove-FileItem" @{ Path = $tmpFile; Confirm = $false }
    Assert-ValidJson  "returns valid JSON (Confirm=false)"  $out2
    Assert-NoError    "no error on delete"                  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "Deleted=true"  $true  $obj2.Deleted
    Assert-True       "file gone after delete"  (-not (Test-Path $tmpFile))

    # Missing path
    $out3 = Invoke-Tool "Remove-FileItem" @{ Path = $tmpFile; Confirm = $false }
    Assert-ValidJson  "missing path returns JSON"  $out3
    $obj3 = Get-ToolOutput $out3
    Assert-True       "missing path has error"  ($null -ne $obj3.error)
}

# ── Write-DocxFile ────────────────────────────────────────────────────────────
Start-Suite "Write-DocxFile"
Test-ToolSchema "Write-DocxFile"
if (-not $SchemaOnly) {
    $docPath = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-$PID.docx"

    $out = Invoke-Tool "Write-DocxFile" @{
        Path       = $docPath
        Paragraphs = @("Hello World", "Second paragraph", "Third paragraph")
        Overwrite  = $true
    }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has ParagraphCount"  $obj "ParagraphCount"
    Assert-HasKey     "has SizeBytes"       $obj "SizeBytes"
    Assert-True       "file exists"         (Test-Path $docPath)
    Assert-True       "SizeBytes > 0"       ($obj.SizeBytes -gt 0)
    Assert-True       "ParagraphCount = 3"  ($obj.ParagraphCount -eq 3)

    # Overwrite guard
    $out2 = Invoke-Tool "Write-DocxFile" @{ Path = $docPath; Paragraphs = @("x"); Overwrite = $false }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "overwrite guard returns error"  ($null -ne $obj2.error)

    # keep $docPath for Read-DocxFile round-trip
}

# ── Read-DocxFile ─────────────────────────────────────────────────────────────
Start-Suite "Read-DocxFile"
Test-ToolSchema "Read-DocxFile"
if (-not $SchemaOnly) {
    $docPath = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-$PID.docx"

    # Ensure the file exists (create if Write-DocxFile test didn't run or cleaned up)
    if (-not (Test-Path $docPath)) {
        Invoke-Tool "Write-DocxFile" @{
            Path       = $docPath
            Paragraphs = @("Hello World", "Second paragraph", "Third paragraph")
            Overwrite  = $true
        } | Out-Null
    }

    $out = Invoke-Tool "Read-DocxFile" @{ Path = $docPath }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has ParagraphCount"   $obj "ParagraphCount"
    Assert-HasKey     "has Text"             $obj "Text"
    Assert-HasKey     "has Paragraphs"       $obj "Paragraphs"
    Assert-True       "ParagraphCount = 3"   ($obj.ParagraphCount -eq 3)
    Assert-True       "Text non-empty"       (-not [string]::IsNullOrWhiteSpace($obj.Text))

    $out2 = Invoke-Tool "Read-DocxFile" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "no-file-xyz.docx") }
    Assert-ValidJson  "missing file returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "missing file has error"  ($null -ne $obj2.error)

    Remove-Item $docPath -Force -EA SilentlyContinue
}

# ── Write-XlsxFile ────────────────────────────────────────────────────────────
Start-Suite "Write-XlsxFile"
Test-ToolSchema "Write-XlsxFile"
if (-not $SchemaOnly) {
    $xlsxPath = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-$PID.xlsx"
    $testData = @(
        @{ Name = "Alice"; Age = 30; City = "London" }
        @{ Name = "Bob";   Age = 25; City = "Paris"  }
        @{ Name = "Carol"; Age = 35; City = "Berlin" }
    )

    $out = Invoke-Tool "Write-XlsxFile" @{
        Path      = $xlsxPath
        Data      = $testData
        SheetName = "People"
        Overwrite = $true
    }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has RowCount"      $obj "RowCount"
    Assert-HasKey     "has ColumnCount"   $obj "ColumnCount"
    Assert-HasKey     "has SizeBytes"     $obj "SizeBytes"
    Assert-Equal      "RowCount = 3"    3  $obj.RowCount
    Assert-Equal      "ColumnCount = 3" 3  $obj.ColumnCount
    Assert-True       "file exists"        (Test-Path $xlsxPath)
    Assert-True       "SizeBytes > 0"     ($obj.SizeBytes -gt 0)

    # Overwrite guard
    $out2 = Invoke-Tool "Write-XlsxFile" @{ Path = $xlsxPath; Data = $testData; Overwrite = $false }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "overwrite guard returns error"  ($null -ne $obj2.error)

    # keep $xlsxPath for Read-XlsxFile round-trip
}

# ── Read-XlsxFile ─────────────────────────────────────────────────────────────
Start-Suite "Read-XlsxFile"
Test-ToolSchema "Read-XlsxFile"
if (-not $SchemaOnly) {
    $xlsxPath = Join-Path ([IO.Path]::GetTempPath()) "matrix-test-$PID.xlsx"
    $testData = @(
        @{ Name = "Alice"; Age = 30; City = "London" }
        @{ Name = "Bob";   Age = 25; City = "Paris"  }
        @{ Name = "Carol"; Age = 35; City = "Berlin" }
    )

    if (-not (Test-Path $xlsxPath)) {
        Invoke-Tool "Write-XlsxFile" @{
            Path      = $xlsxPath
            Data      = $testData
            SheetName = "People"
            Overwrite = $true
        } | Out-Null
    }

    $out = Invoke-Tool "Read-XlsxFile" @{ Path = $xlsxPath }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has SheetName"    $obj "SheetName"
    Assert-HasKey     "has RowCount"     $obj "RowCount"
    Assert-HasKey     "has Rows"         $obj "Rows"
    # Header row + 3 data rows = 4 total rows
    Assert-Equal      "RowCount = 4"   4  $obj.RowCount

    $out2 = Invoke-Tool "Read-XlsxFile" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "no-file-xyz.xlsx") }
    Assert-ValidJson  "missing file returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "missing file has error"  ($null -ne $obj2.error)

    Remove-Item $xlsxPath -Force -EA SilentlyContinue
}

# ── ConvertTo-Base64 ──────────────────────────────────────────────────────────
Start-Suite "ConvertTo-Base64"
Test-ToolSchema "ConvertTo-Base64"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "ConvertTo-Base64" @{ Text = "hello world" }
    Assert-ValidJson  "returns valid JSON"      $out
    Assert-NoError    "no error"                $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Base64"          $obj "Base64"
    Assert-HasKey     "has SourceType"      $obj "SourceType"
    Assert-Equal      "SourceType=Text"  "Text"  $obj.SourceType
    Assert-Equal      "correct base64"  "aGVsbG8gd29ybGQ="  $obj.Base64

    $tmpFile = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllBytes($tmpFile, [byte[]]@(1,2,3,4,5))
    $out2 = Invoke-Tool "ConvertTo-Base64" @{ FilePath = $tmpFile }
    Assert-ValidJson  "file encode returns JSON"   $out2
    Assert-NoError    "no error for file"           $out2
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "SourceType=File"  "File"   $obj2.SourceType
    Assert-Equal      "OriginalSizeBytes=5"  5    $obj2.OriginalSizeBytes
    Remove-Item $tmpFile -Force -EA SilentlyContinue

    $out3 = Invoke-Tool "ConvertTo-Base64"
    Assert-ValidJson  "no params returns JSON"  $out3
    $obj3 = Get-ToolOutput $out3
    Assert-True       "no params has error"  ($null -ne $obj3.error)
}

# ── ConvertFrom-Base64 ────────────────────────────────────────────────────────
Start-Suite "ConvertFrom-Base64"
Test-ToolSchema "ConvertFrom-Base64"
if (-not $SchemaOnly) {
    # Round-trip a known string
    $out = Invoke-Tool "ConvertFrom-Base64" @{ Base64 = "aGVsbG8gd29ybGQ=" }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Text"          $obj "Text"
    Assert-Equal      "decoded correctly"  "hello world"  $obj.Text

    # Decode to file
    $tmpDst = Join-Path ([IO.Path]::GetTempPath()) "matrix-b64-dst-$PID.bin"
    $out2 = Invoke-Tool "ConvertFrom-Base64" @{ Base64 = "AQIDBAU="; FilePath = $tmpDst }
    Assert-ValidJson  "file decode returns JSON"   $out2
    Assert-NoError    "no error for file decode"   $out2
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "SizeBytes=5"  5  $obj2.SizeBytes
    Assert-True       "file written"  (Test-Path $tmpDst)
    Remove-Item $tmpDst -Force -EA SilentlyContinue

    # Invalid base64
    $out3 = Invoke-Tool "ConvertFrom-Base64" @{ Base64 = "not!valid!base64!!!" }
    Assert-ValidJson  "bad base64 returns JSON"  $out3
    $obj3 = Get-ToolOutput $out3
    Assert-True       "bad base64 has error"  ($null -ne $obj3.error)
}

# ── Get-RegexMatches ──────────────────────────────────────────────────────────
Start-Suite "Get-RegexMatches"
Test-ToolSchema "Get-RegexMatches"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-RegexMatches" @{ Pattern = '\d+'; InputText = "abc 123 def 456" }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-Equal      "MatchCount = 2"  2  $obj.MatchCount

    # Named capture group
    $out2 = Invoke-Tool "Get-RegexMatches" @{ Pattern = '(?<word>[a-z]+)'; InputText = "hello world" }
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "2 word matches"  2  $obj2.MatchCount

    # No matches
    $out3 = Invoke-Tool "Get-RegexMatches" @{ Pattern = '\d{10}'; InputText = "no numbers here" }
    $obj3 = Get-ToolOutput $out3
    Assert-Equal      "MatchCount = 0"  0  $obj3.MatchCount

    # Invalid regex
    $out4 = Invoke-Tool "Get-RegexMatches" @{ Pattern = '[invalid'; InputText = "test" }
    Assert-ValidJson  "bad regex returns JSON"  $out4
    $obj4 = Get-ToolOutput $out4
    Assert-True       "bad regex has error"  ($null -ne $obj4.error)
}

# ── Invoke-TextTemplate ───────────────────────────────────────────────────────
Start-Suite "Invoke-TextTemplate"
Test-ToolSchema "Invoke-TextTemplate"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Invoke-TextTemplate" @{
        Template  = "Hello {{name}}, you are {{age}} years old."
        Variables = @{ name = "Alice"; age = "30" }
    }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Result"   $obj "Result"
    Assert-Equal      "correct substitution"  "Hello Alice, you are 30 years old."  $obj.Result
    Assert-Equal      "ReplacementsMade = 2"  2  $obj.ReplacementsMade

    # Missing variable — unreplaced placeholder stays
    $out2 = Invoke-Tool "Invoke-TextTemplate" @{
        Template  = "Hello {{name}} from {{city}}"
        Variables = @{ name = "Bob" }
    }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "partial replace: name filled"  ($obj2.Result -match "Bob")
    Assert-True       "partial replace: city kept"    ($obj2.Result -match "\{\{city\}\}")
}

# ── Get-ClipboardContent ──────────────────────────────────────────────────────
Start-Suite "Get-ClipboardContent"
Test-ToolSchema "Get-ClipboardContent"
if (-not $SchemaOnly) {
    # Set then get — if clipboard unavailable the tool returns graceful error
    Invoke-Tool "Set-ClipboardContent" @{ Text = "matrix-clipboard-test-$PID" } | Out-Null
    $out = Invoke-Tool "Get-ClipboardContent"
    Assert-ValidJson  "returns valid JSON"  $out
    # Don't assert NoError — clipboard may be unavailable in CI
    $obj = Get-ToolOutput $out
    Assert-True       "has Content or error field"  ($null -ne $obj.Content -or $null -ne $obj.error)
}

# ── Set-ClipboardContent ──────────────────────────────────────────────────────
Start-Suite "Set-ClipboardContent"
Test-ToolSchema "Set-ClipboardContent"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Set-ClipboardContent" @{ Text = "matrix-set-clipboard-$PID" }
    Assert-ValidJson  "returns valid JSON"  $out
    $obj = Get-ToolOutput $out
    Assert-True       "has Success or error field"  ($null -ne $obj.Success -or $null -ne $obj.error)
}

# ── Protect-String ────────────────────────────────────────────────────────────
Start-Suite "Protect-String"
Test-ToolSchema "Protect-String"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Protect-String" @{ Text = "hello world"; Password = "s3cr3t" }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has CipherText"    $obj "CipherText"
    Assert-HasKey     "has Algorithm"     $obj "Algorithm"
    Assert-Equal      "Algorithm correct"  "AES-256-CBC"  $obj.Algorithm
    Assert-True       "CipherText non-empty"  (-not [string]::IsNullOrWhiteSpace($obj.CipherText))
    Assert-True       "CipherText changes each call"  ($obj.CipherText -ne (Get-ToolOutput (Invoke-Tool "Protect-String" @{ Text = "hello world"; Password = "s3cr3t" })).CipherText)
}

# ── Unprotect-String ──────────────────────────────────────────────────────────
Start-Suite "Unprotect-String"
Test-ToolSchema "Unprotect-String"
if (-not $SchemaOnly) {
    # Encrypt then decrypt
    $enc = Get-ToolOutput (Invoke-Tool "Protect-String" @{ Text = "round-trip test"; Password = "mypassword" })
    $out = Invoke-Tool "Unprotect-String" @{ CipherText = $enc.CipherText; Password = "mypassword" }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Text"   $obj "Text"
    Assert-Equal      "decrypted correctly"  "round-trip test"  $obj.Text

    # Wrong password returns error
    $out2 = Invoke-Tool "Unprotect-String" @{ CipherText = $enc.CipherText; Password = "wrongpassword" }
    Assert-ValidJson  "wrong password returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "wrong password has error"  ($null -ne $obj2.error)
}

# ── New-SecureToken ────────────────────────────────────────────────────────────
Start-Suite "New-SecureToken"
Test-ToolSchema "New-SecureToken"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "New-SecureToken"
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Token"    $obj "Token"
    Assert-HasKey     "has Charset"  $obj "Charset"
    Assert-Equal      "default length 32"  32  $obj.Length
    Assert-True       "Hex token is hex chars"  ($obj.Token -match '^[0-9A-F]{32}$')

    $out2 = Invoke-Tool "New-SecureToken" @{ Length = 16; Charset = "Alphanumeric" }
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "length 16"  16  $obj2.Length
    Assert-True       "alphanumeric only"  ($obj2.Token -match '^[A-Za-z0-9]{16}$')

    $out3 = Invoke-Tool "New-SecureToken" @{ Length = 24; Charset = "Base64" }
    $obj3 = Get-ToolOutput $out3
    Assert-Equal      "length 24"  24  $obj3.Length
    Assert-True       "Base64 chars only"  ($obj3.Token -match '^[A-Za-z0-9]{24}$')
}

# ── Get-ServiceList ───────────────────────────────────────────────────────────
Start-Suite "Get-ServiceList"
Test-ToolSchema "Get-ServiceList"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-ServiceList"
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has ServiceCount"  $obj "ServiceCount"
    Assert-HasKey     "has Services"      $obj "Services"
    Assert-True       "ServiceCount >= 0"  ($obj.ServiceCount -ge 0)

    # Filter that matches nothing
    $out2 = Invoke-Tool "Get-ServiceList" @{ Name = "matrix-nonexistent-service-xyz*" }
    Assert-ValidJson  "nonexistent filter returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "ServiceCount = 0 or no error"  ($obj2.ServiceCount -eq 0 -or $null -eq $obj2.error)
}

# ── Set-ServiceState ──────────────────────────────────────────────────────────
Start-Suite "Set-ServiceState"
Test-ToolSchema "Set-ServiceState"
if (-not $SchemaOnly) {
    # Only test error path — starting/stopping real services is too risky in CI
    $out = Invoke-Tool "Set-ServiceState" @{ Name = "matrix-no-such-service-xyz"; Action = "Start" }
    Assert-ValidJson  "invalid service returns JSON"  $out
    $obj = Get-ToolOutput $out
    Assert-True       "invalid service has error"  ($null -ne $obj.error)
}

# ── Get-EventLogEntries ───────────────────────────────────────────────────────
Start-Suite "Get-EventLogEntries"
Test-ToolSchema "Get-EventLogEntries"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-EventLogEntries" @{ Newest = 10 }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has EntryCount"   $obj "EntryCount"
    Assert-HasKey     "has LogSource"    $obj "LogSource"
    Assert-HasKey     "has Entries"      $obj "Entries"
    Assert-True       "EntryCount >= 0"  ($obj.EntryCount -ge 0)
}

# ── Get-ScheduledTaskList ─────────────────────────────────────────────────────
Start-Suite "Get-ScheduledTaskList"
Test-ToolSchema "Get-ScheduledTaskList"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-ScheduledTaskList"
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Platform"     $obj "Platform"
    Assert-HasKey     "has TaskCount"    $obj "TaskCount"
    Assert-HasKey     "has Tasks"        $obj "Tasks"
    Assert-True       "TaskCount >= 0"   ($obj.TaskCount -ge 0)
}

# ── Get-CertificateInfo ───────────────────────────────────────────────────────
Start-Suite "Get-CertificateInfo"
Test-ToolSchema "Get-CertificateInfo"
if (-not $SchemaOnly) {
    # Neither param provided
    $out = Invoke-Tool "Get-CertificateInfo"
    Assert-ValidJson  "no params returns JSON"  $out
    $obj = Get-ToolOutput $out
    Assert-True       "no params has error"  ($null -ne $obj.error)

    # Both params provided
    $out2 = Invoke-Tool "Get-CertificateInfo" @{ Path = "x.crt"; Url = "https://example.com" }
    Assert-ValidJson  "both params returns JSON"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-True       "both params has error"  ($null -ne $obj2.error)

    # Live HTTPS URL
    $out3 = Invoke-Tool "Get-CertificateInfo" @{ Url = "https://example.com" }
    Assert-ValidJson  "HTTPS URL returns JSON"  $out3
    $obj3 = Get-ToolOutput $out3
    if ($null -eq $obj3.error) {
        Assert-HasKey "has Thumbprint"       $obj3 "Thumbprint"
        Assert-HasKey "has DaysUntilExpiry"  $obj3 "DaysUntilExpiry"
        Assert-True   "Thumbprint non-empty"  (-not [string]::IsNullOrWhiteSpace($obj3.Thumbprint))
        Assert-True   "cert not expired"      ($obj3.DaysUntilExpiry -gt 0)
    }
    # If error (no network), just verify valid JSON was returned — already checked above
}

# ── Send-SystemNotification ───────────────────────────────────────────────────
Start-Suite "Send-SystemNotification"
Test-ToolSchema "Send-SystemNotification"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Send-SystemNotification" @{ Title = "Matrix Test"; Message = "Wave 6 notification test" }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Success"   $obj "Success"
    Assert-HasKey     "has Method"    $obj "Method"
    Assert-HasKey     "has Platform"  $obj "Platform"
    # Success may be false in headless CI — just verify valid structure
    Assert-True       "Success is bool"  ($obj.Success -is [bool] -or $obj.Success -eq $true -or $obj.Success -eq $false)
}

# ── Edit-FileContent ──────────────────────────────────────────────────────────
Start-Suite "Edit-FileContent"
Test-ToolSchema "Edit-FileContent"
if (-not $SchemaOnly) {
    $tmpF = [IO.Path]::GetTempFileName()
    "Hello world`nfoo bar`nfoo baz" | Set-Content $tmpF -Encoding UTF8
    $out = Invoke-Tool "Edit-FileContent" @{ Path = $tmpF; Find = "foo"; Replace = "qux"; ReplaceAll = $true }
    Assert-ValidJson  "returns valid JSON"         $out
    Assert-NoError    "no error on replace"        $out
    $obj = Get-ToolOutput $out
    Assert-Equal      "ReplacementsCount = 2"  2   $obj.ReplacementsCount
    $content = Get-Content $tmpF -Raw
    Assert-True       "replacements applied"   ($content -match 'qux bar')

    $out2 = Invoke-Tool "Edit-FileContent" @{ Path = $tmpF; Find = "nomatch"; Replace = "x" }
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "no match returns 0"  0  $obj2.ReplacementsCount

    $out3 = Invoke-Tool "Edit-FileContent" @{ Path = $tmpF; Find = "q\w+"; Replace = "Z"; UseRegex = $true; ReplaceAll = $true }
    Assert-NoError    "regex mode no error"  $out3
    $obj3 = Get-ToolOutput $out3
    Assert-True       "regex replacements > 0"  ($obj3.ReplacementsCount -gt 0)

    Remove-Item $tmpF -Force -EA SilentlyContinue
}

# ── Move-FileItem ──────────────────────────────────────────────────────────────
Start-Suite "Move-FileItem"
Test-ToolSchema "Move-FileItem"
if (-not $SchemaOnly) {
    $tmpSrc = [IO.Path]::GetTempFileName()
    $tmpDst = [IO.Path]::GetTempFileName(); Remove-Item $tmpDst -Force
    "move me" | Set-Content $tmpSrc -Encoding UTF8
    $out = Invoke-Tool "Move-FileItem" @{ Source = $tmpSrc; Destination = $tmpDst }
    Assert-ValidJson  "returns valid JSON"      $out
    Assert-NoError    "no error on move"        $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Source"       $obj "Source"
    Assert-HasKey     "has Destination"  $obj "Destination"
    Assert-True       "source gone"      (-not (Test-Path $tmpSrc))
    Assert-True       "dest exists"      (Test-Path $tmpDst)

    $out2 = Invoke-Tool "Move-FileItem" @{ Source = $tmpSrc; Destination = $tmpDst }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "missing source returns error"  ($null -ne $obj2.error)

    Remove-Item $tmpDst -Force -EA SilentlyContinue
}

# ── Compare-FileContent ────────────────────────────────────────────────────────
Start-Suite "Compare-FileContent"
Test-ToolSchema "Compare-FileContent"
if (-not $SchemaOnly) {
    $tmpA = [IO.Path]::GetTempFileName()
    $tmpB = [IO.Path]::GetTempFileName()
    "line1`nline2`nline3" | Set-Content $tmpA -Encoding UTF8
    "line1`nline4`nline3" | Set-Content $tmpB -Encoding UTF8
    $out = Invoke-Tool "Compare-FileContent" @{ PathA = $tmpA; PathB = $tmpB }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has AreSame"      $obj "AreSame"
    Assert-HasKey     "has AddedCount"   $obj "AddedCount"
    Assert-HasKey     "has RemovedCount" $obj "RemovedCount"
    Assert-True       "files differ"     (-not $obj.AreSame)

    # Identical files
    $out2 = Invoke-Tool "Compare-FileContent" @{ PathA = $tmpA; PathB = $tmpA }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "identical files AreSame"  ($obj2.AreSame -eq $true)

    Remove-Item $tmpA,$tmpB -Force -EA SilentlyContinue
}

# ── Sort-FileItems ─────────────────────────────────────────────────────────────
Start-Suite "Sort-FileItems"
Test-ToolSchema "Sort-FileItems"
if (-not $SchemaOnly) {
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) "matrix-sort-$(New-Guid)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    'a' | Set-Content (Join-Path $tmpDir "file.txt")  -Encoding UTF8
    'b' | Set-Content (Join-Path $tmpDir "file.ps1")  -Encoding UTF8
    'c' | Set-Content (Join-Path $tmpDir "file.json") -Encoding UTF8
    $out = Invoke-Tool "Sort-FileItems" @{ Path = $tmpDir; GroupBy = "Extension" }
    Assert-ValidJson  "returns valid JSON"        $out
    Assert-NoError    "no error"                  $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has FilesProcessed" $obj "FilesProcessed"
    Assert-HasKey     "has Groups"         $obj "Groups"
    Assert-Equal      "FilesProcessed = 3"  3   $obj.FilesProcessed
    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue
}

# ── Read-PptxFile ──────────────────────────────────────────────────────────────
Start-Suite "Read-PptxFile"
Test-ToolSchema "Read-PptxFile"
if (-not $SchemaOnly) {
    $tmpPptx = [IO.Path]::GetTempFileName() -replace '\.tmp$','.pptx'
    $writeOut = Invoke-Tool "Write-PptxFile" @{
        Path = $tmpPptx
        Slides = @(@{ Title = "Slide One"; Content = "Body text here" }, @{ Title = "Slide Two"; Content = "More content" })
        Overwrite = $true
    }
    Assert-NoError "write succeeded for read test"  $writeOut

    $out = Invoke-Tool "Read-PptxFile" @{ Path = $tmpPptx }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error reading"     $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has SlideCount"  $obj "SlideCount"
    Assert-HasKey     "has Slides"      $obj "Slides"
    Assert-Equal      "SlideCount = 2"  2   $obj.SlideCount

    $out2 = Invoke-Tool "Read-PptxFile" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "no-such.pptx") }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "missing file has error"  ($null -ne $obj2.error)
    Remove-Item $tmpPptx -Force -EA SilentlyContinue
}

# ── Write-PptxFile ─────────────────────────────────────────────────────────────
Start-Suite "Write-PptxFile"
Test-ToolSchema "Write-PptxFile"
if (-not $SchemaOnly) {
    $tmpPptx = [IO.Path]::GetTempFileName() -replace '\.tmp$','.pptx'
    Remove-Item $tmpPptx -Force -EA SilentlyContinue
    $out = Invoke-Tool "Write-PptxFile" @{
        Path   = $tmpPptx
        Slides = @("First slide text", "Second slide text")
    }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has SlideCount"  $obj "SlideCount"
    Assert-HasKey     "has SizeBytes"   $obj "SizeBytes"
    Assert-Equal      "SlideCount = 2"  2    $obj.SlideCount
    Assert-True       "file created"    (Test-Path $tmpPptx)
    Assert-True       "size > 0"        ($obj.SizeBytes -gt 0)

    $out2 = Invoke-Tool "Write-PptxFile" @{ Path = $tmpPptx; Slides = @("x") }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "overwrite guard returns error"  ($null -ne $obj2.error)
    Remove-Item $tmpPptx -Force -EA SilentlyContinue
}

# ── Write-PdfFile ─────────────────────────────────────────────────────────────
Start-Suite "Write-PdfFile"
Test-ToolSchema "Write-PdfFile"
if (-not $SchemaOnly) {
    $tmpPdf = [IO.Path]::GetTempFileName() -replace '\.tmp$','.pdf'
    Remove-Item $tmpPdf -Force -EA SilentlyContinue
    $out = Invoke-Tool "Write-PdfFile" @{ Path = $tmpPdf; Lines = @("Hello PDF","Line two","Line three") }
    Assert-ValidJson  "returns valid JSON"  $out
    Assert-NoError    "no error"            $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has PageCount"  $obj "PageCount"
    Assert-HasKey     "has LineCount"  $obj "LineCount"
    Assert-HasKey     "has SizeBytes"  $obj "SizeBytes"
    Assert-True       "file created"   (Test-Path $tmpPdf)
    Assert-True       "size > 0"       ($obj.SizeBytes -gt 0)
    Assert-Equal      "LineCount = 3"  3  $obj.LineCount

    $out2 = Invoke-Tool "Write-PdfFile" @{ Path = $tmpPdf; Lines = @("x") }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "overwrite guard"  ($null -ne $obj2.error)
    Remove-Item $tmpPdf -Force -EA SilentlyContinue
}

# ── Read-PdfFile ───────────────────────────────────────────────────────────────
Start-Suite "Read-PdfFile"
Test-ToolSchema "Read-PdfFile"
if (-not $SchemaOnly) {
    $tmpPdf = [IO.Path]::GetTempFileName() -replace '\.tmp$','.pdf'
    Remove-Item $tmpPdf -Force -EA SilentlyContinue
    Invoke-Tool "Write-PdfFile" @{ Path = $tmpPdf; Lines = @("Hello PDF World","Second line here") } | Out-Null
    $out = Invoke-Tool "Read-PdfFile" @{ Path = $tmpPdf }
    Assert-ValidJson  "returns valid JSON"  $out
    Assert-NoError    "no error"            $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has PageCount"  $obj "PageCount"
    Assert-HasKey     "has Text"       $obj "Text"
    Assert-HasKey     "has CharCount"  $obj "CharCount"
    Assert-True       "CharCount > 0"  ($obj.CharCount -gt 0)

    $out2 = Invoke-Tool "Read-PdfFile" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "no-such.pdf") }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "missing file error"  ($null -ne $obj2.error)
    Remove-Item $tmpPdf -Force -EA SilentlyContinue
}

# ── Get-ImageMetadata ──────────────────────────────────────────────────────────
Start-Suite "Get-ImageMetadata"
Test-ToolSchema "Get-ImageMetadata"
if (-not $SchemaOnly) {
    # Use a non-JPEG file — no EXIF expected
    $tmpPng = [IO.Path]::GetTempFileName() -replace '\.tmp$','.png'
    [IO.File]::WriteAllBytes($tmpPng, [byte[]]@(0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A))
    $out = Invoke-Tool "Get-ImageMetadata" @{ Path = $tmpPng }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error for PNG"     $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Format"    $obj "Format"
    Assert-HasKey     "has HasExif"   $obj "HasExif"
    Assert-True       "HasExif false for non-JPEG"  ($obj.HasExif -eq $false)

    $out2 = Invoke-Tool "Get-ImageMetadata" @{ Path = (Join-Path ([IO.Path]::GetTempPath()) "no-such.jpg") }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "missing file error"  ($null -ne $obj2.error)
    Remove-Item $tmpPng -Force -EA SilentlyContinue
}

# ── Search-Images ──────────────────────────────────────────────────────────────
Start-Suite "Search-Images"
Test-ToolSchema "Search-Images"
if (-not $SchemaOnly) {
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) "matrix-imgsch-$(New-Guid)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    # Create dummy jpg files
    'fake' | Set-Content (Join-Path $tmpDir "a.jpg") -Encoding UTF8
    'fake' | Set-Content (Join-Path $tmpDir "b.jpg") -Encoding UTF8
    $out = Invoke-Tool "Search-Images" @{ Path = $tmpDir }
    Assert-ValidJson  "returns valid JSON"    $out
    Assert-NoError    "no error"              $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has TotalScanned"  $obj "TotalScanned"
    Assert-HasKey     "has MatchCount"    $obj "MatchCount"
    Assert-HasKey     "has Images"        $obj "Images"
    Assert-Equal      "TotalScanned = 2"  2  $obj.TotalScanned
    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue
}

# ── Sort-ImageFiles ────────────────────────────────────────────────────────────
Start-Suite "Sort-ImageFiles"
Test-ToolSchema "Sort-ImageFiles"
if (-not $SchemaOnly) {
    $tmpSrc = Join-Path ([IO.Path]::GetTempPath()) "matrix-imgsort-$(New-Guid)"
    $tmpDst = Join-Path ([IO.Path]::GetTempPath()) "matrix-imgsort-dst-$(New-Guid)"
    New-Item -ItemType Directory -Path $tmpSrc -Force | Out-Null
    'fake' | Set-Content (Join-Path $tmpSrc "photo.jpg") -Encoding UTF8
    $out = Invoke-Tool "Sort-ImageFiles" @{ SourcePath = $tmpSrc; DestinationPath = $tmpDst }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has TotalFiles"      $obj "TotalFiles"
    Assert-HasKey     "has Sorted"          $obj "Sorted"
    Assert-HasKey     "has FoldersCreated"  $obj "FoldersCreated"
    Assert-Equal      "TotalFiles = 1"  1   $obj.TotalFiles
    Assert-Equal      "Sorted = 1"      1   $obj.Sorted
    Remove-Item $tmpSrc -Recurse -Force -EA SilentlyContinue
    Remove-Item $tmpDst -Recurse -Force -EA SilentlyContinue
}

# ── New-WebSession ─────────────────────────────────────────────────────────────
Start-Suite "New-WebSession"
Test-ToolSchema "New-WebSession"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "New-WebSession" @{}
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has SessionPath"  $obj "SessionPath"
    Assert-HasKey     "has CookieCount"  $obj "CookieCount"
    Assert-True       "session file exists"  (Test-Path $obj.SessionPath)
    Assert-Equal      "CookieCount = 0"  0  $obj.CookieCount

    $out2 = Invoke-Tool "New-WebSession" @{ BaseUrl = "https://example.com" }
    $obj2 = Get-ToolOutput $out2
    Assert-Equal      "BaseUrl stored"  "https://example.com"  $obj2.BaseUrl

    Remove-Item $obj.SessionPath  -Force -EA SilentlyContinue
    Remove-Item $obj2.SessionPath -Force -EA SilentlyContinue
}

# ── Invoke-WebSession ──────────────────────────────────────────────────────────
Start-Suite "Invoke-WebSession"
Test-ToolSchema "Invoke-WebSession"
if (-not $SchemaOnly) {
    # Create session first
    $sessOut = Invoke-Tool "New-WebSession" @{}
    $sessObj = Get-ToolOutput $sessOut
    $sessPath = $sessObj.SessionPath

    $out = Invoke-Tool "Invoke-WebSession" @{ SessionPath = $sessPath; Uri = "https://httpbin.org/get" }
    Assert-ValidJson  "returns valid JSON"   $out
    Assert-NoError    "no error"             $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has StatusCode"  $obj "StatusCode"
    Assert-HasKey     "has Content"     $obj "Content"
    Assert-Equal      "StatusCode = 200"  200  $obj.StatusCode

    $out2 = Invoke-Tool "Invoke-WebSession" @{ SessionPath = (Join-Path ([IO.Path]::GetTempPath()) "no-session.json"); Uri = "https://httpbin.org/get" }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "missing session error"  ($null -ne $obj2.error)

    Remove-Item $sessPath -Force -EA SilentlyContinue
}

# ── Get-RssFeed ────────────────────────────────────────────────────────────────
Start-Suite "Get-RssFeed"
Test-ToolSchema "Get-RssFeed"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-RssFeed" @{ Url = "https://feeds.bbci.co.uk/news/rss.xml"; MaxItems = 5 }
    Assert-ValidJson  "returns valid JSON"  $out
    Assert-NoError    "no error"            $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has FeedTitle"   $obj "FeedTitle"
    Assert-HasKey     "has Format"      $obj "Format"
    Assert-HasKey     "has Items"       $obj "Items"
    Assert-Equal      "Format is RSS"   "RSS"  $obj.Format
    Assert-True       "items returned"  ($obj.ItemCount -gt 0)
}

# ── Get-CurrencyRate ───────────────────────────────────────────────────────────
Start-Suite "Get-CurrencyRate"
Test-ToolSchema "Get-CurrencyRate"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-CurrencyRate" @{ BaseCurrency = "USD" }
    Assert-ValidJson  "returns valid JSON"     $out
    Assert-NoError    "no error for USD base"  $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Base"          $obj "Base"
    Assert-HasKey     "has CurrencyCount" $obj "CurrencyCount"
    Assert-Equal      "Base = USD"  "USD"  $obj.Base
    Assert-True       "CurrencyCount > 0"  ($obj.CurrencyCount -gt 0)

    $out2 = Invoke-Tool "Get-CurrencyRate" @{ BaseCurrency = "USD"; TargetCurrency = "EUR" }
    Assert-NoError    "no error for EUR target"  $out2
    $obj2 = Get-ToolOutput $out2
    Assert-HasKey     "has Rate"  $obj2 "Rate"
    Assert-True       "Rate is number"  ($obj2.Rate -gt 0)
}

# ── Get-StockQuote ─────────────────────────────────────────────────────────────
Start-Suite "Get-StockQuote"
Test-ToolSchema "Get-StockQuote"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-StockQuote" @{ Symbol = "MSFT" }
    Assert-ValidJson  "returns valid JSON"  $out
    Assert-NoError    "no error for MSFT"  $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Symbol"    $obj "Symbol"
    Assert-HasKey     "has Price"     $obj "Price"
    Assert-HasKey     "has Currency"  $obj "Currency"
    Assert-True       "Price > 0"     ($obj.Price -gt 0)
    Assert-True       "Currency non-empty"  (-not [string]::IsNullOrWhiteSpace($obj.Currency))
}

# ── Get-DnsRecord ──────────────────────────────────────────────────────────────
Start-Suite "Get-DnsRecord"
Test-ToolSchema "Get-DnsRecord"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "Get-DnsRecord" @{ Hostname = "github.com"; Type = "A" }
    Assert-ValidJson  "returns valid JSON"       $out
    Assert-NoError    "no error for github.com"  $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Hostname"     $obj "Hostname"
    Assert-HasKey     "has Records"      $obj "Records"
    Assert-HasKey     "has RecordCount"  $obj "RecordCount"
    Assert-True       "RecordCount > 0"  ($obj.RecordCount -gt 0)
}

# ── Summary ───────────────────────────────────────────────────────────────────
$failed = Show-TestSummary
exit $failed

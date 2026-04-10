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

# ── Summary ───────────────────────────────────────────────────────────────────
$failed = Show-TestSummary
exit $failed

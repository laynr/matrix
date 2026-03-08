# Automated Toolchain Test Script for Matrix CLI
$ErrorActionPreference = "Stop"

$global:MatrixRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$global:MatrixRoot\lib\Config.ps1"
. "$global:MatrixRoot\lib\Context.ps1"
. "$global:MatrixRoot\lib\Network.ps1"
. "$global:MatrixRoot\lib\Logger.ps1"
. "$global:MatrixRoot\lib\ToolManager.ps1"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "    Matrix AI Agent Automated Tests      " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$testConfig = Load-Config
$testTools = Get-MatrixTools

function Run-Test {
    param([string]$TestName, [string]$Prompt)
    
    Write-Host "`n[TEST] $TestName" -ForegroundColor Yellow
    Write-Host "Prompt: $Prompt" -ForegroundColor DarkGray
    
    Clear-Messages
    Add-Message -Role "user" -Content $Prompt
    
    $response = Invoke-MatrixChat -Config $testConfig -Messages (Get-Messages) -Tools $testTools
    
    if ($response.error) {
        Write-Host "FAILED: $($response.error)" -ForegroundColor Red
        return $false
    }
    
    $toolsCalled = @()
    if ($response.content) {
        foreach ($c in $response.content) {
            if ($c.type -eq "tool_use") {
                $toolsCalled += $c.name
            }
        }
    }
    
    if ($toolsCalled.Count -gt 0) {
        Write-Host "SUCCESS: Tools Called -> $($toolsCalled -join ', ')" -ForegroundColor Green
        return $true
    } else {
        Write-Host "FAILED: No tools were called by the LLM." -ForegroundColor Red
        Write-Host "RAW RESPONSE:" -ForegroundColor DarkGray
        $response | ConvertTo-Json -Depth 5 | Write-Host
        return $false
    }
}

$testsPassed = 0
$totalTests = 4

if (Run-Test "Math Tool Evaluation" "What is 1560 divided by 4?") { $testsPassed++ }
if (Run-Test "Weather Tool Evaluation" "What's the weather like in Tokyo right now?") { $testsPassed++ }
if (Run-Test "System Info Evaluation" "Can you check my operating system and memory load?") { $testsPassed++ }
if (Run-Test "Wikipedia Tool Evaluation" "Who was Julius Caesar?") { $testsPassed++ }
if (Run-Test "Multi-Tool Simultaneous Evaluation" "What's the weather in Seattle, and who was Abraham Lincoln, and what is 500 divided by 2?") { $testsPassed++ }
if (Run-Test "Complex Sequential Multi-Tool Evaluation" "multiple the time by the number of Ram the compter has, then tell me the weather") { $testsPassed++ }

$totalTests = 6

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "TEST RESULTS: $testsPassed / $totalTests Passed" -ForegroundColor Cyan
if ($testsPassed -eq $totalTests) {
    Write-Host "All tool routing behaves as expected!" -ForegroundColor Green
} else {
    Write-Host "Some tests failed tool routing." -ForegroundColor Red
}
Write-Host "=========================================" -ForegroundColor Cyan

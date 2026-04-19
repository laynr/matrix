#!/usr/bin/env pwsh
# Config unit tests — covers Load-Config, Save-Config, Select-MatrixModel,
# Get-SystemRamGB, and Get-OllamaModels. No network or Ollama required.

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Test-Framework.ps1")

$global:MatrixRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $global:MatrixRoot "lib" "Logger.ps1")
. (Join-Path $global:MatrixRoot "lib" "Config.ps1")

function Write-MatrixLog { param($Message, $Level = "INFO") }

$configPath = Join-Path $global:MatrixRoot "config.json"

# ── Load-Config: no config.json ───────────────────────────────────────────────

Start-Suite "Load-Config — no config.json"

$savedContent = if (Test-Path $configPath) { Get-Content $configPath -Raw } else { $null }
if (Test-Path $configPath) { Remove-Item $configPath -Force }

try {
    $cfg = Load-Config

    Assert-NotNull "Returns non-null config"    $cfg
    Assert-Equal   "Default Provider is Ollama" "Ollama"   $cfg.Provider
    Assert-Equal   "Default Model is qwen3:4b"  "qwen3:4b" $cfg.Model
    Assert-Equal   "ModelExplicit is false"     $false     $cfg.ModelExplicit

    Assert-NotNull "ModelTiers is not null"     $cfg.ModelTiers
    Assert-True    "ModelTiers is non-empty"    ($cfg.ModelTiers.Count -gt 0)
    $firstTier = $cfg.ModelTiers[0]
    Assert-True    "First ModelTier is hashtable"        ($firstTier -is [hashtable])
    Assert-True    "First ModelTier has MinRamGB key"    ($firstTier.ContainsKey('MinRamGB'))
    Assert-True    "First ModelTier has Model key"       ($firstTier.ContainsKey('Model'))

    Assert-NotNull "CoreTools is not null"      $cfg.CoreTools
    Assert-True    "CoreTools is array"         ($cfg.CoreTools -is [array] -or $cfg.CoreTools.GetType().IsArray)

    Assert-True    "NumCtx is int"              ($cfg.NumCtx    -is [int])
    Assert-True    "MaxTokens is int"           ($cfg.MaxTokens -is [int])
    Assert-True    "MaxDepth is int"            ($cfg.MaxDepth  -is [int])
} finally {
    if ($null -ne $savedContent) { $savedContent | Set-Content $configPath -Encoding UTF8 -NoNewline }
}

# ── Load-Config: with config.json ─────────────────────────────────────────────

Start-Suite "Load-Config — with config.json"

$savedContent2 = if (Test-Path $configPath) { Get-Content $configPath -Raw } else { $null }

try {
    # Model key present → ModelExplicit = $true
    @{ Model = "llama3.2:3b"; Provider = "Ollama" } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
    $cfg = Load-Config
    Assert-Equal "ModelExplicit=true when Model key present" $true         $cfg.ModelExplicit
    Assert-Equal "Model loaded from file"                    "llama3.2:3b" $cfg.Model

    # Model key absent → ModelExplicit = $false
    @{ Provider = "CustomProvider" } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
    $cfg = Load-Config
    Assert-Equal "ModelExplicit=false when Model key absent" $false           $cfg.ModelExplicit
    Assert-Equal "Provider loaded from file"                 "CustomProvider" $cfg.Provider

    # ModelTiers from JSON parsed as [hashtable] array (not PSCustomObject)
    $tiersJson = @{ ModelTiers = @(
        @{ MinRamGB = 16; Model = "bigmodel:latest" }
        @{ MinRamGB = 8;  Model = "smallmodel:3b"   }
    ) } | ConvertTo-Json -Depth 5
    $tiersJson | Set-Content $configPath -Encoding UTF8
    $cfg = Load-Config
    $t0 = $cfg.ModelTiers[0]
    $t1 = $cfg.ModelTiers[1]
    Assert-True  "ModelTier[0] is hashtable"            ($t0 -is [hashtable])
    Assert-Equal "ModelTier[0].MinRamGB preserved"      16                 $t0.MinRamGB
    Assert-Equal "ModelTier[0].Model preserved"         "bigmodel:latest"  $t0.Model
    Assert-True  "ModelTier[1] is hashtable"            ($t1 -is [hashtable])
    Assert-Equal "ModelTier[1].MinRamGB preserved"      8                  $t1.MinRamGB

    # Invalid Endpoint → falls back to default
    @{ Endpoint = "ftp://badscheme/api" } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
    $cfg = Load-Config
    Assert-Equal "Invalid Endpoint falls back to default" "http://localhost:11434/api/chat" $cfg.Endpoint

    # Corrupt JSON → all defaults, ModelExplicit = $false
    "this is not json {{{{" | Set-Content $configPath -Encoding UTF8
    $cfg = Load-Config
    Assert-Equal "Corrupt JSON returns default model"          "qwen3:4b" $cfg.Model
    Assert-Equal "Corrupt JSON returns ModelExplicit=false"    $false     $cfg.ModelExplicit

    # Explicit values override defaults
    @{ Provider = "OpenAI"; NumCtx = 4096; MaxDepth = 5; CoreTools = @("Get-Weather") } |
        ConvertTo-Json | Set-Content $configPath -Encoding UTF8
    $cfg = Load-Config
    Assert-Equal "Provider override applied"   "OpenAI" $cfg.Provider
    Assert-Equal "NumCtx override applied"     4096     $cfg.NumCtx
    Assert-Equal "MaxDepth override applied"   5        $cfg.MaxDepth
    Assert-True  "CoreTools override applied"  ($cfg.CoreTools -contains "Get-Weather")
} finally {
    if ($null -ne $savedContent2) { $savedContent2 | Set-Content $configPath -Encoding UTF8 -NoNewline }
    elseif (Test-Path $configPath) { Remove-Item $configPath -Force }
}

# ── Save-Config ───────────────────────────────────────────────────────────────

Start-Suite "Save-Config"

$savedContent3 = if (Test-Path $configPath) { Get-Content $configPath -Raw } else { $null }

try {
    $testCfg = @{
        Provider     = "Ollama"
        Model        = "qwen3:8b"
        Endpoint     = "http://localhost:11434/api/chat"
        SystemPrompt = "Test prompt"
        NumCtx       = 0
        MaxTokens    = 100000
        SummarizeAt  = 75000
        MaxDepth     = 10
        ToolBudgetTokens = 6000
        MaxToolCount     = 25
        CoreTools    = @("Get-DateTime")
        ModelTiers   = @(@{ MinRamGB = 12; Model = "qwen3:8b" })
        ModelExplicit = $true
    }
    Save-Config -Config $testCfg

    $raw = Get-Content $configPath -Raw | ConvertFrom-Json

    Assert-True "ModelExplicit NOT in saved JSON"  (-not ($raw.PSObject.Properties.Name -contains 'ModelExplicit'))
    Assert-True "Model present in saved JSON"      ($raw.PSObject.Properties.Name -contains 'Model')
    Assert-True "Provider present in saved JSON"   ($raw.PSObject.Properties.Name -contains 'Provider')
    Assert-True "ModelTiers present in saved JSON" ($raw.PSObject.Properties.Name -contains 'ModelTiers')
    Assert-True "CoreTools present in saved JSON"  ($raw.PSObject.Properties.Name -contains 'CoreTools')

    Assert-Equal "ModelTiers[0].MinRamGB round-trip" 12         $raw.ModelTiers[0].MinRamGB
    Assert-Equal "ModelTiers[0].Model round-trip"    "qwen3:8b" $raw.ModelTiers[0].Model

    # Save → Load round-trip
    $reloaded = Load-Config
    Assert-Equal "Round-trip: Model matches"    "qwen3:8b" $reloaded.Model
    Assert-Equal "Round-trip: Provider matches" "Ollama"   $reloaded.Provider
} finally {
    if ($null -ne $savedContent3) { $savedContent3 | Set-Content $configPath -Encoding UTF8 -NoNewline }
    elseif (Test-Path $configPath) { Remove-Item $configPath -Force }
}

# ── Select-MatrixModel boundary cases ─────────────────────────────────────────

Start-Suite "Select-MatrixModel — boundary cases"

$tiers = @(
    @{ MinRamGB = 20; Model = "qwen3:8b"    }
    @{ MinRamGB = 12; Model = "qwen2.5:7b"  }
    @{ MinRamGB = 6;  Model = "qwen3:4b"    }
    @{ MinRamGB = 0;  Model = "llama3.2:3b" }
)
$cfg = @{ ModelTiers = $tiers }

# RAM exactly at threshold qualifies that tier
function Get-SystemRamGB  { return 12 }
function Get-OllamaModels { return @("qwen2.5:7b") }
Assert-Equal "RAM=12 qualifies MinRamGB=12 tier" "qwen2.5:7b" (Select-MatrixModel -Config $cfg)

# RAM one below threshold skips that tier
function Get-SystemRamGB  { return 11 }
function Get-OllamaModels { return @("qwen3:4b") }
Assert-Equal "RAM=11 skips MinRamGB=12, picks MinRamGB=6" "qwen3:4b" (Select-MatrixModel -Config $cfg)

# Tag variant: installed qwen3:8b-q4_0 matches tier qwen3:8b
function Get-SystemRamGB  { return 24 }
function Get-OllamaModels { return @("qwen3:8b-q4_0") }
Assert-Equal "Variant tag qwen3:8b-q4_0 matches tier qwen3:8b" "qwen3:8b" (Select-MatrixModel -Config $cfg)

# Empty ModelTiers → last-resort default
function Get-SystemRamGB  { return 32 }
function Get-OllamaModels { return @() }
Assert-Equal "Empty ModelTiers returns qwen3:4b default" "qwen3:4b" (Select-MatrixModel -Config @{ ModelTiers = @() })

# No tier model is installed but a non-tier model is → first installed returned
function Get-SystemRamGB  { return 0 }
function Get-OllamaModels { return @("phi3:mini") }
$noMatchCfg = @{ ModelTiers = @(@{ MinRamGB = 0; Model = "qwen3:4b" }) }
Assert-Equal "Falls back to first installed when no tier model present" "phi3:mini" (Select-MatrixModel -Config $noMatchCfg)

# ── Get-SystemRamGB platform detection ────────────────────────────────────────

Start-Suite "Get-SystemRamGB — platform detection"

# Reload real function (remove mock overrides from above)
Remove-Item Function:\Get-SystemRamGB -ErrorAction SilentlyContinue
Remove-Item Function:\Get-OllamaModels -ErrorAction SilentlyContinue
. (Join-Path $global:MatrixRoot "lib" "Config.ps1")
function Write-MatrixLog { param($Message, $Level = "INFO") }

$ramGB = Get-SystemRamGB
Assert-True "Returns positive value"      ($ramGB -gt 0)
Assert-True "Result compares as number"   ([math]::Floor($ramGB) -ge 1)

# ── Get-OllamaModels structure ────────────────────────────────────────────────

Start-Suite "Get-OllamaModels — structure"

$src = Get-Content (Join-Path $global:MatrixRoot "lib" "Config.ps1") -Raw
Assert-True "Source has catch fallback returning empty array"  ($src -match 'catch.*return @\(\)')
Assert-True "Source skips header line"                         ($src -match 'Select-Object -Skip 1')

if (Get-Command ollama -ErrorAction SilentlyContinue) {
    $models = Get-OllamaModels
    Assert-True "Result is array type"  ($models -is [array] -or $models.GetType().BaseType.Name -eq 'Array')
}

$failed = Show-TestSummary
exit $failed

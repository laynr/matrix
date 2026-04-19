function Get-SystemRamGB {
    try {
        if ($IsWindows) {
            return [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB)
        } elseif ($IsMacOS) {
            return [math]::Round([long](& sysctl -n hw.memsize) / 1GB)
        } else {
            $kb = [long](((Get-Content /proc/meminfo -ErrorAction Stop) -match '^MemTotal:') -replace '[^\d]')
            return [math]::Round($kb / 1MB)
        }
    } catch {
        return 8
    }
}

# Returns base names of all models currently pulled in Ollama.
function Get-OllamaModels {
    try {
        $lines = & ollama list 2>$null | Select-Object -Skip 1
        return @($lines | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
    } catch { return @() }
}

# Walks ModelTiers top-down, picking the best model that fits available RAM AND
# is already pulled in Ollama. Falls back to the first installed model if none
# of the tiers match, then to qwen3:4b as a last resort.
# Skipped entirely when the user has pinned a model in config.json.
function Select-MatrixModel {
    param([hashtable]$Config)
    $ramGB     = Get-SystemRamGB
    $installed = Get-OllamaModels

    foreach ($tier in ($Config.ModelTiers | Sort-Object { $_.MinRamGB } -Descending)) {
        if ($ramGB -lt $tier.MinRamGB) { continue }
        # If Ollama isn't reachable yet, trust RAM fit and return the tier model
        if ($installed.Count -eq 0) { return $tier.Model }
        $base = $tier.Model.Split(":")[0]
        if ($installed | Where-Object { $_ -match "^$([regex]::Escape($base))" }) {
            return $tier.Model
        }
    }

    # No tier model is installed — use whatever is available, or fall back to default
    if ($installed.Count -gt 0) {
        Write-MatrixLog -Level "WARN" -Message "No tier model installed; using first available: $($installed[0])"
        return $installed[0]
    }
    return "qwen3:4b"
}

function Load-Config {
    $configPath = Join-Path $global:MatrixRoot "config.json"
    $defaults = @{
        Provider     = "Ollama"
        Model        = "qwen3:4b"
        Endpoint     = "http://localhost:11434/api/chat"
        SystemPrompt = "You are Matrix, a helpful AI agent. Use the tools available to you when they are needed to answer the user. Be concise and direct."
        NumCtx       = 0
        MaxTokens        = 100000
        SummarizeAt      = 75000
        MaxDepth         = 10
        ToolBudgetTokens = 6000
        MaxToolCount     = 25
        CoreTools        = @()
        ModelTiers       = @(
            @{ MinRamGB = 20; Model = "qwen3:8b"     }
            @{ MinRamGB = 12; Model = "qwen2.5:7b"   }
            @{ MinRamGB = 6;  Model = "qwen3:4b"     }
            @{ MinRamGB = 0;  Model = "llama3.2:3b"  }
        )
        ModelExplicit = $false
    }

    if (Test-Path $configPath) {
        try {
            $json   = Get-Content $configPath -Raw | ConvertFrom-Json
            $config = @{
                Provider     = if ($json.Provider)     { [string]$json.Provider }     else { $defaults.Provider }
                Model        = if ($json.Model)        { [string]$json.Model }        else { $defaults.Model }
                Endpoint     = if ($json.Endpoint)     { [string]$json.Endpoint }     else { $defaults.Endpoint }
                SystemPrompt = if ($json.SystemPrompt) { [string]$json.SystemPrompt } else { $defaults.SystemPrompt }
                NumCtx       = if ($null -ne $json.NumCtx)      { [int]$json.NumCtx }      else { $defaults.NumCtx }
                MaxTokens    = if ($null -ne $json.MaxTokens)   { [int]$json.MaxTokens }   else { $defaults.MaxTokens }
                SummarizeAt  = if ($null -ne $json.SummarizeAt) { [int]$json.SummarizeAt } else { $defaults.SummarizeAt }
                MaxDepth         = if ($null -ne $json.MaxDepth)         { [int]$json.MaxDepth }         else { $defaults.MaxDepth }
                ToolBudgetTokens = if ($null -ne $json.ToolBudgetTokens) { [int]$json.ToolBudgetTokens } else { $defaults.ToolBudgetTokens }
                MaxToolCount     = if ($null -ne $json.MaxToolCount)     { [int]$json.MaxToolCount }     else { $defaults.MaxToolCount }
                CoreTools        = if ($json.CoreTools)                  { [string[]]$json.CoreTools }   else { $defaults.CoreTools }
                ModelTiers       = if ($json.ModelTiers) {
                    @($json.ModelTiers | ForEach-Object { @{ MinRamGB = [int]$_.MinRamGB; Model = [string]$_.Model } })
                } else { $defaults.ModelTiers }
                ModelExplicit = ($json.PSObject.Properties.Name -contains 'Model')
            }
            if ($config.Endpoint -notmatch '^https?://') {
                Write-Warning "config.json: Endpoint '$($config.Endpoint)' is not a valid URL — using default."
                $config.Endpoint = $defaults.Endpoint
            }
            return $config
        } catch {
            Write-Warning "Failed to parse config.json — using defaults. $_"
        }
    }

    return $defaults
}

function Save-Config {
    param([hashtable]$Config)
    $configPath = Join-Path $global:MatrixRoot "config.json"
    # Exclude internal tracking keys before saving
    $toSave = @{}
    foreach ($k in $Config.Keys) {
        if ($k -notin @('ModelExplicit')) { $toSave[$k] = $Config[$k] }
    }
    $toSave | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
}

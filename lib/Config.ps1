function Load-Config {
    $configPath = Join-Path $global:MatrixRoot "config.json"
    $defaults = @{
        Provider     = "Ollama"
        Model        = "gemma4:latest"
        Endpoint     = "http://localhost:11434/api/chat"
        SystemPrompt = "You are Matrix, a helpful AI agent. Use the tools available to you when they are needed to answer the user. Be concise and direct."
        NumCtx       = 0
        MaxTokens    = 100000
        SummarizeAt  = 75000
        MaxDepth     = 10
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
                MaxDepth     = if ($null -ne $json.MaxDepth)    { [int]$json.MaxDepth }    else { $defaults.MaxDepth }
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
    $Config | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
}

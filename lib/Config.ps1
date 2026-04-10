function Load-Config {
    $configPath = Join-Path $global:MatrixRoot "config.json"
    if (Test-Path $configPath) {
        try {
            $json = Get-Content $configPath -Raw | ConvertFrom-Json
            return @{
                Provider     = [string]$json.Provider
                Model        = [string]$json.Model
                Endpoint     = [string]$json.Endpoint
                SystemPrompt = [string]$json.SystemPrompt
                NumCtx       = if ($null -ne $json.NumCtx) { [int]$json.NumCtx } else { 0 }
            }
        } catch {
            Write-Warning "Failed to parse config.json — using defaults. $_"
        }
    }

    return @{
        Provider     = "Ollama"
        Model        = "gemma4:latest"
        Endpoint     = "http://localhost:11434/api/chat"
        SystemPrompt = "You are Matrix, a helpful AI agent. Use the tools available to you when they are needed to answer the user. Be concise and direct."
        NumCtx       = 0
    }
}

function Save-Config {
    param([hashtable]$Config)
    $configPath = Join-Path $global:MatrixRoot "config.json"
    $Config | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
}

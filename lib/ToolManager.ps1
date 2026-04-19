# Discovers tools from the tools/ directory and builds Ollama-compatible schemas.
# Each tool is a .ps1 file. The function name = file basename.
# Parameters and .SYNOPSIS are parsed via PowerShell AST.
# Schemas are cached in memory and persisted to tools/.schema-cache.json so cold
# starts skip AST parsing when no tool files have changed.

$script:ToolCache           = $null
$script:ToolCacheMtime      = @{}
$script:ToolDiscoveryErrors = @()
$script:ToolSchemaJsonCache = @{}

function Get-SchemaCachePath {
    Join-Path $global:MatrixRoot "tools" ".schema-cache.json"
}

function Load-ToolSchemaCache {
    param([hashtable]$Fingerprint)
    $path = Get-SchemaCachePath
    if (-not (Test-Path $path)) { return $null }
    try {
        $cached = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $fp = $cached.fingerprint
        if (-not $fp) { return $null }
        # Count must match
        $cachedCount = ($fp.PSObject.Properties | Measure-Object).Count
        if ($cachedCount -ne $Fingerprint.Count) { return $null }
        # Every key and value must match
        foreach ($key in $Fingerprint.Keys) {
            if ($fp.$key -ne $Fingerprint[$key]) { return $null }
        }
        return $cached
    } catch { return $null }
}

function Save-ToolSchemaCache {
    param([hashtable]$Fingerprint, [array]$Schemas, [hashtable]$SchemaJson)
    try {
        @{
            fingerprint = $Fingerprint
            schemas     = $Schemas
            schemaJson  = $SchemaJson
        } | ConvertTo-Json -Depth 10 -Compress | Set-Content (Get-SchemaCachePath) -Encoding UTF8
    } catch {
        Write-MatrixLog -Level "WARN" -Message "Failed to write schema cache: $_"
    }
}

function Reset-ToolCache {
    $script:ToolCache           = $null
    $script:ToolCacheMtime      = @{}
    $script:ToolDiscoveryErrors = @()
    $script:ToolSchemaJsonCache = @{}
    $cachePath = Get-SchemaCachePath
    if (Test-Path $cachePath) { Remove-Item $cachePath -Force -ErrorAction SilentlyContinue }
}

function Get-MatrixTools {
    $root     = if ($global:MatrixRoot) { $global:MatrixRoot } else { Split-Path -Parent $PSScriptRoot }
    $toolsDir = Join-Path $root "tools"

    Write-MatrixLog -Message "Scanning tools in: $toolsDir"

    if (-not (Test-Path $toolsDir)) {
        Write-MatrixLog -Level "WARN" -Message "tools/ directory not found at $toolsDir"
        return @()
    }

    $scripts = @(Get-ChildItem -Path $toolsDir -Filter "*.ps1")

    # Build mtime fingerprint for all tool files
    $fingerprint = @{}
    foreach ($s in $scripts) { $fingerprint[$s.BaseName] = $s.LastWriteTime.ToString("o") }

    # In-memory cache hit
    $dirty = ($scripts.Count -ne $script:ToolCacheMtime.Count) -or
             ($scripts | Where-Object { $script:ToolCacheMtime[$_.BaseName] -ne $_.LastWriteTime })

    if (-not $dirty -and $script:ToolCache) {
        Write-MatrixLog -Message "Tool cache hit ($($script:ToolCache.Count) tools)"
        return $script:ToolCache
    }

    # Disk cache hit — skip AST parsing on clean restarts
    $diskCache = Load-ToolSchemaCache -Fingerprint $fingerprint
    if ($diskCache -and $diskCache.schemas) {
        $script:ToolCache = @($diskCache.schemas)
        $script:ToolCacheMtime = @{}
        foreach ($s in $scripts) { $script:ToolCacheMtime[$s.BaseName] = $s.LastWriteTime }
        $script:ToolSchemaJsonCache = @{}
        if ($diskCache.schemaJson) {
            $diskCache.schemaJson.PSObject.Properties | ForEach-Object {
                $script:ToolSchemaJsonCache[$_.Name] = $_.Value
            }
        }
        Write-MatrixLog -Message "Tool disk cache hit ($($script:ToolCache.Count) tools)"
        return $script:ToolCache
    }

    Write-MatrixLog -Message "Rebuilding tool cache ($($scripts.Count) scripts)"
    $script:ToolDiscoveryErrors = @()

    $discovered = foreach ($script in $scripts) {
        try {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName, [ref]$tokens, [ref]$errors
            )
            if ($null -eq $ast) { continue }

            $description = "Tool: $($script.BaseName)"
            $help = $ast.GetHelpContent()
            if ($help -and $help.Synopsis) { $description = $help.Synopsis.Trim() }

            $properties = [ordered]@{}
            $required   = @()

            if ($ast.ParamBlock) {
                foreach ($p in $ast.ParamBlock.Parameters) {
                    $pName = $p.Name.VariablePath.UserPath

                    $pType = "string"
                    if ($p.StaticType) {
                        $t = $p.StaticType.Name.ToLower()
                        if ($t -match "int|long|float|double|decimal") { $pType = "number" }
                        elseif ($t -match "bool|switch")                { $pType = "boolean" }
                    }

                    $pDesc = "Parameter $pName"
                    if ($help -and $help.Parameters -and $help.Parameters[$pName.ToUpper()]) {
                        $pDesc = $help.Parameters[$pName.ToUpper()].Trim()
                    }

                    $properties[$pName] = @{ type = $pType; description = $pDesc }

                    foreach ($attr in @($p.Attributes)) {
                        if ($attr -isnot [System.Management.Automation.Language.AttributeAst]) { continue }
                        if ($attr.TypeName.Name -ne 'Parameter') { continue }
                        $mandatoryArg = $attr.NamedArguments |
                                        Where-Object { $_.ArgumentName -eq 'Mandatory' }
                        if ($mandatoryArg) {
                            if ($mandatoryArg.ExpressionOmitted -or
                                $mandatoryArg.Argument.Extent.Text -match '^\$?true$') {
                                $required += $pName
                            }
                        }
                    }
                }
            }

            $params = @{ type = "object"; properties = $properties }
            if ($required.Count -gt 0) { $params.required = [array]$required }

            @{
                type     = "function"
                function = @{
                    name        = $script.BaseName
                    description = $description
                    parameters  = $params
                }
            }
        } catch {
            $errMsg = [string]$_
            Write-MatrixLog -Level "ERROR" -Message "Tool discovery error ($($script.Name)): $errMsg"
            $script:ToolDiscoveryErrors += @{ Name = $script.BaseName; Error = $errMsg }
        }
    }

    $valid = @($discovered) | Where-Object {
        $_ -is [hashtable] -and $_.function -and $_.function.name
    }

    $seen   = @{}
    $unique = @()
    foreach ($t in $valid) {
        if (-not $seen[$t.function.name]) {
            $unique += $t
            $seen[$t.function.name] = $true
        }
    }

    $script:ToolCache = [array]$unique
    $script:ToolCacheMtime = @{}
    foreach ($s in $scripts) { $script:ToolCacheMtime[$s.BaseName] = $s.LastWriteTime }

    $script:ToolSchemaJsonCache = @{}
    foreach ($t in $unique) {
        $script:ToolSchemaJsonCache[$t.function.name] = ($t | ConvertTo-Json -Depth 10 -Compress)
    }

    Save-ToolSchemaCache -Fingerprint $fingerprint -Schemas $unique -SchemaJson $script:ToolSchemaJsonCache

    Write-MatrixLog -Message "Tools ready: $($unique.Count) ($(($unique | ForEach-Object { $_.function.name } | Sort-Object) -join ', '))"
    return $script:ToolCache
}

function Get-MatrixToolCatalog {
    if (-not $script:ToolCache) { return "" }
    return ($script:ToolCache |
        Sort-Object { $_.function.name } |
        ForEach-Object { "$($_.function.name): $($_.function.description)" }
    ) -join "`n"
}

function Select-MatrixTools {
    param(
        [string]   $UserMessage    = "",
        [int]      $MaxTokenBudget = 6000,
        [int]      $MaxCount       = 25,
        [string[]] $CoreTools      = @()
    )

    if (-not $script:ToolCache -or $script:ToolCache.Count -eq 0) { return @() }

    $charBudget = [math]::Floor($MaxTokenBudget * 3.5)

    $words = @()
    if (-not [string]::IsNullOrWhiteSpace($UserMessage)) {
        $words = ($UserMessage -split '\W+') |
                 Where-Object { $_.Length -gt 2 } |
                 ForEach-Object { $_.ToLower() } |
                 Select-Object -Unique
    }

    $scored = foreach ($tool in $script:ToolCache) {
        $name    = $tool.function.name
        $descLow = $tool.function.description.ToLower()

        $nameParts = @()
        foreach ($seg in ($name -split '-')) {
            [regex]::Matches($seg, '[A-Z][a-z]*|[0-9]+') | ForEach-Object { $nameParts += $_.Value.ToLower() }
        }
        $nameLow = $name.ToLower()

        $score = 0
        foreach ($w in $words) {
            $esc = [regex]::Escape($w)
            if ($w -in $nameParts)                      { $score += 3 }
            elseif ($nameLow -match $esc)               { $score += 2 }
            elseif ($descLow -match "\b$esc\b")         { $score += 1 }
        }
        [PSCustomObject]@{ Tool = $tool; Name = $name; Score = $score }
    }

    # Use List[object] to accept both hashtables (live cache) and PSCustomObjects (disk cache)
    $selected    = [System.Collections.Generic.List[object]]::new()
    $usedChars   = 0
    $selectedSet = @{}

    foreach ($coreName in $CoreTools) {
        if ($selectedSet[$coreName]) { continue }
        $entry = $script:ToolCache | Where-Object { $_.function.name -eq $coreName } | Select-Object -First 1
        if (-not $entry) { continue }
        $jsonLen = if ($script:ToolSchemaJsonCache[$coreName]) { $script:ToolSchemaJsonCache[$coreName].Length } else { 500 }
        $selected.Add($entry)
        $usedChars += $jsonLen
        $selectedSet[$coreName] = $true
    }

    foreach ($item in ($scored | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Name'; Ascending = $true })) {
        if ($selected.Count -ge $MaxCount) { break }
        if ($selectedSet[$item.Name]) { continue }
        $jsonLen = if ($script:ToolSchemaJsonCache[$item.Name]) { $script:ToolSchemaJsonCache[$item.Name].Length } else { 500 }
        if ($usedChars + $jsonLen -gt $charBudget) { continue }
        $selected.Add($item.Tool)
        $usedChars += $jsonLen
        $selectedSet[$item.Name] = $true
    }

    return [array]$selected
}

function Invoke-MatrixTool {
    param(
        [string]$ToolName,
        [hashtable]$InputArgs
    )

    $toolPath = Join-Path $global:MatrixRoot "tools" "$ToolName.ps1"
    if (-not (Test-Path $toolPath)) {
        Write-MatrixLog -Level "WARN" -Message "Tool not found: $toolPath"
        return @{ error = "tool '$ToolName' not found" } | ConvertTo-Json -Compress
    }

    try {
        $output = if ($InputArgs -and $InputArgs.Count -gt 0) {
            & $toolPath @InputArgs
        } else {
            & $toolPath
        }

        if ($output -is [hashtable] -or
            $output -is [System.Management.Automation.PSCustomObject] -or
            $output -is [array]) {
            return $output | ConvertTo-Json -Depth 5 -Compress
        }
        return [string]$output
    } catch {
        Write-MatrixLog -Level "ERROR" -Message "Tool error ($ToolName): $_"
        return @{ error = "Error executing '$ToolName': $_" } | ConvertTo-Json -Compress
    }
}

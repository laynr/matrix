# Discovers tools from the tools/ directory and builds Ollama-compatible schemas.
# Each tool is a .ps1 file. The function name = file basename.
# Parameters and .SYNOPSIS are parsed via PowerShell AST.
# Schemas are cached in memory and only rebuilt when a tool file changes.

$script:ToolCache      = $null
$script:ToolCacheMtime = @{}   # BaseName → LastWriteTime

function Get-MatrixTools {
    $root     = if ($global:MatrixRoot) { $global:MatrixRoot } else { Split-Path -Parent $PSScriptRoot }
    $toolsDir = Join-Path $root "tools"

    Write-MatrixLog -Message "Scanning tools in: $toolsDir"

    if (-not (Test-Path $toolsDir)) {
        Write-MatrixLog -Level "WARN" -Message "tools/ directory not found at $toolsDir"
        return @()
    }

    $scripts = @(Get-ChildItem -Path $toolsDir -Filter "*.ps1")

    # Cache hit: same file count AND no file has a newer mtime
    $dirty = ($scripts.Count -ne $script:ToolCacheMtime.Count) -or
             ($scripts | Where-Object { $script:ToolCacheMtime[$_.BaseName] -ne $_.LastWriteTime })

    if (-not $dirty -and $script:ToolCache) {
        Write-MatrixLog -Message "Tool cache hit ($($script:ToolCache.Count) tools)"
        return $script:ToolCache
    }

    Write-MatrixLog -Message "Rebuilding tool cache ($($scripts.Count) scripts)"

    $discovered = foreach ($script in $scripts) {
        try {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName, [ref]$tokens, [ref]$errors
            )
            if ($null -eq $ast) { continue }

            # Description from .SYNOPSIS
            $description = "Tool: $($script.BaseName)"
            $help = $ast.GetHelpContent()
            if ($help -and $help.Synopsis) { $description = $help.Synopsis.Trim() }

            # Parameters
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
                    if ($help -and $help.Parameters -and $help.Parameters[$pName]) {
                        $pDesc = $help.Parameters[$pName].Trim()
                    }

                    $properties[$pName] = @{ type = $pType; description = $pDesc }

                    foreach ($attr in @($p.Attributes)) {
                        # Must be an AttributeAst (not a type constraint like [string])
                        if ($attr -isnot [System.Management.Automation.Language.AttributeAst]) { continue }
                        if ($attr.TypeName.Name -ne 'Parameter') { continue }
                        # Handle both [Parameter(Mandatory)] and [Parameter(Mandatory = $true)]
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
            Write-MatrixLog -Level "ERROR" -Message "Tool discovery error ($($script.Name)): $_"
        }
    }

    $valid = @($discovered) | Where-Object {
        $_ -is [hashtable] -and $_.function -and $_.function.name
    }

    # Deduplicate
    $seen   = @{}
    $unique = @()
    foreach ($t in $valid) {
        if (-not $seen[$t.function.name]) {
            $unique += $t
            $seen[$t.function.name] = $true
        }
    }

    # Update cache
    $script:ToolCache = [array]$unique
    $script:ToolCacheMtime = @{}
    foreach ($s in $scripts) { $script:ToolCacheMtime[$s.BaseName] = $s.LastWriteTime }

    Write-MatrixLog -Message "Tools ready: $($unique.Count) ($(($unique | ForEach-Object { $_.function.name } | Sort-Object) -join ', '))"
    return $script:ToolCache
}

function Invoke-MatrixTool {
    param(
        [string]$ToolName,
        [hashtable]$InputArgs
    )

    $toolPath = Join-Path $global:MatrixRoot "tools" "$ToolName.ps1"
    if (-not (Test-Path $toolPath)) {
        Write-MatrixLog -Level "WARN" -Message "Tool not found: $toolPath"
        return "Error: tool '$ToolName' not found."
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
        return "Error executing '$ToolName': $_"
    }
}

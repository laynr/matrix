# Discovers tools from the tools/ directory and builds Ollama-compatible schemas.
# Each tool is a .ps1 file. The function name = file basename.
# Parameters and .SYNOPSIS are parsed via PowerShell AST.

function Get-MatrixTools {
    $root      = if ($global:MatrixRoot) { $global:MatrixRoot } else { Split-Path -Parent $PSScriptRoot }
    $toolsDir  = Join-Path $root "tools"  # forward-slash safe; pwsh handles both separators

    Write-MatrixLog -Message "Scanning tools in: $toolsDir"

    if (-not (Test-Path $toolsDir)) {
        Write-MatrixLog -Level "WARN" -Message "tools/ directory not found at $toolsDir"
        return @()
    }

    $scripts = Get-ChildItem -Path $toolsDir -Filter "*.ps1"
    Write-MatrixLog -Message "Found $($scripts.Count) tool script(s)"

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
                        if ($t -match "int|double|long|float") { $pType = "number" }
                        elseif ($t -match "bool|switch")        { $pType = "boolean" }
                    }

                    # Grab per-parameter description from .PARAMETER help block
                    $pDesc = "Parameter $pName"
                    if ($help -and $help.Parameters -and $help.Parameters[$pName]) {
                        $pDesc = $help.Parameters[$pName].Trim()
                    }

                    $properties[$pName] = @{ type = $pType; description = $pDesc }

                    foreach ($attr in @($p.Attributes)) {
                        if ($attr.TypeName.Name -match "Parameter" -and
                            $attr.Extent.Text -match 'Mandatory\s*=\s*\$true') {
                            $required += $pName
                        }
                    }
                }
            }

            # Ollama / OpenAI function-calling schema
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

    Write-MatrixLog -Message "Tools ready: $($unique.Count) ($($unique | ForEach-Object { $_.function.name }) -join ', ')"
    return [array]$unique
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

        if ($output -is [hashtable] -or $output -is [System.Management.Automation.PSCustomObject] -or $output -is [array]) {
            return $output | ConvertTo-Json -Depth 5 -Compress
        }
        return [string]$output
    } catch {
        Write-MatrixLog -Level "ERROR" -Message "Tool error ($ToolName): $_"
        return "Error executing '$ToolName': $_"
    }
}

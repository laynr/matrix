

function Get-MatrixTools {
    $root = if ($global:MatrixRoot) { $global:MatrixRoot } else { Split-Path -Parent $PSScriptRoot }
    $pluginsDir = Join-Path $root "plugins"
    Write-MatrixLog -Message "Scanning plugins in: $pluginsDir"
    if (-not (Test-Path $pluginsDir)) { 
        Write-MatrixLog -Level "WARN" -Message "Plugins directory not found!"
        return @() 
    }
    
    $scripts = Get-ChildItem -Path $pluginsDir -Filter "*.ps1"
    Write-MatrixLog -Message "Found $($scripts.Count) potential plugin scripts."
    
    $discovered = foreach ($script in $scripts) {
        try {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
            
            if ($null -eq $ast) { continue }
            
            $synopsis = "Plugin tool: $($script.BaseName)"
            $parsedHelp = $ast.GetHelpContent()
            if ($null -ne $parsedHelp -and $null -ne $parsedHelp.Synopsis) { 
                $synopsis = $parsedHelp.Synopsis.Trim()
            }
            
            $paramBlock = $ast.ParamBlock
            $properties = @{}
            $required = @()
            
            if ($paramBlock) {
                foreach ($p in $paramBlock.Parameters) {
                    $pName = $p.Name.VariablePath.UserPath
                    $pType = "string" 
                    if ($p.StaticType) {
                        $typeName = $p.StaticType.Name.ToLower()
                        if ($typeName -match "int|double|long") { $pType = "number" }
                        elseif ($typeName -match "bool") { $pType = "boolean" }
                    }
                    
                    $properties[$pName] = @{
                        type = $pType
                        description = "Parameter $pName"
                    }
                    
                    if ($p.Attributes) {
                        foreach ($attr in $p.Attributes) {
                            if ($attr.TypeName.Name -match "Parameter") {
                                if ($attr.Extent.Text -match 'Mandatory\s*=\s*\$true') {
                                    $required += $pName
                                }
                            }
                        }
                    }
                }
            }
            
            $schema = @{
                name = $script.BaseName
                description = $synopsis
                input_schema = @{
                    type = "object"
                    properties = if ($properties.Count -gt 0) { $properties } else { @{} }
                }
            }
            
            if ($required.Count -gt 0) {
                $schema.input_schema.required = [array]$required
            }
            
            # Return the schema to the foreach pipeline
            $schema
        } catch {
            Write-MatrixLog -Level "ERROR" -Message "Discovery Error ($($script.Name)): $_"
        }
    }
    
    # Return exactly one array of unique valid hashtables
    if ($null -eq $discovered) { 
        Write-MatrixLog -Message "No tools discovered."
        return @() 
    }
    $validTools = @($discovered) | Where-Object { $null -ne $_ -and $_ -is [hashtable] -and [string]::IsNullOrWhiteSpace($_.name) -eq $false }
    
    $uniqueTools = @()
    $seenNames = @{}
    foreach ($t in $validTools) {
        if (-not $seenNames.ContainsKey($t.name)) {
            $uniqueTools += $t
            $seenNames[$t.name] = $true
        }
    }
    
    Write-MatrixLog -Message "Total unique tools discovered: $($uniqueTools.Count)"
    return [array]$uniqueTools
}

function Invoke-MatrixTool {
    param(
        [string]$ToolName,
        [hashtable]$InputArgs
    )
    
    $pluginPath = Join-Path $global:MatrixRoot "plugins\$ToolName.ps1"
    if (Test-Path $pluginPath) {
        try {
            if ($InputArgs -and $InputArgs.Keys.Count -gt 0) {
                $jobOutput = & $pluginPath @InputArgs
            } else {
                $jobOutput = & $pluginPath
            }
            
            if ($jobOutput -is [hashtable] -or $jobOutput -is [PSCustomObject] -or $jobOutput -is [array]) {
                $strOut = $jobOutput | ConvertTo-Json -Depth 5 -Compress
                Write-MatrixLog -Message "Tool Output ($ToolName): $strOut"
                return $strOut
            } else {
                return [string]$jobOutput
            }
        } catch {
            Write-MatrixLog -Level "ERROR" -Message "Tool Error ($ToolName): $_"
            return "Error executing tool: $_"
        }
    }
    
    Write-MatrixLog -Level "WARN" -Message "Tool Not Found: $ToolName"
    return "Tool $ToolName not found."
}

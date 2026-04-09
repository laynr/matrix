You are adding a new tool to the **Matrix agent framework**.

User request: **$ARGUMENTS**

---

## Step 1 — Identify the target variant

Ask (or infer from context) which Matrix variant to add the tool to:
- **matrix.ps1** (PowerShell) at `/Users/layne/projects/matrix.ps1/tools/`
- **matrix.py** (Python) at `/Users/layne/projects/matrix/tools/`

If ambiguous, default to **matrix.ps1**.

---

## Step 2 — Design the tool interface

Before writing code, confirm:
- **Tool name**: PascalCase verb-noun for PS1 (`Get-Weather`), snake_case for Python (`get_weather`)
- **Parameters**: name, type, required/optional, description
- **Output fields**: what JSON keys are returned on success
- **Error cases**: what inputs should return `{ error: "..." }`
- **Platform differences**: anything OS-specific?
- **External dependencies**: network calls? system commands? timeout needed?

---

## Step 3 — Create the tool

### PowerShell (matrix.ps1)

Write to `/Users/layne/projects/matrix.ps1/tools/<ToolName>.ps1`:

```powershell
<#
.SYNOPSIS
One sentence describing what this tool does. Be specific and concise.

.PARAMETER ParamName
What this parameter means. Required for EVERY Mandatory param.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ParamName,

    [int]$OptionalParam = 10
)

try {
    # Use $IsWindows / $IsMacOS / $IsLinux for OS-specific branches
    # Add -TimeoutSec 15 to all Invoke-RestMethod / Invoke-WebRequest calls

    return @{
        Result  = "value"
        # Include all meaningful output fields
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
```

**Non-negotiable rules:**
- `[CmdletBinding()]` — required for schema discovery
- `.PARAMETER` doc for every `[Parameter(Mandatory)]` — tested by CI
- All output is compact JSON — never `Write-Host`
- All logic inside `try/catch` returning `@{ error = "..." }`
- `-TimeoutSec 15` on all external calls
- `-Depth 3 -Compress` on all `ConvertTo-Json`

### Python (matrix.py)

Write to `/Users/layne/projects/matrix/tools/<tool_name>.py`:

```python
"""One sentence: what this tool does."""

def run(param_name: str, optional_param: int = 10) -> dict:
    """
    Args:
        param_name: What this parameter means.
        optional_param: Optional description.
    Returns JSON-serializable dict.
    """
    try:
        # implementation
        return {"result": "value"}
    except Exception as e:
        return {"error": str(e)}
```

---

## Step 4 — Write tests (PowerShell only)

Add a test block to `/Users/layne/projects/matrix.ps1/tests/Test-Tools.ps1`:

```powershell
# ── <ToolName> ────────────────────────────────────────────────────────────────
Start-Suite "<ToolName>"
Test-ToolSchema "<ToolName>"
$out = Invoke-Tool "<ToolName>" @{ ParamName = "valid-value" }
Assert-ValidJson  "returns valid JSON"         $out
Assert-NoError    "no error on valid input"    $out
$obj = Get-ToolOutput $out
Assert-HasKey     "has Result field"   $obj   "Result"

# Error case
$out2 = Invoke-Tool "<ToolName>" @{ ParamName = "invalid" }
$obj2 = Get-ToolOutput $out2
Assert-True       "bad input returns error"    ($null -ne $obj2.error)
```

Wrap network-dependent tests in `if (-not $SchemaOnly) { ... }`.

---

## Step 5 — Run tests

```powershell
pwsh /Users/layne/projects/matrix.ps1/tests/Run-Tests.ps1 -SchemaOnly
```

All tests must pass before moving on. Fix any failures.

---

## Step 6 — Report results

Summarize:
- Tool path created
- Parameters (name → type, required?)
- Output fields
- Error handling behavior
- Tests added
- How to hot-load: type `reload` inside the Matrix REPL

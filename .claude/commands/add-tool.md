You are adding a new tool to the **Matrix agent framework**.

User request: **$ARGUMENTS**

---

## Step 1 — Design the tool interface

Before writing code, confirm:
- **Tool name**: PascalCase verb-noun (`Get-Weather`, `Invoke-Math`, `Convert-Units`)
- **Parameters**: name, type, required/optional, description
- **Output fields**: what JSON keys are returned on success
- **Error cases**: what inputs should return `{ error: "..." }`
- **Platform differences**: anything OS-specific? Use `$IsWindows`/`$IsMacOS`/`$IsLinux`
- **External dependencies**: network calls need `-TimeoutSec 15` and `try/catch`

---

## Step 2 — Create the tool

Write to `/Users/layne/projects/matrix/tools/<ToolName>.ps1`:

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

**Non-negotiable rules (all enforced by CI):**
- `[CmdletBinding()]` — required for AST schema discovery
- `.PARAMETER` doc for every `[Parameter(Mandatory)]` — tested by `Test-ToolSchema`
- All output is compact JSON — never `Write-Host` (output goes to the model)
- All logic inside `try/catch` returning `@{ error = "..." }`
- `-TimeoutSec 15` on all external calls (no hanging agent)
- `-Depth 3 -Compress` on all `ConvertTo-Json`
- Return `@{ error = "..." }` on bad input — do not throw

**Security checklist:**
- [ ] Validate path args with `Test-Path` or resolve to prevent traversal
- [ ] Never `Invoke-Expression` on user input — use `& $exe @args` array form
- [ ] Do not log secrets/tokens to err.log

---

## Step 3 — Write tests

Add a test block to `/Users/layne/projects/matrix/tests/Test-Tools.ps1`:

```powershell
# ── <ToolName> ────────────────────────────────────────────────────────────────
Start-Suite "<ToolName>"
Test-ToolSchema "<ToolName>"
if (-not $SchemaOnly) {
    $out = Invoke-Tool "<ToolName>" @{ ParamName = "valid-value" }
    Assert-ValidJson  "returns valid JSON"         $out
    Assert-NoError    "no error on valid input"    $out
    $obj = Get-ToolOutput $out
    Assert-HasKey     "has Result field"           $obj "Result"

    # Error case
    $out2 = Invoke-Tool "<ToolName>" @{ ParamName = "invalid" }
    $obj2 = Get-ToolOutput $out2
    Assert-True       "bad input returns error"    ($null -ne $obj2.error)
}
```

Wrap ALL live/network calls in `if (-not $SchemaOnly) { ... }`.

---

## Step 4 — Run tests

```powershell
pwsh /Users/layne/projects/matrix/tests/Run-Tests.ps1 -SchemaOnly
```

All tests must pass before moving on. Fix any failures.

---

## Step 5 — Report results

Summarize:
- Tool file created at `tools/<ToolName>.ps1`
- Parameters (name → type, required?)
- Output fields on success
- Error handling behavior
- Tests added to `Test-Tools.ps1`
- How to hot-load: type `reload` inside the Matrix REPL

**The new tool is auto-discovered on the next message — no restart needed.**
Type `tools` in the REPL to confirm it appears in the list.

# Matrix — Claude Code Development Guide

Cross-platform AI agent in PowerShell 7. Runs Ollama + gemma4 on Mac, Linux, and Windows. Repo: `laynr/matrix`.

---

## Core principles — in priority order

1. **User experience first** — streaming output, parallel tools, zero-friction install, instant feedback
2. **Code quality** — cross-platform, tests before every commit, no half-measures
3. **Security** — validate inputs, timeout all external calls, never execute untrusted strings unescaped

---

## Architecture

```
Matrix.ps1              ← Entry point. -CLI forces terminal; default is WPF GUI on Windows.
lib/
  Config.ps1            ← Load/save config.json; SystemPrompt default
  Network.ps1           ← Invoke-MatrixStreamingChat (CLI), Invoke-MatrixChat (GUI),
                           Invoke-MatrixToolchain (parallel runspaces), Limit-ToolResult
  Context.ps1           ← Message history, Prune-Context (summarize → smart prune),
                           Invoke-ContextSummary
  ToolManager.ps1       ← AST schema discovery, mtime cache, Invoke-MatrixTool
  CLI.ps1               ← Show-MatrixCLI, Process-OllamaMessage (streaming loop)
  Logger.ps1            ← Write-MatrixLog → err.log
  GUI.ps1               ← WPF chat window (Windows only)
tools/                  ← Drop a .ps1 here — auto-discovered on next message or reload
tests/
  Test-Framework.ps1    ← Assert-*, Invoke-Tool, Test-ToolSchema
  Test-Tools.ps1        ← Unit tests: every tool (schema + live calls)
  Test-MultiTool.ps1    ← Integration: parallel dispatch, type coercion, cache
  Run-Tests.ps1         ← Master runner: -SchemaOnly (CI), -Suite Tools|MultiTool
.github/workflows/
  publish.yml           ← Test on 3 OS → zip release → publish to laynr/matrix releases
```

**Key design decisions (do not revert without discussion):**
- System prompt injected on every API call, never stored in `$global:MatrixMessages`
- Streaming via `System.Net.Http.HttpClient` NDJSON — tokens print live in CLI path
- Parallel tool dispatch via `[PowerShell]::Create()` runspaces
- Context budget: summarize at 75k tokens (Phase A), smart prune fallback (Phase B)
- Tool results truncated at 8,000 chars via `Limit-ToolResult`
- GUI uses blocking `Invoke-MatrixChat`; CLI uses `Invoke-MatrixStreamingChat`

---

## Development workflow

### Before every commit — REQUIRED

```powershell
pwsh tests/Run-Tests.ps1 -SchemaOnly
```

Schema validation + unit tests, no network. All must pass. The pre-commit hook enforces this automatically.

Full suite (requires Ollama):
```powershell
pwsh tests/Run-Tests.ps1
```

### After every commit

Check whether any new pattern, decision, or preference should be saved:
- Memory files: `~/.claude/projects/-Users-layne-projects-matrix/memory/`
- This file (`CLAUDE.md`) if the architecture or workflow changed

### Adding a new tool

Use `/add-tool <name: description>` — scaffolds the file, writes tests, runs the suite.

Or manually: create `tools/ToolName.ps1`, add a `Start-Suite` block to `tests/Test-Tools.ps1`, run tests.

---

## Tool authoring rules (all enforced by tests)

| Rule | Why |
|------|-----|
| `[CmdletBinding()]` on every tool | Required for AST Mandatory detection |
| One-sentence `.SYNOPSIS` | Becomes the model's tool description |
| `.PARAMETER` doc for every `Mandatory` param | Enforced by `Test-ToolSchema` |
| All logic in `try/catch` returning `@{ error = "..." }` | Agent handles errors gracefully |
| Return compact JSON — never `Write-Host` | Output goes to the model |
| `-TimeoutSec 15` on all external calls | No hanging agent |
| `$IsWindows`/`$IsMacOS`/`$IsLinux` for OS branches | Cross-platform required |
| `-Depth 3 -Compress` on all `ConvertTo-Json` | Consistent, compact context |

---

## Quick reference

```powershell
pwsh tests/Run-Tests.ps1 -SchemaOnly        # before every commit
pwsh tests/Run-Tests.ps1 -Suite Tools       # single suite
pwsh Matrix.ps1 -CLI                        # run the agent
tail -f err.log                             # live log
# Inside the REPL:
reload                                      # hot-reload tools after changes
```

---

## Security checklist for new tools

- [ ] Validate path args with `Test-Path` or resolve to prevent traversal
- [ ] Wrap all external calls in `try/catch` with `-TimeoutSec`
- [ ] Never `Invoke-Expression` on user input — use `& $exe @args` array form
- [ ] Return `@{ error = "..." }` on bad input; do not throw
- [ ] Do not log secrets/tokens to `err.log`

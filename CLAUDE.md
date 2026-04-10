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
  Config.ps1            ← Load/save config.json; defaults for all tuneable values
  Network.ps1           ← Invoke-MatrixStreamingChat (CLI), Invoke-MatrixChat (GUI),
                           Invoke-MatrixToolchain (RunspacePool), Limit-ToolResult,
                           Get-MatrixRunspacePool, Get-DynamicNumCtx
  Context.ps1           ← Message history, Prune-Context (summarize → smart prune),
                           Invoke-ContextSummary, Get-ContextTokenCount
  ToolManager.ps1       ← AST schema discovery, mtime cache, Reset-ToolCache,
                           Invoke-MatrixTool
  CLI.ps1               ← Show-MatrixCLI, Process-OllamaMessage (streaming loop),
                           Show-MatrixError, Show-ContextStatus, Show-MatrixHelp,
                           Show-MatrixToolsList
  Logger.ps1            ← Write-MatrixLog → err.log (cross-platform mutex)
  GUI.ps1               ← WPF chat window (Windows only)
tools/                  ← Drop a .ps1 here — auto-discovered on next message or reload
tests/
  Test-Framework.ps1    ← Assert-*, Invoke-Tool, Test-ToolSchema
  Test-Tools.ps1        ← Unit tests: every tool (schema + live calls)
  Test-MultiTool.ps1    ← Integration: parallel dispatch, type coercion, cache
  Test-LiveAgent.ps1    ← E2E: streaming pipeline + per-tool deterministic tests
  Run-Tests.ps1         ← Master runner: -SchemaOnly (CI), -Suite Tools|MultiTool|LiveAgent
.github/workflows/
  publish.yml           ← zip release → publish to laynr/matrix releases (push to main)
```

**Key design decisions (do not revert without discussion):**
- System prompt injected on every API call, never stored in `$global:MatrixMessages`
- Streaming via `System.Net.Http.HttpClient` NDJSON — tokens print live in CLI path
- Parallel tool dispatch via `RunspacePool` (1–8 warm runspaces, shared across turns)
- Context budget: summarize at SummarizeAt tokens (Phase A), smart prune fallback (Phase B)
- Tool results truncated at 8,000 chars via `Limit-ToolResult`
- GUI uses blocking `Invoke-MatrixChat`; CLI uses `Invoke-MatrixStreamingChat`
- Logger mutex uses `Global\MatrixLogMutex` on Windows, bare name on macOS/Linux
- Config defaults centralised in `Load-Config` — all limits (MaxTokens, MaxDepth, etc.) come from there

---

## Configuration (`config.json`)

All fields are optional — defaults apply when absent.

| Key | Default | Description |
|-----|---------|-------------|
| `Model` | `gemma4:latest` | Ollama model name |
| `Endpoint` | `http://localhost:11434/api/chat` | Ollama API URL |
| `SystemPrompt` | (built-in) | Agent personality, injected fresh on every call |
| `NumCtx` | `0` | Context window size. 0 = auto-calculate from message+tool sizes |
| `MaxTokens` | `100000` | Token budget ceiling for context pruning display |
| `SummarizeAt` | `75000` | Tokens threshold that triggers Phase A summarisation |
| `MaxDepth` | `10` | Max tool-call recursion depth per user turn |

---

## Development workflow

### Before every commit — REQUIRED

```powershell
pwsh tests/Run-Tests.ps1 -SchemaOnly
```

Schema validation + unit tests, no network. All must pass. The pre-commit hook enforces this automatically.

Full suite (requires Ollama running):
```powershell
pwsh tests/Run-Tests.ps1
```

This includes `Test-LiveAgent.ps1` — two suites:
- **E2E**: sends "do something that uses all your tools" through the real streaming pipeline
- **Per-tool**: one test per discovered tool, exposing only that tool to the model to force deterministic invocation

Run just the live tests:
```powershell
pwsh tests/Run-Tests.ps1 -Suite LiveAgent
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

## CLI — REPL commands

| Command | Action |
|---------|--------|
| `exit` / `quit` | Exit Matrix |
| `reload` | Rescan `tools/` and register new tools |
| `clear` | Reset conversation history (keeps tools loaded) |
| `tools` | List all loaded tools with descriptions |
| `help` | Show all REPL commands |

---

## Quick reference

```powershell
pwsh tests/Run-Tests.ps1 -SchemaOnly        # before every commit
pwsh tests/Run-Tests.ps1 -Suite Tools       # single suite
pwsh tests/Run-Tests.ps1 -Suite LiveAgent   # live tests only (needs Ollama)
pwsh Matrix.ps1 -CLI                        # run the agent
tail -f err.log                             # live log
# Inside the REPL:
reload          # hot-reload tools after changes
clear           # reset conversation context
tools           # list loaded tools
help            # show all commands
```

---

## Security checklist for new tools

- [ ] Validate path args with `Test-Path` or resolve to prevent traversal
- [ ] Wrap all external calls in `try/catch` with `-TimeoutSec`
- [ ] Never `Invoke-Expression` on user input — use `& $exe @args` array form
- [ ] Return `@{ error = "..." }` on bad input; do not throw
- [ ] Do not log secrets/tokens to `err.log`

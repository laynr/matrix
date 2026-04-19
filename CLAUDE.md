# Matrix — Claude Code Development Guide

Cross-platform AI agent in PowerShell 7. Runs Ollama + qwen3 on Mac, Linux, and Windows. Repo: `laynr/matrix`.

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
  Config.ps1            ← Load-Config, Save-Config, Select-MatrixModel (RAM-aware tier selection),
                           Get-SystemRamGB, Get-OllamaModels; defaults for all tuneable values
  Network.ps1           ← Invoke-MatrixStreamingChat (CLI), Invoke-MatrixChat (GUI),
                           Invoke-MatrixToolchain (RunspacePool), Limit-ToolResult,
                           Get-MatrixRunspacePool (pre-loads Logger/ToolManager via InitialSessionState),
                           Get-DynamicNumCtx
  Context.ps1           ← Message history, Prune-Context (summarize → smart prune),
                           Invoke-ContextSummary, Get-ContextTokenCount
  ToolManager.ps1       ← AST schema discovery, two-tier cache (memory + disk at tools/.schema-cache.json),
                           Get-MatrixTools, Select-MatrixTools, Reset-ToolCache, Invoke-MatrixTool
  CLI.ps1               ← Show-MatrixCLI, Process-OllamaMessage (streaming loop),
                           Show-MatrixError, Show-ContextStatus, Show-MatrixHelp,
                           Show-MatrixToolsList
  Logger.ps1            ← Write-MatrixLog → err.log (cross-platform mutex)
  GUI.ps1               ← WPF chat window (Windows only)
tools/                  ← Drop a .ps1 here — auto-discovered on next message or reload
install/
  install.sh            ← Mac/Linux: sh bootstrap → installs pwsh
  install.ps1           ← Windows: PS5 bootstrap → installs pwsh 7
  install.pwsh.ps1      ← Shared pwsh 7 setup (Ollama, model, download release, launcher)
  uninstall.pwsh.ps1    ← Removes ~/.matrix and the launcher
tests/
  Test-Framework.ps1    ← Assert-*, Invoke-Tool, Test-ToolSchema
  Test-Config.ps1       ← Unit tests: Load-Config, Save-Config, Select-MatrixModel, RAM/Ollama helpers
  Test-Tools.ps1        ← Unit tests: every tool (schema + live calls)
  Test-MultiTool.ps1    ← Integration: parallel dispatch, type coercion, cache
  Test-LiveAgent.ps1    ← E2E: streaming pipeline + per-tool deterministic tests
  Run-Tests.ps1         ← Master runner: -SchemaOnly (CI), -Suite Config|Tools|MultiTool|LiveAgent
.github/workflows/
  publish.yml           ← zip release → publish to laynr/matrix releases (push to main)
```

**Key design decisions (do not revert without discussion):**
- System prompt injected on every API call, never stored in `$global:MatrixMessages`
- Streaming via `System.Net.Http.HttpClient` NDJSON — tokens print live in CLI path
- Parallel tool dispatch via `RunspacePool` (1–8 warm runspaces, shared across turns)
- RunspacePool pre-loads `Logger.ps1` and `ToolManager.ps1` via `InitialSessionState` at pool-open time — eliminates per-call dot-source overhead
- Tool schema cache is two-tier: memory (mtime fingerprint) → disk (`tools/.schema-cache.json`); cold starts skip AST parsing when files unchanged
- Model auto-selected by `Select-MatrixModel`: walks `ModelTiers` sorted by RAM, picks best tier that fits available RAM **and** is installed in Ollama; skips auto-select when `Model` is explicitly set in `config.json`
- Context budget: summarize at SummarizeAt tokens (Phase A), smart prune fallback (Phase B)
- Tool results truncated at 8,000 chars via `Limit-ToolResult`
- GUI uses blocking `Invoke-MatrixChat`; CLI uses `Invoke-MatrixStreamingChat`
- Logger mutex uses `Global\MatrixLogMutex` on Windows, bare name on macOS/Linux
- Config defaults centralised in `Load-Config` — all limits (MaxTokens, MaxDepth, etc.) come from there
- `Invoke-CoerceArg` coerces JSON strings `"true"`/`"false"` to `[bool]` — model often sends string for bool params
- CLI uses `Select-MatrixTools` (≤25 tools, 6000-token budget) + full catalog per turn — never dumps all schemas at once

---

## Configuration (`config.json`)

All fields are optional — defaults apply when absent.

| Key | Default | Description |
|-----|---------|-------------|
| `Model` | `qwen3:4b` | Ollama model name. Auto-selected from `ModelTiers` based on RAM when not explicitly set in config.json |
| `ModelTiers` | 4-tier pyramid (qwen3:8b/20GB, qwen2.5:7b/12GB, qwen3:4b/6GB, llama3.2:3b/0GB) | RAM-aware tier list; each entry is `@{ MinRamGB; Model }`. `Select-MatrixModel` picks highest fitting installed tier |
| `Endpoint` | `http://localhost:11434/api/chat` | Ollama API URL |
| `SystemPrompt` | (built-in) | Agent personality, injected fresh on every call |
| `NumCtx` | `0` | Context window size. 0 = auto-calculate from message+tool sizes |
| `MaxTokens` | `100000` | Token budget ceiling for context pruning display |
| `SummarizeAt` | `75000` | Tokens threshold that triggers Phase A summarisation |
| `MaxDepth` | `10` | Max tool-call recursion depth per user turn |
| `ToolBudgetTokens` | `6000` | Max tokens for injected tool schemas per request |
| `MaxToolCount` | `25` | Hard cap on tools selected per request |
| `CoreTools` | `@()` | Tool names always included regardless of relevance scoring |

---

## Development workflow

### Before every commit — REQUIRED

```powershell
pwsh tests/Run-Tests.ps1 -SchemaOnly
```

Schema validation + Config and Tools unit tests, no network. All must pass. The pre-commit hook enforces this automatically.

Full suite (requires Ollama running):
```powershell
pwsh tests/Run-Tests.ps1
```

This includes `Test-LiveAgent.ps1` — two suites:
- **E2E**: passes 3 explicit safe tools and a directed prompt through the real streaming pipeline; verifies ≥1 tool is invoked
- **Per-tool**: one test per discovered tool, exposing only that tool to the model to force deterministic invocation; smaller models (3b) may non-deterministically answer from memory — expect 1–3 [warn] failures per run, not regressions

Run just the live tests:
```powershell
pwsh tests/Run-Tests.ps1 -Suite LiveAgent
```

### After every commit

Check whether any new pattern, decision, or preference should be saved:
- Memory files: `~/.claude/projects/C--Users-matrix-projects-matrix/memory/`
- This file (`CLAUDE.md`) if the architecture or workflow changed

### Model requirements

The model is **auto-selected** based on available RAM and installed Ollama models (via `Select-MatrixModel`). The default tier pyramid:

| RAM | Model |
|-----|-------|
| ≥20 GB | `qwen3:8b` |
| ≥12 GB | `qwen2.5:7b` |
| ≥6 GB | `qwen3:4b` |
| any | `llama3.2:3b` |

To pin a specific model, set `Model` explicitly in `config.json` (disables auto-selection):
```json
{ "Model": "llama3.2:3b" }
```
`config.json` is gitignored — set it per machine. Pull models with `ollama pull <model>`.

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
pwsh tests/Run-Tests.ps1 -Suite Config      # config unit tests only
pwsh tests/Run-Tests.ps1 -Suite Tools       # tool unit tests only
pwsh tests/Run-Tests.ps1 -Suite MultiTool   # integration tests only
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

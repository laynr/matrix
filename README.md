# matrix.ps1

An AI agent for Windows built in PowerShell 5.1. Runs entirely locally using **Ollama + gemma4**. Features a CLI mode and a plugin system that lets the AI call PowerShell scripts as tools.

> Part of the [Matrix](https://github.com/laynr/matrix) family — also available for [Mac/Linux (Python)](https://github.com/laynr/matrix.py).

## Install — one command

Run this in **PowerShell** (no Administrator required):

```powershell
irm https://raw.githubusercontent.com/laynr/matrix.ps1/main/install.ps1 | iex
```

The installer will:
- Set the execution policy to `RemoteSigned` for the current user (if needed)
- Install **Git** via `winget` if missing
- Install **Ollama** via `winget` (or direct download if winget unavailable)
- Pull **gemma4:latest**
- Clone this repo to `~\.matrix`
- Register a `matrix` command in `~/bin` and add it to your `PATH`
- Launch Matrix in CLI mode immediately

After the first install, just run:

```powershell
matrix
```

## Adding tools

Drop a `.ps1` file into the `tools/` directory. Matrix discovers it automatically via PowerShell's AST parser — your parameter names and `.SYNOPSIS` block become the tool schema.

```powershell
<#
.SYNOPSIS
Returns the current disk usage for a given drive.
.PARAMETER Drive
The drive letter to check (e.g. C:).
#>
param(
    [string]$Drive = "C:"
)
Get-PSDrive $Drive | Select-Object Used, Free
```

No registration needed. Type `reload` in the REPL and the tool is live.

## Built-in tools

| Tool | What it does |
|------|-------------|
| `Get-Time` | Current date, time, and timezone |
| `Get-SystemInfo` | OS version, CPU load, memory |
| `Get-Weather` | Current weather for a location |
| `Get-WikipediaSummary` | Wikipedia article summary |
| `Invoke-Math` | Evaluate a math expression |

## REPL commands

| Command | Action |
|---------|--------|
| `reload` | Rescan `tools/` and register new tools |
| `exit` / `quit` | Exit |

## Configuration

Override via environment variables before running:

```powershell
$env:MATRIX_MODEL = "gemma4:27b"
matrix
```

Or edit `~\.matrix\config.json`:

```json
{
  "Provider":     "Ollama",
  "Model":        "gemma4:latest",
  "Endpoint":     "http://localhost:11434/api/chat",
  "SystemPrompt": "You are Matrix..."
}
```

## Manual install

```powershell
git clone https://github.com/laynr/matrix.ps1 ~/.matrix
cd ~/.matrix
.\Matrix.ps1 -CLI
```

## License

MIT

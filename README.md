# Matrix

An AI agent built in **PowerShell Core (pwsh 7+)**. Runs on **Mac, Linux, and Windows** using Ollama + gemma4. Tools are `.ps1` scripts dropped into the `tools/` directory.

## Install — one command

### Mac / Linux
```sh
curl -fsSL https://raw.githubusercontent.com/laynr/matrix/main/install.sh | sh
```

### Windows (PowerShell 5.1+)
```powershell
irm https://raw.githubusercontent.com/laynr/matrix/main/install.ps1 | iex
```

The installer:
1. Installs **PowerShell 7** (`pwsh`) if missing — using native OS tools only (brew/pkg on Mac, snap/apt/dnf/tarball on Linux, winget/MSI on Windows)
2. Installs **Ollama** if missing
3. Pulls **gemma4:latest**
4. Downloads and extracts the latest release to `~/.matrix`
5. Installs a `matrix` command
6. Starts Matrix immediately

After install, just run:
```
matrix
```

## How it works

The bootstrap (`install.sh` / `install.ps1`) is the only platform-specific part — it installs `pwsh` using whatever tools are natively available on the OS. Once `pwsh` is running, `install.pwsh.ps1` takes over and is **identical on all platforms**.

```
install.sh      ← Mac/Linux: sh bootstrap → installs pwsh
install.ps1     ← Windows:   PS5 bootstrap → installs pwsh 7
    └── install.pwsh.ps1   ← shared pwsh 7 setup (Ollama, model, download release, launcher)
            └── Matrix.ps1 ← cross-platform agent (pwsh 7, all OS)
```

## Adding tools

Drop a `.ps1` file into `tools/`. Matrix discovers it automatically on the next message (schemas are cached; run `reload` to pick up new files immediately).

### Tool template

Copy this into a new file like `tools/My-Tool.ps1`:

```powershell
<#
.SYNOPSIS
One sentence: what does this tool do?

.PARAMETER InputText
The text to process.

.PARAMETER MaxResults
How many results to return. Default: 10.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputText,

    [int]$MaxResults = 10
)

try {
    # Your logic here. Use $IsWindows / $IsMacOS / $IsLinux for platform branches.

    return @{
        Result = "value"
        Count  = 0
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
```

### Rules for tool authors

| Rule | Why |
|------|-----|
| Always `[CmdletBinding()]` | Required for Mandatory param detection |
| Always `try/catch` returning `{ error: "..." }` | Agent handles errors gracefully |
| Always return JSON — never `Write-Host` | Output goes to the model, not the screen |
| Use `-Depth 3 -Compress` on output | Consistent, compact |
| Add `-TimeoutSec 15` to any `Invoke-RestMethod` | Don't let the agent hang |
| Use `$IsWindows / $IsMacOS / $IsLinux` | Cross-platform required |
| Keep `.SYNOPSIS` to one sentence | Becomes the tool description the model sees |

Type `reload` in the REPL — the tool is live immediately, no restart.

## Built-in tools

| Tool | What it does |
|------|-------------|
| `Get-Time` | Current date, time, and timezone |
| `Get-SystemInfo` | OS, CPU load, memory (cross-platform) |
| `Get-Weather` | Current weather for a location |
| `Get-WikipediaSummary` | Wikipedia article summary |
| `Invoke-Math` | Evaluate a math expression |
| `Read-File` | Read a file's contents, with optional line range |
| `Write-FileContent` | Write or append text to a file |
| `Find-Files` | Search for files by name pattern or text content |
| `Get-WebContent` | Fetch a URL and return readable text |
| `Get-ProcessList` | List running processes, filtered by name |
| `Invoke-ShellCommand` | Run a shell command and return its output |
| `Get-EnvVariable` | Read one or all environment variables |
| `Convert-Units` | Convert between temperature, length, weight, data size, speed |
| `Get-IPInfo` | Public IP address and geolocation |
| `Convert-DataFormat` | Convert between JSON, CSV, list, and table |

## REPL commands

| Command | Action |
|---------|--------|
| `reload` | Rescan `tools/` and register new tools |
| `clear` | Reset conversation history |
| `tools` | List loaded tools with descriptions |
| `help` | Show all commands |
| `exit` / `quit` | Exit |

## Configuration

```powershell
# Override model
$env:MATRIX_MODEL = "gemma4:27b"
matrix

# Custom install location
$env:MATRIX_HOME = "/opt/matrix"
```

Or edit `~/.matrix/config.json`:
```json
{
  "Model":        "gemma4:latest",
  "Endpoint":     "http://localhost:11434/api/chat",
  "SystemPrompt": "You are Matrix...",
  "NumCtx":       0,
  "MaxTokens":    100000,
  "SummarizeAt":  75000,
  "MaxDepth":     10
}
```

All fields are optional. `NumCtx = 0` means auto-calculate context size from message + tool schema sizes.

## Windows

On Windows, `matrix` starts the WPF GUI. `matrix -CLI` opens the terminal interface, which is **identical to Mac and Linux**:

```powershell
matrix          # GUI (Windows default)
matrix -CLI     # Terminal REPL — same on all platforms
```

The spinner, tool calling, reload command, and all other behaviour are exactly the same in CLI mode regardless of OS.

## Manual run

```sh
pwsh -NoProfile -ExecutionPolicy Bypass -File ~/.matrix/Matrix.ps1 -CLI
```

## License

MIT

# matrix.ps1

An AI agent built in **PowerShell Core (pwsh 7+)**. Runs on **Mac, Linux, and Windows** using Ollama + gemma4. Tools are `.ps1` scripts dropped into the `tools/` directory.

> Part of the [Matrix](https://github.com/laynr/matrix) family — also available as [matrix.py](https://github.com/laynr/matrix.py) (Python).

## Install — one command

### Mac / Linux
```sh
curl -fsSL https://raw.githubusercontent.com/laynr/matrix.ps1/main/install.sh | sh
```

### Windows (PowerShell 5.1+)
```powershell
irm https://raw.githubusercontent.com/laynr/matrix.ps1/main/install.ps1 | iex
```

The installer:
1. Installs **PowerShell 7** (`pwsh`) if missing — using native OS tools only (brew/pkg on Mac, snap/apt/dnf/tarball on Linux, winget/MSI on Windows)
2. Installs **Ollama** if missing
3. Pulls **gemma4:latest**
4. Clones this repo to `~/.matrix`
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
    └── install.pwsh.ps1   ← shared pwsh 7 setup (Ollama, model, repo, launcher)
            └── Matrix.ps1 ← cross-platform agent (pwsh 7, all OS)
```

## Adding tools

Drop a `.ps1` file into `tools/`. Matrix discovers it automatically — `.SYNOPSIS` becomes the description, `param()` block becomes the schema.

```powershell
<#
.SYNOPSIS
Returns the disk usage for a drive or path.
.PARAMETER Path
The path to check. Defaults to current drive root.
#>
param([string]$Path = "/")
$info = Get-PSDrive (Split-Path $Path -Qualifier).TrimEnd(':') -ErrorAction SilentlyContinue
if ($info) { @{ Used = $info.Used; Free = $info.Free } | ConvertTo-Json -Compress }
else { Get-Item $Path | Select-Object FullName, @{n='SizeBytes';e={(Get-ChildItem $_ -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum}} | ConvertTo-Json }
```

Type `reload` in the REPL — it's live immediately, no restart.

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
  "Provider":     "Ollama",
  "Model":        "gemma4:latest",
  "Endpoint":     "http://localhost:11434/api/chat",
  "SystemPrompt": "You are Matrix..."
}
```

## Windows GUI

On Windows, `matrix` starts the WPF GUI. Use `-CLI` for the terminal:
```powershell
matrix -CLI
```

On Mac and Linux, CLI mode is always used (no WPF).

## Manual run

```sh
pwsh -NoProfile -ExecutionPolicy Bypass -File ~/.matrix/Matrix.ps1 -CLI
```

## License

MIT

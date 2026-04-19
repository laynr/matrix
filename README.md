# Matrix

An AI agent built in **PowerShell Core (pwsh 7+)**. Runs on **Mac, Linux, and Windows** using Ollama. Tools are `.ps1` scripts dropped into the `tools/` directory — 61 built-in tools, auto-discovered.

## Install — one command

### Mac / Linux
```sh
curl -fsSL https://raw.githubusercontent.com/laynr/matrix/main/install/install.sh | sh
```

### Windows (PowerShell 5.1+)
```powershell
irm https://raw.githubusercontent.com/laynr/matrix/main/install/install.ps1 | iex
```

The installer:
1. Installs **PowerShell 7** (`pwsh`) if missing — using native OS tools only (brew/pkg on Mac, snap/apt/dnf/tarball on Linux, winget/MSI on Windows)
2. Installs **Ollama** if missing
3. Pulls the best model for your available RAM (auto-selected from a tier list; default `qwen3:4b`)
4. Downloads and extracts the latest release to `~/.matrix`
5. Installs a `matrix` command
6. Starts Matrix immediately

After install, just run:
```
matrix
```

## How it works

The bootstrap (`install/install.sh` / `install/install.ps1`) is the only platform-specific part — it installs `pwsh` using whatever tools are natively available on the OS. Once `pwsh` is running, `install/install.pwsh.ps1` takes over and is **identical on all platforms**.

```
install/
  install.sh        ← Mac/Linux: sh bootstrap → installs pwsh
  install.ps1       ← Windows:   PS5 bootstrap → installs pwsh 7
  install.pwsh.ps1  ← shared pwsh 7 setup (Ollama, model, download release, launcher)
  uninstall.pwsh.ps1← removes ~/.matrix and the launcher
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

Or use the scaffolding command inside Claude Code:
```
/add-tool <name: description>
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

## Built-in tools (61)

### Time & System
| Tool | What it does |
|------|-------------|
| `Get-Time` | Current date, time, and timezone |
| `Get-SystemInfo` | OS, CPU load, and memory usage (cross-platform) |
| `Get-ProcessList` | Running processes, filterable by name |
| `Get-DiskInfo` | Disk drives and space usage |
| `Get-NetworkAdapters` | Network interfaces and IP addresses |
| `Get-ActiveConnections` | Active TCP connections with state and process |
| `Get-ServiceList` | System services, filterable by name or state |
| `Get-EventLogEntries` | Recent system log events |
| `Get-ScheduledTaskList` | Scheduled tasks (cross-platform) |
| `Get-EnvVariable` | Read one or all environment variables |

### Files & Directories
| Tool | What it does |
|------|-------------|
| `Read-File` | Read file contents with optional line range |
| `Write-FileContent` | Write or append text to a file |
| `Edit-FileContent` | Find-and-replace in a file (literal or regex) |
| `Find-Files` | Search for files by name pattern or text content |
| `Move-FileItem` | Move or rename a file or directory |
| `Copy-FileItem` | Copy a file or directory |
| `Compare-FileContent` | Diff two files, line by line |
| `Sort-FileItems` | Group files into subfolders by extension, date, or size |
| `Get-DirectoryTree` | Recursive directory tree with file counts |
| `Get-FileHash` | SHA256 / MD5 hash of a file |
| `New-ZipArchive` | Create a ZIP archive from a directory or file list |
| `Expand-ZipArchive` | Extract a ZIP archive |

### Network & Web
| Tool | What it does |
|------|-------------|
| `Get-WebContent` | Fetch a URL and return readable text |
| `Invoke-HttpRequest` | Full HTTP client — GET/POST/PUT with headers and body |
| `Get-IPInfo` | Public IP address and geolocation |
| `Test-NetworkHost` | Ping and port reachability check |
| `Get-DnsRecord` | DNS lookup (A, MX, TXT, etc.) |
| `Get-CertificateInfo` | TLS/SSL certificate details for a URL or file |
| `New-WebSession` | Create a persistent cookie session for web scraping |
| `Invoke-WebSession` | Make requests using a saved cookie session |

### Data & Conversion
| Tool | What it does |
|------|-------------|
| `Invoke-Math` | Evaluate a math expression |
| `Convert-Units` | Convert temperature, length, weight, data size, speed |
| `Convert-DataFormat` | Convert between JSON, CSV, list, and table formats |
| `ConvertTo-Base64` | Encode text or a file to Base64 |
| `ConvertFrom-Base64` | Decode Base64 to text or a file |
| `Get-RegexMatches` | Extract regex matches from text |
| `Invoke-TextTemplate` | Fill a `{{variable}}` template with values |

### Online Services
| Tool | What it does |
|------|-------------|
| `Get-Weather` | Current weather for any location |
| `Get-WikipediaSummary` | Wikipedia article summary |
| `Get-StockQuote` | Real-time stock price |
| `Get-CurrencyRate` | Live exchange rates |
| `Get-RssFeed` | Parse an RSS or Atom feed |
| `Search-Images` | Search for images in a directory |

### Office & Documents
| Tool | What it does |
|------|-------------|
| `Write-DocxFile` | Create a Word `.docx` file |
| `Read-DocxFile` | Read text and paragraphs from a `.docx` |
| `Write-XlsxFile` | Create an Excel `.xlsx` spreadsheet |
| `Read-XlsxFile` | Read rows from an `.xlsx` spreadsheet |
| `Write-PdfFile` | Create a PDF document |
| `Read-PdfFile` | Extract text from a PDF |
| `Write-PptxFile` | Create a PowerPoint `.pptx` presentation |
| `Read-PptxFile` | Read slide content from a `.pptx` |

### Images
| Tool | What it does |
|------|-------------|
| `Get-ImageMetadata` | EXIF metadata (dimensions, camera, GPS) |
| `Sort-ImageFiles` | Organize images into date-based subfolders |

### Security & Crypto
| Tool | What it does |
|------|-------------|
| `Protect-String` | AES-256 encrypt a string with a password |
| `Unprotect-String` | Decrypt an AES-256 encrypted string |
| `New-SecureToken` | Generate a cryptographically secure random token |
| `Get-CertificateInfo` | Inspect TLS/SSL certificates |

### Clipboard
| Tool | What it does |
|------|-------------|
| `Get-ClipboardContent` | Read the system clipboard |
| `Set-ClipboardContent` | Write text to the system clipboard |

### Notifications & Messaging
| Tool | What it does |
|------|-------------|
| `Send-SystemNotification` | Desktop notification (macOS, Linux, Windows) |
| `Send-SlackMessage` | Post to a Slack webhook |
| `Send-TeamsMessage` | Post to a Microsoft Teams webhook |

## REPL commands

| Command | Action |
|---------|--------|
| `reload` | Rescan `tools/` and register new tools |
| `clear` | Reset conversation history |
| `tools` | List loaded tools with descriptions |
| `help` | Show all commands |
| `exit` / `quit` | Exit |

## Configuration

Edit `~/.matrix/config.json` (all fields optional):
```json
{
  "Model":             "qwen3:4b",
  "Endpoint":          "http://localhost:11434/api/chat",
  "SystemPrompt":      "You are Matrix...",
  "NumCtx":            0,
  "MaxTokens":         100000,
  "SummarizeAt":       75000,
  "MaxDepth":          10,
  "ToolBudgetTokens":  6000,
  "MaxToolCount":      25,
  "CoreTools":         []
}
```

`Model` is **auto-selected** based on available RAM and which models are installed in Ollama — you don't need to set it unless you want to pin a specific model. The default tier pyramid:

| RAM | Auto-selected model |
|-----|---------------------|
| ≥20 GB | `qwen3:8b` |
| ≥12 GB | `qwen2.5:7b` |
| ≥6 GB | `qwen3:4b` |
| any | `llama3.2:3b` |

`NumCtx = 0` means auto-calculate context size from message + tool schema sizes.

## Windows

On Windows, `matrix` starts the WPF GUI. `matrix -CLI` opens the terminal interface, which is **identical to Mac and Linux**:

```powershell
matrix          # GUI (Windows default)
matrix -CLI     # Terminal REPL — same on all platforms
```

## Manual run

```sh
pwsh -NoProfile -ExecutionPolicy Bypass -File ~/.matrix/Matrix.ps1 -CLI
```

## Development

```powershell
# Before every commit (required — CI enforces this)
pwsh tests/Run-Tests.ps1 -SchemaOnly

# Full suite (requires Ollama running)
pwsh tests/Run-Tests.ps1

# Specific suite
pwsh tests/Run-Tests.ps1 -Suite Config
pwsh tests/Run-Tests.ps1 -Suite Tools
pwsh tests/Run-Tests.ps1 -Suite MultiTool
pwsh tests/Run-Tests.ps1 -Suite LiveAgent
```

## License

MIT

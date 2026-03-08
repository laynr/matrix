# Matrix AI Agent

Matrix is a high-performance, intelligent AI assistant built entirely in PowerShell 5.1. It features a modern WPF GUI, a versatile CLI, and a powerful plugin system that allows the AI to interact directly with your system using PowerShell scripts.

## Features

- **Modern WPF GUI**: A sleek, dark-themed interface with file attachment support and real-time chat.
- **Versatile CLI**: A lightweight command-line interface for fast interactions and automation.
- **PowerShell Plugin System**: Native tool calling support using `.ps1` files. (e.g., `Get-Time` is included by default).
- **Context Management**: Automatic message history pruning to stay within model token limits.
- **Anthropic Claude Integration**: Optimized for Claude 3.5 Sonnet and Haiku.

## Quick Start

### Prerequisites
- Windows PowerShell 5.1
- An Anthropic API Key

### Installation
1. Clone the repository:
   ```powershell
   git clone https://github.com/yourusername/matrix.git
   cd matrix
   ```
2. Run the agent:
   ```powershell
   .\Matrix.ps1
   ```
3. Set your API Key in the **Settings** (gear icon) on first run.

### CLI Mode
To run in terminal mode:
```powershell
.\Matrix.ps1 -CLI
```

## Plugin Development
Matrix discovers tools by parsing `.ps1` scripts in the `plugins/` directory. Each script is automatically converted into a Claude-compatible tool schema using AST parsing.

To add a new tool:
1. Create a script in `plugins/Your-Tool.ps1`.
2. Use standard PowerShell parameters and help comments (Synopsis).
3. The AI will automatically discover and know how to call it!

## License
MIT

# Matrix

An AI agent that runs on **Mac**, **Linux**, and **Windows**. One command installs the right version for your platform.

## Install

### Mac / Linux
```sh
curl -fsSL https://raw.githubusercontent.com/laynr/matrix/main/install.sh | sh
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/laynr/matrix/main/install.ps1 | iex
```

After install, just run:
```
matrix
```

## Platform ports

| Platform | Repo | Runtime | Backend |
|----------|------|---------|---------|
| Mac / Linux | [matrix.py](https://github.com/laynr/matrix.py) | Python 3 | Ollama + gemma4 |
| Windows | [matrix.ps1](https://github.com/laynr/matrix.ps1) | PowerShell 5.1 | Anthropic Claude |

The meta-installer in this repo detects your OS and delegates to the appropriate port. Each port is maintained in its own repo.

## What it does

Matrix is a local AI agent with a dynamic tool system:

- **Mac/Linux** — talks to a local Ollama instance running gemma4. Tools are Python files dropped into a `tools/` directory.
- **Windows** — talks to the Anthropic Claude API. Tools are PowerShell scripts dropped into a `plugins/` directory.

Both versions reload tools at runtime — no restart needed.

## Architecture

```
laynr/matrix          ← you are here (meta-installer, cross-platform entry point)
├── laynr/matrix.py   ← Mac / Linux (Python + Ollama)
└── laynr/matrix.ps1  ← Windows (PowerShell + Claude)
```

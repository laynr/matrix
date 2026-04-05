#!/usr/bin/env sh
# Matrix — cross-platform meta-installer
#
# Detects your OS and installs the right port:
#   Mac/Linux  → github.com/laynr/matrix.py   (Python + Ollama)
#   Windows    → github.com/laynr/matrix.ps1  (PowerShell + Claude)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/laynr/matrix/main/install.sh | sh

OS="$(uname -s 2>/dev/null || echo unknown)"

case "$OS" in
    Darwin|Linux)
        echo ""
        echo "  Matrix — detected $OS"
        echo "  Installing matrix.py (Python + Ollama)..."
        echo ""
        curl -fsSL https://raw.githubusercontent.com/laynr/matrix.py/main/install.sh | sh
        ;;
    *)
        echo ""
        echo "  Matrix — OS not recognised: $OS"
        echo ""
        echo "  On Windows, open PowerShell and run:"
        echo "    irm https://raw.githubusercontent.com/laynr/matrix/main/install.ps1 | iex"
        echo ""
        exit 1
        ;;
esac

#!/usr/bin/env sh
# Matrix (PowerShell) — Mac/Linux bootstrap
#
# Only uses tools available by default on the OS.
# Installs PowerShell Core (pwsh) if missing, then hands off
# to install.pwsh.ps1 which runs identically on all platforms.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/laynr/matrix/main/install/install.sh | sh

set -e

OS="$(uname -s)"
ARCH="$(uname -m)"
PWSH_INSTALLER_URL="https://github.com/laynr/matrix/releases/latest/download/install.pwsh.ps1"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { printf "  ${GREEN}[ok]${NC}    %s\n" "$*"; }
info() { printf "  ${CYAN}[setup]${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}[warn]${NC}  %s\n" "$*"; }
die()  { printf "  ${RED}[error]${NC} %s\n" "$*" >&2; exit 1; }

echo ""
echo "  +----------------------------------+"
echo "  |          M A T R I X             |"
echo "  |   AI Agent  *  PowerShell Core   |"
echo "  +----------------------------------+"
echo "  Platform: $OS / $ARCH"
echo ""

# ── Install pwsh if missing ────────────────────────────────────────────────────
install_pwsh_macos() {
    # Try Homebrew casks in order of availability
    if command -v brew >/dev/null 2>&1; then
        info "Trying PowerShell via Homebrew..."
        brew install --cask powershell 2>/dev/null \
            || brew install --cask powershell@preview 2>/dev/null \
            || { brew tap microsoft/homebrew-tap 2>/dev/null; brew install --cask powershell 2>/dev/null; } \
            || true
    fi

    # Fall through to .pkg if Homebrew didn't get us there
    if ! command -v pwsh >/dev/null 2>&1; then
        case "$ARCH" in
            arm64)  PKG_ARCH="osx-arm64" ;;
            x86_64) PKG_ARCH="osx-x64" ;;
            *)      die "Unsupported Mac arch: $ARCH" ;;
        esac
        PWSH_VER=$(curl -fsSL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" \
            | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
        [ -z "$PWSH_VER" ] && die "Could not resolve latest PowerShell version"
        TMP_PKG="$(mktemp /tmp/pwsh.XXXXXX.pkg)"
        info "Downloading powershell-${PWSH_VER}-${PKG_ARCH}.pkg..."
        curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VER}/powershell-${PWSH_VER}-${PKG_ARCH}.pkg" \
            -o "$TMP_PKG" --retry 3 --retry-delay 2
        info "Installing package (requires sudo)..."
        sudo installer -pkg "$TMP_PKG" -target /
        rm -f "$TMP_PKG"
    fi
}

install_pwsh_linux() {
    # apt
    if command -v apt-get >/dev/null 2>&1; then
        info "Installing PowerShell via apt..."
        VER=$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-22.04}")
        TMP_DEB="$(mktemp /tmp/msprod.XXXXXX.deb)"
        curl -fsSL "https://packages.microsoft.com/config/ubuntu/${VER}/packages-microsoft-prod.deb" \
            -o "$TMP_DEB" 2>/dev/null \
            || curl -fsSL "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -o "$TMP_DEB"
        sudo dpkg -i "$TMP_DEB" >/dev/null 2>&1 || true
        rm -f "$TMP_DEB"
        sudo apt-get update -qq && sudo apt-get install -y powershell
        return
    fi
    # dnf / yum
    if command -v dnf >/dev/null 2>&1; then
        info "Installing PowerShell via dnf..."
        sudo dnf install -y powershell && return
    fi
    if command -v yum >/dev/null 2>&1; then
        info "Installing PowerShell via yum..."
        sudo yum install -y powershell && return
    fi
    # snap — last resort (classic confinement can block on some distros)
    if command -v snap >/dev/null 2>&1; then
        info "Installing PowerShell via snap..."
        sudo snap install powershell --classic && return
    fi
    # tarball fallback → ~/.local
    case "$ARCH" in
        x86_64)         TAR_ARCH="linux-x64" ;;
        aarch64|arm64)  TAR_ARCH="linux-arm64" ;;
        *)              die "Unsupported Linux arch: $ARCH" ;;
    esac
    PWSH_VER=$(curl -fsSL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    [ -z "$PWSH_VER" ] && die "Could not resolve latest PowerShell version"
    TMP_TAR="$(mktemp /tmp/pwsh.XXXXXX.tar.gz)"
    info "Downloading powershell-${PWSH_VER}-${TAR_ARCH}.tar.gz..."
    curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VER}/powershell-${PWSH_VER}-${TAR_ARCH}.tar.gz" -o "$TMP_TAR"
    PWSH_DIR="$HOME/.local/lib/powershell"
    mkdir -p "$PWSH_DIR" "$HOME/.local/bin"
    tar -xzf "$TMP_TAR" -C "$PWSH_DIR"
    chmod +x "$PWSH_DIR/pwsh"
    ln -sf "$PWSH_DIR/pwsh" "$HOME/.local/bin/pwsh"
    export PATH="$HOME/.local/bin:$PATH"
    rm -f "$TMP_TAR"
}

if command -v pwsh >/dev/null 2>&1; then
    ok "PowerShell already installed: $(pwsh --version)"
else
    warn "PowerShell Core not found — installing..."
    case "$OS" in
        Darwin) install_pwsh_macos ;;
        Linux)  install_pwsh_linux ;;
        *)      die "Unsupported OS: $OS. Install PowerShell from https://aka.ms/install-powershell" ;;
    esac
    command -v pwsh >/dev/null 2>&1 || die "PowerShell installation failed."
    ok "PowerShell installed: $(pwsh --version)"
fi

# ── Hand off to the shared cross-platform PowerShell installer ────────────────
info "Running cross-platform PowerShell installer..."
echo ""

TMP_PS="$(mktemp /tmp/matrix_install.XXXXXX)"
TMP_PS_EXT="${TMP_PS}.ps1"
mv "$TMP_PS" "$TMP_PS_EXT"
TMP_PS="$TMP_PS_EXT"
curl -fsSL "$PWSH_INSTALLER_URL" -o "$TMP_PS"

# Launch with /dev/tty so the agent started at the end can accept input
if [ -t 0 ]; then
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$TMP_PS"
elif ( exec </dev/tty ) 2>/dev/null; then
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$TMP_PS" </dev/tty
else
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$TMP_PS"
fi

rm -f "$TMP_PS"

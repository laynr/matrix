#!/usr/bin/env sh
# tests/Test-Install.sh — static + behavioral tests for install.sh
#
# No network, no real installations. Uses PATH-mocked stubs.
#
# Usage:
#   sh tests/Test-Install.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$(cd "$SCRIPT_DIR/.." && pwd)/install.sh"
PASS=0
FAIL=0

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'
pass() { PASS=$((PASS+1)); printf "  ${GREEN}[pass]${NC} %s\n" "$*"; }
fail() { FAIL=$((FAIL+1)); printf "  ${RED}[FAIL]${NC} %s\n" "$*"; }
skip() { printf "  ${GRAY}[skip]${NC} %s\n" "$*"; }
suite(){ printf "\n  ${CYAN}Suite: %s${NC}\n" "$*"; }

printf "\n"
printf "  +----------------------------------+\n"
printf "  |   install.sh test suite          |\n"
printf "  +----------------------------------+\n"
printf "  Script: %s\n" "$INSTALL_SH"
printf "\n"

# ── 1. File presence ───────────────────────────────────────────────────────────
suite "File presence"

if [ -f "$INSTALL_SH" ]; then
    pass "install.sh exists"
else
    fail "install.sh not found at $INSTALL_SH"
    printf "\n  Results: %d passed, %d failed\n\n" "$PASS" "$FAIL"
    exit 1
fi

# ── 2. Syntax check ────────────────────────────────────────────────────────────
suite "Syntax"

if sh -n "$INSTALL_SH" 2>/dev/null; then
    pass "sh -n syntax check"
else
    fail "sh -n syntax check"
fi

# ── 3. shellcheck ──────────────────────────────────────────────────────────────
suite "shellcheck"

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -S warning "$INSTALL_SH" 2>&1; then
        pass "shellcheck clean"
    else
        fail "shellcheck found issues"
    fi
else
    skip "shellcheck not installed (brew install shellcheck to enable)"
fi

# ── 4. mktemp portability ──────────────────────────────────────────────────────
suite "mktemp portability"

# Verify install.sh does NOT use the broken pattern (suffix embedded in template)
if grep -qF 'mktemp /tmp/matrix_install.XXXXXX.ps1' "$INSTALL_SH" 2>/dev/null; then
    fail "install.sh uses broken mktemp pattern — suffix must not be inside template"
else
    pass "install.sh mktemp pattern is portable (no suffix in template)"
fi

# Verify the actual pattern used works on this platform
TMP_BASE="$(mktemp /tmp/matrix_test.XXXXXX)"
TMP_EXT="${TMP_BASE}.ps1"
mv "$TMP_BASE" "$TMP_EXT"
if [ -f "$TMP_EXT" ]; then
    pass "mktemp + mv creates .ps1 file on this platform"
    rm -f "$TMP_EXT"
    pass "temp file cleanup works"
else
    fail "mktemp + mv did not produce expected file on this platform"
fi

# ── 5. Mock run: pwsh already present ─────────────────────────────────────────
suite "Mock run (pwsh already installed)"

MOCK_BIN="$(mktemp -d /tmp/matrix_test_bin.XXXXXX)"

# Stub: pwsh — reports version, exits cleanly for any other invocation
cat > "$MOCK_BIN/pwsh" <<'STUB'
#!/usr/bin/env sh
case "$1" in
    --version) printf "PowerShell 7.6.0\n"; exit 0 ;;
    *)         exit 0 ;;
esac
STUB
chmod +x "$MOCK_BIN/pwsh"

# Stub: curl — writes an empty file to -o target, ignores all other flags
cat > "$MOCK_BIN/curl" <<'STUB'
#!/usr/bin/env sh
while [ $# -gt 0 ]; do
    if [ "$1" = "-o" ]; then touch "$2"; shift 2; else shift; fi
done
exit 0
STUB
chmod +x "$MOCK_BIN/curl"

# Stub: brew — unavailable (forces fallback path on macOS if reached)
cat > "$MOCK_BIN/brew" <<'STUB'
#!/usr/bin/env sh
exit 1
STUB
chmod +x "$MOCK_BIN/brew"

# Track pre-existing temp files so cleanup check is accurate
BEFORE_COUNT="$(find /tmp -maxdepth 1 -name 'matrix_install.*.ps1' 2>/dev/null | wc -l | tr -d ' ')"

# Use a file to capture output — avoids command-substitution stdin changes
# that would make /dev/tty inaccessible inside install.sh
TMP_OUT="$(mktemp /tmp/matrix_test_out.XXXXXX)"
PATH="$MOCK_BIN:$PATH" sh "$INSTALL_SH" >"$TMP_OUT" 2>&1 && RC=0 || RC=$?
OUTPUT="$(cat "$TMP_OUT")"
rm -f "$TMP_OUT"

if echo "$OUTPUT" | grep -qi "already installed"; then
    pass "detected pwsh as already installed"
else
    fail "did not detect existing pwsh — output:\n$OUTPUT"
fi

if [ "$RC" -eq 0 ]; then
    pass "script exited cleanly (exit 0)"
else
    fail "script exited with code $RC"
fi

if echo "$OUTPUT" | grep -qi "cross-platform powershell installer"; then
    pass "handed off to cross-platform installer"
else
    fail "no handoff message found in output"
fi

# Temp .ps1 must be cleaned up by the script's rm -f
AFTER_COUNT="$(find /tmp -maxdepth 1 -name 'matrix_install.*.ps1' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$AFTER_COUNT" -le "$BEFORE_COUNT" ]; then
    pass "no temp .ps1 files left behind"
else
    fail "$((AFTER_COUNT - BEFORE_COUNT)) temp .ps1 file(s) were not cleaned up"
fi

rm -rf "$MOCK_BIN"

# ── Summary ────────────────────────────────────────────────────────────────────
printf "\n  Results: %d passed, %d failed\n\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

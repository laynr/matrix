#!/usr/bin/env bash
# Pre-commit hook: runs Matrix schema tests before any git commit.
# Blocks the commit (exit 2) if tests fail.
# Claude Code fires this before every Bash tool call; the script only acts on commits.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only intercept git commit commands
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
    exit 0
fi

# Resolve project root dynamically — works on any machine/OS
MATRIX_DIR=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

if [[ -z "$MATRIX_DIR" || ! -f "$MATRIX_DIR/tests/Run-Tests.ps1" ]]; then
    echo "  [pre-commit] Matrix tests not found — skipping test gate" >&2
    exit 0
fi

echo "  [pre-commit] Running Matrix schema tests before commit..." >&2

if pwsh -NoProfile -ExecutionPolicy Bypass \
       -File "$MATRIX_DIR/tests/Run-Tests.ps1" -SchemaOnly 2>&1; then
    echo "  [pre-commit] Tests passed — proceeding with commit." >&2
    exit 0
else
    echo "" >&2
    echo "  [pre-commit] TESTS FAILED — commit blocked." >&2
    echo "  Fix the failures above, then retry the commit." >&2
    exit 2
fi

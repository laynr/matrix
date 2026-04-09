#!/usr/bin/env bash
# Pre-commit hook: runs matrix.ps1 schema tests before any git commit.
# Blocks the commit (exit 2) if tests fail.
# Claude Code fires this before every Bash tool call; the script only acts on commits.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only intercept git commit commands
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
    exit 0
fi

# Find the matrix.ps1 tests directory
MATRIX_DIR=""
for candidate in "/Users/layne/projects/matrix.ps1" "$HOME/.matrix" "$(pwd)"; do
    if [[ -f "$candidate/tests/Run-Tests.ps1" ]]; then
        MATRIX_DIR="$candidate"
        break
    fi
done

if [[ -z "$MATRIX_DIR" ]]; then
    echo "  [pre-commit] matrix.ps1 tests not found — skipping test gate" >&2
    exit 0
fi

echo "  [pre-commit] Running matrix.ps1 schema tests before commit..." >&2

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

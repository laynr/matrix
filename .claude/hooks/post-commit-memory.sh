#!/usr/bin/env bash
# Post-commit hook: prompts Claude to review whether memory files need updating.
# Fires after every successful Bash tool call; only outputs on git commits.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
EXIT_CODE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_response',{}).get('exit_code', 0))" 2>/dev/null || echo "0")

# Only fire on successful git commits
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
    exit 0
fi

if [[ "$EXIT_CODE" != "0" ]]; then
    exit 0
fi

# Derive memory path dynamically from the actual project root — works on any machine
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
# Convert to the Claude project key format: leading slash removed, remaining slashes → dashes
PROJECT_KEY=$(echo "$PROJECT_ROOT" | sed 's|^/||; s|/|-|g; s|\\|-|g; s|:||g')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"

cat <<EOF

────────────────────────────────────────────────────────────
  POST-COMMIT MEMORY REVIEW
────────────────────────────────────────────────────────────
  Commit succeeded. Please review whether any of the following
  should be updated before ending this session:

  1. Memory files in:
     $MEMORY_DIR
     → New patterns, decisions, user preferences, or lessons?

  2. CLAUDE.md (project guide):
     → Architecture changed? New rule needed? Workflow updated?

  3. .claude/commands/ (skills):
     → New workflow worth capturing as a slash command?

  Run: ls "$MEMORY_DIR"
────────────────────────────────────────────────────────────
EOF

exit 0

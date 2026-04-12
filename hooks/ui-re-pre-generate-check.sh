#!/usr/bin/env bash
# Pre-generation check hook for ui-reverse-engineering
# Runs validate-gate.sh pre-generate before any component file is written
# Install in settings.json PreToolUse for Write/Edit tools

# Only trigger when writing to component files in a project that has tmp/ref/
TOOL_INPUT="$1"

# Find the project's tmp/ref directory
REF_DIR=""
for d in tmp/ref/*/; do
  if [ -d "$d" ] && [ -f "${d}transition-spec.json" ]; then
    REF_DIR="$d"
    break
  fi
done

# If no ref dir, this isn't a ui-reverse-engineering project — skip
[ -z "$REF_DIR" ] && exit 0

# Find validate-gate.sh
GATE_SCRIPT="$(find ~/.claude/skills -name 'validate-gate.sh' 2>/dev/null | head -1)"
[ -z "$GATE_SCRIPT" ] && exit 0

# Run pre-generate gate
bash "$GATE_SCRIPT" "$REF_DIR" pre-generate > /tmp/ui-re-gate-result.txt 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "⛔ UI Reverse Engineering: pre-generate gate FAILED"
  echo "Missing artifacts detected. Run extraction steps first."
  cat /tmp/ui-re-gate-result.txt | grep -E '❌|⚠️' | head -5
  exit 1
fi

exit 0

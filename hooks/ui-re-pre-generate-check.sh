#!/usr/bin/env bash
# Pre-generation check hook for ui-reverse-engineering
# Runs validate-gate.sh pre-generate before any component file is written
# Install in settings.json PreToolUse for Write/Edit tools

# Only trigger when writing to component files in a project that has tmp/ref/
TOOL_INPUT="$1"

# Find the project's tmp/ref directory
# Pick the most recently modified ref dir that has extraction artifacts
REF_DIR=""
NEWEST_TIME=0
for d in tmp/ref/*/; do
  [ -d "$d" ] || continue
  for marker in regions.json structure.json extracted.json transition-spec.json component-map.json; do
    if [ -f "${d}${marker}" ]; then
      MOD_TIME=$(stat -f %m "${d}${marker}" 2>/dev/null || stat -c %Y "${d}${marker}" 2>/dev/null || echo "0")
      if [ "$MOD_TIME" -gt "$NEWEST_TIME" ]; then
        NEWEST_TIME="$MOD_TIME"
        REF_DIR="$d"
      fi
      break
    fi
  done
done

# If no ref dir, this isn't a ui-reverse-engineering project — skip
[ -z "$REF_DIR" ] && exit 0

# Find validate-gate.sh (check installed skills first, then source repo)
GATE_SCRIPT="$(find ~/.claude/skills -name 'validate-gate.sh' 2>/dev/null | head -1)"
[ -z "$GATE_SCRIPT" ] && GATE_SCRIPT="$(find ~/Documents/ui-skills -name 'validate-gate.sh' 2>/dev/null | head -1)"
[ -z "$GATE_SCRIPT" ] && exit 0

# Run pre-generate gate (capture stderr where gate outputs, ignore timestamp errors)
bash "$GATE_SCRIPT" "$REF_DIR" pre-generate > /tmp/ui-re-gate-result.txt 2>&1 || true

# Check for actual missing artifacts (❌ lines), not script infrastructure errors
MISSING_COUNT=$(grep -c '❌ MISSING\|❌ NO ' /tmp/ui-re-gate-result.txt 2>/dev/null || true)
MISSING_COUNT="${MISSING_COUNT:-0}"
MISSING_COUNT=$(echo "$MISSING_COUNT" | tr -d '[:space:]')

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "⛔ UI Reverse Engineering: pre-generate gate FAILED"
  echo "Missing artifacts detected. Run extraction steps first."
  grep -E '❌' /tmp/ui-re-gate-result.txt | head -5
  exit 1
fi

exit 0

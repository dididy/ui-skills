#!/usr/bin/env bash
# Pre-generation check hook for ui-reverse-engineering
# Runs validate-gate.sh pre-generate before any component file is written

TOOL_INPUT="$1"

# Find the project's tmp/ref directory (most recently modified)
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

# If no ref dir, not a ui-reverse-engineering project — skip
[ -z "$REF_DIR" ] && exit 0

# Find validate-gate.sh — use CLAUDE_PLUGIN_ROOT if set, then search known locations
GATE_SCRIPT=""
SEARCH_DIRS=("$HOME/.claude/skills/ui-reverse-engineering/scripts")
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && SEARCH_DIRS=("$CLAUDE_PLUGIN_ROOT/scripts" "${SEARCH_DIRS[@]}")
SEARCH_DIRS+=("$HOME/.claude/skills")
for search_dir in "${SEARCH_DIRS[@]}"; do
  if [ -f "$search_dir/validate-gate.sh" ]; then
    GATE_SCRIPT="$search_dir/validate-gate.sh"
    break
  fi
done
[ -z "$GATE_SCRIPT" ] && exit 0

# Run pre-generate gate
bash "$GATE_SCRIPT" "$REF_DIR" pre-generate > /tmp/ui-re-gate-result.txt 2>&1
GATE_EXIT=$?

if [ "$GATE_EXIT" -ne 0 ]; then
  STRIPPED=$(sed 's/\x1b\[[0-9;]*m//g' /tmp/ui-re-gate-result.txt)
  MISSING_COUNT=$(echo "$STRIPPED" | grep -c 'MISSING' 2>/dev/null || echo "0")
  MISSING_COUNT=$(echo "$MISSING_COUNT" | tr -d '[:space:]')

  if [ "$MISSING_COUNT" -gt 0 ]; then
    MISSING_LIST=$(echo "$STRIPPED" | grep 'MISSING' | head -8 | sed 's/.*— //' | tr '\n' ', ' | sed 's/, $//')
    cat <<HOOKJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "UI Reverse Engineering: extraction incomplete. Missing: $MISSING_LIST. Complete Phase 2 before writing components. Run: bash validate-gate.sh $REF_DIR pre-generate"
  }
}
HOOKJSON
    exit 0
  fi
fi

exit 0

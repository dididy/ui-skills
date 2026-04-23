#!/usr/bin/env bash
# Pre-generation check hook for ui-reverse-engineering
# Blocks Write/Edit on component files when extraction pipeline is incomplete
# Enhanced: also checks for multi-state extraction completeness

# Read tool input from $1 or stdin
TOOL_INPUT="${1:-$(cat 2>/dev/null)}"

# Extract file path
FILE_PATH=""
if [ -n "$TOOL_INPUT" ]; then
  FILE_PATH=$(echo "$TOOL_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')
fi

# Only enforce on component/page files — everything else passes freely
case "$FILE_PATH" in
  */src/components/*|*/src/app/*/page.*|*/src/projects/*/components/*)
    ;; # component file — enforce pipeline
  *)
    exit 0 ;; # not a component file or path unknown — skip
esac

# ── Find ref dir by most recent marker files ──
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

# No ref dir — not a ui-reverse-engineering project
[ -z "$REF_DIR" ] && exit 0

# ── Run pre-generate gate ──
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
    "permissionDecisionReason": "UI Reverse Engineering: extraction incomplete ($MISSING_COUNT artifacts missing). Missing: $MISSING_LIST. Complete Phase 2 before writing components."
  }
}
HOOKJSON
    exit 0
  fi
fi

# ── Mode 3: Multi-state extraction check ──
# If interactions-detected.json has click/navigation interactions,
# check that styles were extracted for EACH view state
INTERACTIONS_FILE="$REF_DIR/interactions-detected.json"
if [ -f "$INTERACTIONS_FILE" ]; then
  # Count interactions that change page state (click with navigation, js-class with view change)
  STATE_CHANGING=$(grep -c '"trigger"[[:space:]]*:[[:space:]]*"click"' "$INTERACTIONS_FILE" 2>/dev/null || echo "0")
  STATE_CHANGING=$(echo "$STATE_CHANGING" | tr -d '[:space:]')

  if [ "$STATE_CHANGING" -gt 0 ]; then
    # Check if there are multiple state extractions (e.g., styles-home.json, styles-search.json)
    # or if the main styles.json mentions multiple view states
    STATE_EXTRACTIONS=$(find "$REF_DIR" -name "styles-*.json" -o -name "structure-*.json" 2>/dev/null | wc -l | tr -d ' ')
    
    # Also check if transition-spec.json documents the state changes
    SPEC_FILE="$REF_DIR/transition-spec.json"
    HAS_STATE_DOCS=0
    if [ -f "$SPEC_FILE" ]; then
      HAS_STATE_DOCS=$(grep -c '"visual"' "$SPEC_FILE" 2>/dev/null || echo "0")
      HAS_STATE_DOCS=$(echo "$HAS_STATE_DOCS" | tr -d '[:space:]')
    fi

    if [ "$STATE_EXTRACTIONS" -eq 0 ] && [ "$HAS_STATE_DOCS" -eq 0 ]; then
      # Warn but don't block — this is a new check and shouldn't break existing workflows
      echo ""
      echo "⚠️  UI-RE: $STATE_CHANGING click interactions found but no per-state extraction."
      echo "    Consider extracting styles/DOM for each view state:"
      echo "    - Click the element in agent-browser"  
      echo "    - Extract getComputedStyle for the new state"
      echo "    - Save as styles-<state>.json, structure-<state>.json"
      echo ""
    fi
  fi
fi

exit 0

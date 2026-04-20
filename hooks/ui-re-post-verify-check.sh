#!/usr/bin/env bash
# Post-verification check hook for ui-reverse-engineering
# Enhanced: checks actual PASS/FAIL results, not just file existence

# Find the project's tmp/ref directory (most recently modified)
REF_DIR=""
NEWEST_TIME=0
for d in tmp/ref/*/; do
  [ -d "$d" ] || continue
  for marker in transition-spec.json component-map.json extracted.json; do
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

# If no ref dir, not a ui-re project — skip
[ -z "$REF_DIR" ] && exit 0

# Only warn on Bash commands that look like completion signals
TOOL_INPUT="${TOOL_INPUT:-}"
IS_COMPLETION=false
if echo "$TOOL_INPUT" | grep -qiE 'commit|done|complete|finish|merge|push|"looks good"|"all pass"'; then
  IS_COMPLETION=true
fi

[ "$IS_COMPLETION" = false ] && exit 0

# ── Check 1: Verification has been run ──
DIFF_COUNT=$(find "$REF_DIR/static/diff" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
HEALTH_FILE="$REF_DIR/layout-health.json"

if [ "$DIFF_COUNT" -lt 3 ] && [ ! -f "$HEALTH_FILE" ]; then
  VERIFY_SCRIPT=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/auto-verify.sh" ]; then
    VERIFY_SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/auto-verify.sh"
  else
    VERIFY_SCRIPT="$(find "$HOME/.claude/skills" -maxdepth 3 -name 'auto-verify.sh' 2>/dev/null | head -1)"
  fi
  [ -z "$VERIFY_SCRIPT" ] && VERIFY_SCRIPT="auto-verify.sh"

  echo ""
  echo "⚠️  UI-RE: Verification has NOT been run."
  echo "    Before declaring done, run:"
  echo "    bash \"$VERIFY_SCRIPT\" <session> <orig-url> <impl-url> $REF_DIR"
  echo ""
  exit 0
fi

# ── Check 2: Verification results are actually passing ──
# Look for batch-compare output and check for FAIL counts
COMPARE_LOG="$REF_DIR/batch-compare-result.txt"
if [ -f "$COMPARE_LOG" ]; then
  FAIL_COUNT=$(grep -c '❌' "$COMPARE_LOG" 2>/dev/null || echo "0")
  PASS_COUNT=$(grep -c '✅' "$COMPARE_LOG" 2>/dev/null || echo "0")
  FAIL_COUNT=$(echo "$FAIL_COUNT" | tr -d '[:space:]')
  PASS_COUNT=$(echo "$PASS_COUNT" | tr -d '[:space:]')
  
  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "⚠️  UI-RE: Verification ran but $FAIL_COUNT positions FAILED (only $PASS_COUNT passed)."
    echo "    Read diff images in $REF_DIR/static/diff/ to diagnose."
    echo "    DO NOT declare done with failing positions."
    echo ""
  fi
fi

# ── Check 3: Multi-state verification ──
# If there are click interactions, check if search/alternate views were also verified
INTERACTIONS_FILE="$REF_DIR/interactions-detected.json"
if [ -f "$INTERACTIONS_FILE" ]; then
  STATE_CHANGING=$(grep -c '"trigger"[[:space:]]*:[[:space:]]*"click"' "$INTERACTIONS_FILE" 2>/dev/null || echo "0")
  STATE_CHANGING=$(echo "$STATE_CHANGING" | tr -d '[:space:]')
  
  if [ "$STATE_CHANGING" -gt 0 ]; then
    # Check if any alternate state was captured
    ALT_STATE_CAPTURES=$(find "$REF_DIR" -name "*search*" -o -name "*active*" -o -name "*result*" -o -name "*click*" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$ALT_STATE_CAPTURES" -eq 0 ]; then
      echo ""
      echo "⚠️  UI-RE: $STATE_CHANGING click interactions exist but no alternate-state captures found."
      echo "    Did you verify the search/results/active view as well?"
      echo "    Click an element → screenshot → compare with original."
      echo ""
    fi
  fi
fi

# Always exit 0 — this is advisory, not blocking
exit 0

#!/usr/bin/env bash
# Post-verification check hook for ui-reverse-engineering
# Blocks declaring "done" if post-implement gate hasn't passed
# Install in settings.json as a reminder hook (non-blocking)
#
# This hook checks if auto-verify.sh has been run by looking for
# comparison results in the ref directory. If no verification has
# been run, it prints a warning.

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

# Check if verification has been run
# Look for batch-compare output (static/diff/ directory with files)
DIFF_COUNT=$(find "$REF_DIR/static/diff" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
HEALTH_FILE="$REF_DIR/layout-health.json"

if [ "$DIFF_COUNT" -lt 3 ] && [ ! -f "$HEALTH_FILE" ]; then
  # Find auto-verify.sh dynamically
  VERIFY_SCRIPT="$(find ~/.claude/skills -name 'auto-verify.sh' 2>/dev/null | head -1)"
  [ -z "$VERIFY_SCRIPT" ] && VERIFY_SCRIPT="$(find ~/Documents/ui-skills -name 'auto-verify.sh' 2>/dev/null | head -1)"
  [ -z "$VERIFY_SCRIPT" ] && VERIFY_SCRIPT="auto-verify.sh"

  echo ""
  echo "⚠️  UI Reverse Engineering: Verification has NOT been run yet."
  echo "    Before declaring any section 'done', run:"
  echo "    bash \"$VERIFY_SCRIPT\" <session> <orig-url> <impl-url> $REF_DIR"
  echo ""
fi

# Always exit 0 — this is advisory, not blocking
exit 0

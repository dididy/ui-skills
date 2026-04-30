#!/usr/bin/env bash
# ui-re-section-compare-gate.sh
# Stop hook — blocks Claude response if section-compare hasn't passed.
#
# Activation: only fires when a WIP marker exists (tmp/ref/<session>/.ui-re-active).
# Claude writes the marker at session start; section-compare.sh removes it on success.
# This prevents the Stop hook from blocking unrelated conversations in the same project.
#
# result.txt is written automatically by section-compare.sh — no manual pipe needed.

set -euo pipefail

# ── WIP marker guard: only enforce when a ui-re session is active ──
# REF_DIR is determined by the WIP marker itself, not by mtime of artifacts.
# This prevents cross-session confusion when multiple ui-re sessions are active.
#
# Project root priority:
#   1. $CLAUDE_PROJECT_DIR — set by Claude Code to the opened project directory
#   2. git rev-parse --show-toplevel — works for git repos
#   3. Walk up from $PWD looking for tmp/ref/ — avoids locking onto a nested subdir
# Never blindly use $PWD alone: hooks run from the CWD of the edited file,
# which may be a nested subdirectory (e.g. navercorp-clone/) with its own tmp/ref/.
_find_project_root() {
  # 1. Claude Code sets this env var to the project directory
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    echo "$CLAUDE_PROJECT_DIR"
    return
  fi
  # 2. Git root
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_root" ]; then
    echo "$git_root"
    return
  fi
  # 3. Walk up from $PWD, stop at the highest directory that has tmp/ref/
  local dir="$PWD"
  local best=""
  while [ "$dir" != "/" ]; do
    [ -d "$dir/tmp/ref" ] && best="$dir"
    dir=$(dirname "$dir")
  done
  [ -n "$best" ] && echo "$best" && return
  # 4. Fallback to $PWD
  echo "$PWD"
}

PROJECT_ROOT=$(_find_project_root)
SEARCH_ROOT="${PROJECT_ROOT}/tmp/ref"
[ -d "$SEARCH_ROOT" ] || exit 0

REF_DIR=""
ACTIVE_COUNT=0
for d in "$SEARCH_ROOT"/*/; do
  [ -d "$d" ] || continue
  if [ -f "${d}.ui-re-active" ]; then
    ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
    if [ -z "$REF_DIR" ]; then
      REF_DIR="$d"
    fi
  fi
done

# No WIP marker — not in an active ui-re session
[ -z "$REF_DIR" ] && exit 0

# Stale marker guard: if marker is older than 3 days, it is likely orphaned from a crashed session.
# Auto-remove and allow (user can re-activate by running run-pipeline.sh again).
MARKER_FILE="${REF_DIR}.ui-re-active"
MARKER_AGE_DAYS=0
if [ -f "$MARKER_FILE" ]; then
  MARKER_MTIME=$(stat -f %m "$MARKER_FILE" 2>/dev/null || stat -c %Y "$MARKER_FILE" 2>/dev/null || echo "0")
  NOW=$(date +%s)
  MARKER_AGE_DAYS=$(( (NOW - MARKER_MTIME) / 86400 ))
fi
if [ "$MARKER_AGE_DAYS" -ge 3 ]; then
  echo "ui-re-gate: Stale WIP marker (${MARKER_AGE_DAYS} days old) at $MARKER_FILE — auto-removing." >&2
  rm -f "$MARKER_FILE" 2>/dev/null || true
  # Re-check remaining markers
  REF_DIR=""
  ACTIVE_COUNT=0
  for d in "$SEARCH_ROOT"/*/; do
    [ -d "$d" ] || continue
    if [ -f "${d}.ui-re-active" ]; then
      ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
      [ -z "$REF_DIR" ] && REF_DIR="$d"
    fi
  done
  [ -z "$REF_DIR" ] && exit 0
fi

# Multiple active sessions: warn in block message (still enforce against first-found)
if [ "$ACTIVE_COUNT" -gt 1 ]; then
  # Log to stderr only (not stdout — stdout is parsed as JSON by Claude Code)
  echo "ui-re-gate: WARNING: $ACTIVE_COUNT concurrent WIP markers found. Enforcing against: $REF_DIR" >&2
fi

RESULT_FILE="${REF_DIR}sections/result.txt"
SECTION_DIR="${REF_DIR}sections"

# ── emit_block REASON — output Stop hook block JSON (correct schema) ──
# Claude Code Stop hook schema: top-level {"decision":"block","reason":"..."}
# hookSpecificOutput is NOT used for Stop events (only PreToolUse/UserPromptSubmit/PostToolUse).
emit_block() {
  local reason="$1"
  # Escape for JSON string value:
  # 1. Backslashes first (must be first to avoid double-escaping)
  # 2. Double-quotes
  # 3. Convert literal newlines → \n (awk prints each line with \n suffix, sed removes trailing)
  local escaped
  escaped=$(printf '%s' "$reason" \
    | sed 's/\\/\\\\/g' \
    | sed 's/"/\\"/g' \
    | sed 's/	/\\t/g' \
    | awk '{printf "%s\\n", $0}' \
    | sed 's/\\n$//')
  # Use printf with %s to avoid interpreting % in escaped content
  printf '%s\n' "{\"decision\":\"block\",\"reason\":\"${escaped}\"}"
}

# ── Gate 1: section-compare hasn't been run ──
if [ ! -f "$RESULT_FILE" ]; then
  # Check if sections dir exists at all
  if [ ! -d "$SECTION_DIR" ]; then
    emit_block "⛔ UI-RE Gate: section-compare.sh has NOT been run.

Run:
  bash skills/visual-debug/scripts/section-compare.sh \\
    <orig-url> <impl-url> <session> ${REF_DIR}

(result.txt is written automatically — no pipe needed)
All sections must PASS before finishing."
    exit 0
  fi
  # sections dir exists but no result.txt — run happened but output wasn't saved
  # Check diff images as proxy
  DIFF_COUNT=$({ find "$SECTION_DIR/diff" -name "*.png" 2>/dev/null || true; } | wc -l | tr -d '[:space:]')
  if [ "$DIFF_COUNT" -eq 0 ]; then
    emit_block "⛔ UI-RE Gate: section-compare.sh has NOT been run.

Run:
  bash ~/.claude/skills/visual-debug/scripts/section-compare.sh \\
    <orig-url> <impl-url> <session> ${REF_DIR}

All sections must PASS."
    exit 0
  fi
  # Has diff images — run happened but result not saved. Can't determine PASS/FAIL — allow.
  exit 0
fi

# ── Gate 2: Parse result.txt for FAIL/PASS counts ──
# Use precise patterns: table rows with ❌/✅ emoji, and the specific "⚠️ MISSING impl" marker.
# Avoid grepping for bare "MISSING" which can match section names containing that word.
FAIL_COUNT=$(grep -c '❌' "$RESULT_FILE" 2>/dev/null || echo "0")
PASS_COUNT=$(grep -c '✅' "$RESULT_FILE" 2>/dev/null || echo "0")
MISSING_COUNT=$(grep -c '⚠️ MISSING impl' "$RESULT_FILE" 2>/dev/null || echo "0")
FAIL_COUNT=$(echo "$FAIL_COUNT" | tr -d '[:space:]')
PASS_COUNT=$(echo "$PASS_COUNT" | tr -d '[:space:]')
MISSING_COUNT=$(echo "$MISSING_COUNT" | tr -d '[:space:]')

# Extract failing section names (first pipe-column = section name, skip numeric columns)
FAIL_SECTIONS=$(grep '❌' "$RESULT_FILE" 2>/dev/null | sed -n 's/^| \([^|]*\) |.*/\1/p' | sed 's/^ *//;s/ *$//' | paste -sd ',' - || echo "")
MISSING_SECTIONS=$(grep '⚠️ MISSING impl' "$RESULT_FILE" 2>/dev/null | sed -n 's/^| \([^|]*\) |.*/\1/p' | sed 's/^ *//;s/ *$//' | paste -sd ',' - || echo "")

if [ "$FAIL_COUNT" -gt 0 ] || [ "$MISSING_COUNT" -gt 0 ]; then
  MSG="⛔ UI-RE Gate: section-compare FAILED."
  if [ "$FAIL_COUNT" -gt 0 ]; then
    MSG="$MSG

${FAIL_COUNT} section(s) FAILED: ${FAIL_SECTIONS}
→ Read diff images in ${SECTION_DIR}/diff/
→ Fix issues and re-run section-compare.sh"
  fi
  if [ "$MISSING_COUNT" -gt 0 ]; then
    MSG="$MSG

${MISSING_COUNT} section(s) MISSING in impl: ${MISSING_SECTIONS}
→ Implement the missing sections"
  fi
  MSG="$MSG

All sections must PASS before finishing."
  emit_block "$MSG"
  exit 0
fi

# All passed
exit 0

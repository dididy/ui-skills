#!/usr/bin/env bash
set -euo pipefail
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

# ── Find ref dir: prefer WIP marker, fall back to mtime of marker files ──
# Project root priority: $CLAUDE_PROJECT_DIR → git root → walk-up → $PWD
# Never blindly use $PWD: hooks run from CWD of the edited file (may be a nested subdir).
_find_project_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    echo "$CLAUDE_PROJECT_DIR"; return
  fi
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_root" ]; then echo "$git_root"; return; fi
  # Walk-up: find highest directory containing tmp/ref/.
  # WARNING: In monorepos with multiple workspaces, this may find the wrong workspace.
  # Set $CLAUDE_PROJECT_DIR to the correct workspace root to avoid this.
  local dir="$PWD" best=""
  while [ "$dir" != "/" ]; do
    [ -d "$dir/tmp/ref" ] && best="$dir"
    dir=$(dirname "$dir")
  done
  if [ -n "$best" ]; then
    # Warn if we found multiple tmp/ref dirs during walk (monorepo risk)
    local ref_count
    ref_count=$(find "$best" -maxdepth 4 -name "tmp" -type d 2>/dev/null | wc -l | tr -d ' ')
    if [ "$ref_count" -gt 1 ]; then
      echo "ui-re-pre-generate: WARNING: multiple tmp/ dirs found under $best — set \$CLAUDE_PROJECT_DIR to the correct workspace to avoid monorepo confusion." >&2
    fi
    echo "$best"; return
  fi
  echo "$PWD"
}
PROJECT_ROOT=$(_find_project_root)
SEARCH_ROOT="${PROJECT_ROOT}/tmp/ref"
REF_DIR=""

# 1. Check for active WIP marker first (most reliable, avoids cross-session confusion)
if [ -d "$SEARCH_ROOT" ]; then
  for d in "$SEARCH_ROOT"/*/; do
    [ -d "$d" ] || continue
    if [ -f "${d}.ui-re-active" ]; then
      REF_DIR="$d"
      break
    fi
  done
fi

# 2. Fall back to mtime — ONLY for refs that have extracted.json (generation-ready state).
# This avoids picking stale/abandoned refs that only have partial extraction.
# Without extracted.json the gate would always fail anyway — so skip those refs entirely.
if [ -z "$REF_DIR" ] && [ -d "$SEARCH_ROOT" ]; then
  NEWEST_TIME=0
  for d in "$SEARCH_ROOT"/*/; do
    [ -d "$d" ] || continue
    # Only consider refs with extracted.json — partial extractions are not generation-ready
    [ -f "${d}extracted.json" ] || continue
    MOD_TIME=$(stat -f %m "${d}extracted.json" 2>/dev/null || stat -c %Y "${d}extracted.json" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$NEWEST_TIME" ]; then
      NEWEST_TIME="$MOD_TIME"
      REF_DIR="$d"
    fi
  done
fi

# No ref dir — not a ui-reverse-engineering project (or no generation-ready ref exists)
[ -z "$REF_DIR" ] && exit 0

# ── Run pre-generate gate ──
# Search order (most specific → broadest):
# 1. $CLAUDE_PLUGIN_ROOT/scripts  — explicitly configured plugin root
# 2. Hook script's own directory → ../../scripts (relative to hooks/ dir)
# 3. find in ~/.claude/skills for validate-gate.sh (catches any symlink layout)
# 4. $PROJECT_ROOT/scripts (fallback — unlikely but safe)
GATE_SCRIPT=""
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
SEARCH_DIRS=()
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && SEARCH_DIRS+=("$CLAUDE_PLUGIN_ROOT/scripts")
# Relative to hooks/ → ../scripts (works for both real path and symlink resolution)
SEARCH_DIRS+=("$HOOK_DIR/../scripts")
# find-based fallback: locate validate-gate.sh anywhere under ~/.claude/skills
FOUND_VIA_FIND=$({ find "$HOME/.claude/skills" -maxdepth 5 -name 'validate-gate.sh' 2>/dev/null || true; } | head -1)
[ -n "$FOUND_VIA_FIND" ] && SEARCH_DIRS+=("$(dirname "$FOUND_VIA_FIND")")
SEARCH_DIRS+=("$PROJECT_ROOT/scripts")
for search_dir in "${SEARCH_DIRS[@]}"; do
  if [ -f "$search_dir/validate-gate.sh" ]; then
    GATE_SCRIPT="$search_dir/validate-gate.sh"
    break
  fi
done
if [ -z "$GATE_SCRIPT" ]; then
  # Gate script not found — warn to stderr and allow (fail-open is better than silent skip)
  echo "ui-re-pre-generate: WARNING: validate-gate.sh not found in any search path. Gate skipped." >&2
  echo "  Searched: ${SEARCH_DIRS[*]}" >&2
  exit 0
fi

RESULT_FILE=$(mktemp -t ui-re-gate-result.XXXXXX)
trap 'rm -f "$RESULT_FILE"' EXIT
GATE_EXIT=0; bash "$GATE_SCRIPT" "$REF_DIR" pre-generate > "$RESULT_FILE" 2>&1 || GATE_EXIT=$?

if [ "$GATE_EXIT" -ne 0 ]; then
  STRIPPED=$(sed 's/\x1b\[[0-9;]*m//g' "$RESULT_FILE")
  # Count failed checks (both MISSING and empty-file cases)
  MISSING_COUNT=$(echo "$STRIPPED" | grep -c '✗' 2>/dev/null || echo "0")
  MISSING_COUNT=$(echo "$MISSING_COUNT" | tr -d '[:space:]')

  # Always deny on non-zero gate exit — even if grep missed the ✗ symbols
  # (e.g. encoding issues on some terminals). Fall back to generic message.
  if [ "$MISSING_COUNT" -gt 0 ]; then
    MISSING_LIST=$(echo "$STRIPPED" | grep '✗' | head -8 | sed 's/.*✗ //;s/ (.*//;s/ —.*//' | paste -s -d ',' /dev/stdin)
    REASON="UI Reverse Engineering: extraction incomplete ($MISSING_COUNT artifacts missing). Missing: $MISSING_LIST. Complete Phase 2 before writing components."
  else
    REASON="UI Reverse Engineering: pre-generate gate FAILED. Run: bash \"\$PLUGIN_ROOT/scripts/validate-gate.sh\" tmp/ref/<component> pre-generate"
  fi
  # Escape REASON for safe JSON string embedding (backslash first, then quotes, then newlines)
  REASON_ESC=$(printf '%s' "$REASON" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
  cat <<HOOKJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$REASON_ESC"
  }
}
HOOKJSON
  exit 0
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
    STATE_EXTRACTIONS=$({ find "$REF_DIR" -name "styles-*.json" -o -name "structure-*.json" 2>/dev/null || true; } | wc -l | tr -d '[:space:]')
    
    # Also check if transition-spec.json documents the state changes
    SPEC_FILE="$REF_DIR/transition-spec.json"
    HAS_STATE_DOCS=0
    if [ -f "$SPEC_FILE" ]; then
      HAS_STATE_DOCS=$(grep -c '"visual"' "$SPEC_FILE" 2>/dev/null || echo "0")
      HAS_STATE_DOCS=$(echo "$HAS_STATE_DOCS" | tr -d '[:space:]')
    fi

    if [ "$STATE_EXTRACTIONS" -eq 0 ] && [ "$HAS_STATE_DOCS" -eq 0 ]; then
      # Warn but don't block — redirect to stderr so Claude Code doesn't parse it as hook JSON
      echo "" >&2
      echo "⚠️  UI-RE: $STATE_CHANGING click interactions found but no per-state extraction." >&2
      echo "    Consider extracting styles/DOM for each view state:" >&2
      echo "    - Click the element in agent-browser" >&2
      echo "    - Extract getComputedStyle for the new state" >&2
      echo "    - Save as styles-<state>.json, structure-<state>.json" >&2
      echo "" >&2
    fi
  fi
fi

# ── Auto-activate Stop gate WIP marker ──
# Gate passed: first allowed component write activates the Stop gate automatically.
# Claude never needs to manually `touch .ui-re-active` — it happens here.
# section-compare.sh removes the marker on all-PASS result.
if touch "${REF_DIR}.ui-re-active" 2>/dev/null; then
  # Print to stderr so Claude Code shows it in the tool result without affecting hook JSON output.
  # This makes the Stop gate activation visible — LLM knows section-compare.sh is now required.
  echo "⚑  UI-RE Stop gate ACTIVATED: section-compare.sh must pass before finishing." >&2
  echo "   Run: bash ~/.claude/skills/visual-debug/scripts/section-compare.sh <orig> <impl> <session> $(dirname "${REF_DIR%/}")/$(basename "${REF_DIR%/}")" >&2
fi

exit 0

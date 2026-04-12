#!/usr/bin/env bash
# run-pipeline.sh — Orchestrate the full ui-reverse-engineering pipeline
# Usage: bash run-pipeline.sh <url> <component-name> <session>
#
# This script enforces the correct order of operations by:
# 1. Running each step's gate BEFORE allowing the next step
# 2. Printing exactly what the agent should do next
# 3. Refusing to advance if prerequisites are missing
#
# The agent calls this script at each step to get instructions.
# Usage pattern in conversation:
#   bash "$PLUGIN_ROOT/scripts/run-pipeline.sh" <url> <name> <session> status
#   bash "$PLUGIN_ROOT/scripts/run-pipeline.sh" <url> <name> <session> next

set -euo pipefail

URL="${1:?Usage: run-pipeline.sh <url> <component-name> <session> <command>}"
NAME="${2:?}"
SESSION="${3:?}"
CMD="${4:-status}"

DIR="tmp/ref/$NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Determine current phase ──
get_phase() {
  # Phase 0: No extraction started
  [ ! -d "$DIR" ] && echo "0-init" && return

  # Phase 1: Capture
  [ ! -f "$DIR/structure.json" ] && echo "1-capture" && return

  # Phase 2: Extraction
  [ ! -f "$DIR/transition-spec.json" ] && echo "2-extract" && return

  # Phase 2.5: CSS + Assets
  local css_count=$(find "$DIR/css" -name "*.css" 2>/dev/null | wc -l | tr -d ' ')
  [ "$css_count" -lt 1 ] && echo "2.5-css" && return

  # Phase 2.6: CSS variables
  [ ! -f "$DIR/css/variables.txt" ] && echo "2.6-vars" && return

  # Phase 3: Pre-generation gate
  if ! bash "$SCRIPT_DIR/validate-gate.sh" "$DIR" pre-generate >/dev/null 2>&1; then
    echo "3-pregen" && return
  fi

  # Phase 4: Generation (check if components exist)
  local comp_count=$(find . -path "*/components/*.tsx" -newer "$DIR/transition-spec.json" 2>/dev/null | wc -l | tr -d ' ')
  [ "$comp_count" -lt 3 ] && echo "4-generate" && return

  # Phase 5: Verification
  echo "5-verify"
}

PHASE=$(get_phase)

case "$CMD" in
  status)
    echo ""
    echo -e "${CYAN}═══ UI Reverse Engineering Pipeline ═══${NC}"
    echo -e "URL:       $URL"
    echo -e "Component: $NAME"
    echo -e "Directory: $DIR"
    echo -e "Phase:     ${GREEN}$PHASE${NC}"
    echo ""

    case "$PHASE" in
      0-init)
        echo -e "${YELLOW}→ Start: Create directory and run /ui-capture${NC}"
        ;;
      1-capture)
        echo -e "${YELLOW}→ Next: Run /ui-capture $URL${NC}"
        echo "  Then: Read dom-extraction.md, execute Steps 1-2.5"
        echo "  Then: Read interaction-detection.md, download bundles, create transition-spec.json"
        ;;
      2-extract)
        echo -e "${YELLOW}→ Next: Download bundles, create transition-spec.json${NC}"
        echo "  Missing: transition-spec.json"
        ;;
      2.5-css)
        echo -e "${YELLOW}→ Next: Download original CSS files${NC}"
        echo "  Read dom-extraction.md Step 2.5 'Download original CSS files' section"
        ;;
      2.6-vars)
        echo -e "${YELLOW}→ Next: Extract CSS variables from downloaded CSS${NC}"
        echo "  Run: cat $DIR/css/*.css | grep -oE '\-\-[a-zA-Z0-9_-]+:\s*[^;}]+' | sed 's/}.*//' | sort -u > $DIR/css/variables.txt"
        ;;
      3-pregen)
        echo -e "${YELLOW}→ Next: Fix pre-generation gate failures${NC}"
        bash "$SCRIPT_DIR/validate-gate.sh" "$DIR" pre-generate 2>&1 | grep -E '❌|⚠️' | head -10
        ;;
      4-generate)
        echo -e "${YELLOW}→ Next: Generate components${NC}"
        echo "  Read site-detection.md → choose CSS-First or Extract-Values"
        echo "  Read component-generation.md → CSS-First generation rules"
        echo "  Read transition-implementation.md → implement ALL transitions"
        echo ""
        echo "  Transitions to implement:"
        if [ -f "$DIR/transition-spec.json" ]; then
          python3 -c "
import json
d = json.load(open('$DIR/transition-spec.json'))
for t in d.get('transitions', []):
    name = t.get('name', t.get('id', '?'))
    trigger = t.get('trigger', '?')
    print(f'    □ {name} ({trigger})')
" 2>/dev/null
        fi
        ;;
      5-verify)
        echo -e "${YELLOW}→ Next: Visual verification${NC}"
        echo "  Read visual-verification.md"
        echo "  Run getComputedStyle comparison (not visual judgment)"
        ;;
    esac
    echo ""
    ;;

  next)
    # Print the exact command(s) to run for the current phase
    case "$PHASE" in
      0-init)
        echo "mkdir -p $DIR"
        echo "# Run /ui-capture $URL"
        ;;
      1-capture)
        echo "# Read dom-extraction.md and execute Steps 1-2.5"
        ;;
      2-extract)
        echo "# Read interaction-detection.md Step 6"
        echo "# Download ALL JS bundles"
        echo "# Create transition-spec.json"
        ;;
      2.5-css)
        echo "# Download original CSS files:"
        echo "agent-browser --session $SESSION eval \"(() => JSON.stringify(performance.getEntriesByType('resource').filter(e=>e.name.match(/\\.css(\\?|\$)/i)).map(e=>e.name)))()\""
        echo "# curl each to $DIR/css/"
        ;;
      2.6-vars)
        echo "cat $DIR/css/*.css | grep -oE '\\-\\-[a-zA-Z0-9_-]+:\\s*[^;}]+' | sed 's/}.*//' | sort -u > $DIR/css/variables.txt"
        ;;
      3-pregen)
        echo "bash $SCRIPT_DIR/validate-gate.sh $DIR pre-generate"
        ;;
      4-generate)
        echo "# Read site-detection.md + component-generation.md + transition-implementation.md"
        echo "# Generate components with original CSS classes + transitions"
        ;;
      5-verify)
        echo "bash $SCRIPT_DIR/validate-gate.sh $DIR post-implement"
        ;;
    esac
    ;;

  gate)
    # Run the appropriate gate for current phase
    case "$PHASE" in
      3-pregen|4-generate)
        bash "$SCRIPT_DIR/validate-gate.sh" "$DIR" pre-generate
        ;;
      5-verify)
        bash "$SCRIPT_DIR/validate-gate.sh" "$DIR" post-implement
        ;;
      *)
        echo "No gate for phase $PHASE"
        ;;
    esac
    ;;

  *)
    echo "Unknown command: $CMD"
    echo "Usage: run-pipeline.sh <url> <name> <session> {status|next|gate}"
    exit 1
    ;;
esac

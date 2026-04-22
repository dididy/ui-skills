#!/usr/bin/env bash
# run-pipeline.sh — Determine current pipeline phase and tell the LLM what to do next
#
# Usage: bash run-pipeline.sh <url> <component-name> <session> status
#
# This is the FIRST command the LLM must run. It checks which artifacts exist
# and reports exactly which phase/step to execute next. The LLM should follow
# its output instead of guessing where it is in the pipeline.

set -uo pipefail

URL="${1:?Usage: run-pipeline.sh <url> <component-name> <session> status}"
COMPONENT="${2:?}"
SESSION="${3:?}"
ACTION="${4:-status}"

REF_DIR="tmp/ref/$COMPONENT"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

phase_status() {
  local label="$1"
  shift
  if "$@" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $label"
    return 0
  else
    echo -e "  ${YELLOW}○${NC} $label"
    return 1
  fi
}

# Helper: check file exists
has_file() { [ -f "$1" ]; }

# Helper: check dir has at least N files matching pattern
has_files() {
  local dir="$1" pattern="$2" min="$3"
  [ -d "$dir" ] && [ "$(find "$dir" -name "$pattern" 2>/dev/null | wc -l | tr -d ' ')" -ge "$min" ]
}

echo -e "${BOLD}Pipeline Status: $COMPONENT${NC}"
echo "URL: $URL"
echo "Session: $SESSION"
echo "Ref dir: $REF_DIR"
echo ""

# Track first incomplete phase
NEXT_PHASE=""
NEXT_STEP=""

# ── Phase 0: Prior data ──
echo -e "${BOLD}Phase 0 — Prior Data${NC}"
if [ -f "$REF_DIR/transition-spec.json" ]; then
  echo -e "  ${GREEN}✓${NC} transition-spec.json exists — READ THIS FIRST"
else
  echo -e "  ${YELLOW}○${NC} No prior transition-spec.json"
fi
if [ -f "$REF_DIR/extracted.json" ]; then
  echo -e "  ${GREEN}✓${NC} extracted.json exists"
fi
echo ""

# ── Phase 1: Reference capture ──
echo -e "${BOLD}Phase 1 — Reference Capture${NC}"
HAS_REF=false
if phase_status "static/ref/ screenshots (≥5 files)" has_files "$REF_DIR/static/ref" "*.png" 5; then
  HAS_REF=true
fi
phase_status "scroll-video/ref/ video" has_files "$REF_DIR/scroll-video/ref" "*.webm" 1 || true
if [ "$HAS_REF" = false ] && [ -z "$NEXT_PHASE" ]; then
  NEXT_PHASE="1"
  NEXT_STEP="Invoke /ui-capture $URL. See SKILL.md Phase 1."
fi
echo ""

# ── Phase 2: Extraction ──
echo -e "${BOLD}Phase 2 — Extraction${NC}"

# Step 1-2: DOM + section enumeration
phase_status "Step 1-2: structure.json + section-map.json" test -f "$REF_DIR/structure.json" -a -f "$REF_DIR/section-map.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read dom-extraction.md → run Step 2 (structure) + semantic section enumeration (section-map)."
}

# Step 2.5: Head/assets/fonts
phase_status "Step 2.5: head.json + fonts.json" test -f "$REF_DIR/head.json" -a -f "$REF_DIR/fonts.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read dom-extraction.md Step 2.5 → extract head, assets, fonts."
}

# Step 3: Styles
phase_status "Step 3: styles.json + design-bundles" test -f "$REF_DIR/styles.json" -a -f "$REF_DIR/design-bundles.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read style-extraction.md → extract computed styles."
}

# Step 4: Responsive
phase_status "Step 4: detected-breakpoints.json" has_file "$REF_DIR/detected-breakpoints.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read responsive-detection.md → sweep viewports."
}

# Step 5: Interactions
phase_status "Step 5: interactions-detected.json" has_file "$REF_DIR/interactions-detected.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read interaction-detection.md → detect interactions."
}

# Step 5c: Bundles
phase_status "Step 5c: bundles/ (≥3 JS files)" has_files "$REF_DIR/bundles" "*.js" 3 || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read interaction-detection.md Step 6 → download ALL JS chunks. Gate: bundle"
}

# Step 5d: Spec
phase_status "Step 5d: transition-spec.json" has_file "$REF_DIR/transition-spec.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read interaction-detection.md Step 6b → write transition-spec.json. Gate: spec"
}

# Step 6: Animation
phase_status "Step 6: animation-spec.json" has_file "$REF_DIR/animation-spec.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read animation-detection.md → 3 phases: idle, scroll, per-element."
}

# Step 6b: Assembled extraction
phase_status "Step 6b: extracted.json (assembled)" has_file "$REF_DIR/extracted.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Assemble extracted.json from all artifacts."
}
echo ""

# ── Phase 3: Generation ──
echo -e "${BOLD}Phase 3 — Generation${NC}"
# Check for component files in the app directory
APP_DIR=""
for d in apps/*/src/components; do
  if [ -d "$d" ]; then
    APP_DIR="$(dirname "$(dirname "$d")")"
    break
  fi
done
if [ -n "$APP_DIR" ]; then
  COMP_COUNT=$(find "$APP_DIR/src/components" -name "*.tsx" 2>/dev/null | wc -l | tr -d ' ')
  phase_status "Components generated ($COMP_COUNT .tsx files)" test "$COMP_COUNT" -ge 5 || {
    [ -z "$NEXT_PHASE" ] && NEXT_PHASE="3" && NEXT_STEP="Read component-generation.md → generate from extracted.json. Gate: pre-generate"
  }
else
  echo -e "  ${YELLOW}○${NC} No app directory found"
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="3" && NEXT_STEP="Scaffold app, then read component-generation.md."
fi
echo ""

# ── Phase 4: Verification ──
echo -e "${BOLD}Phase 4 — Verification${NC}"
phase_status "impl screenshots captured" has_files "$REF_DIR/static/impl" "*.png" 5 || true
phase_status "diff images generated" has_files "$REF_DIR/static/diff" "*.png" 1 || true
if [ -z "$NEXT_PHASE" ]; then
  NEXT_PHASE="4"
  NEXT_STEP="Run auto-verify.sh. Gate: post-implement"
fi
echo ""

# ── Next action ──
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -n "$NEXT_PHASE" ]; then
  echo -e "${BOLD}NEXT: Phase $NEXT_PHASE${NC}"
  echo -e "${YELLOW}→ $NEXT_STEP${NC}"

  # Run the gate for the current phase to show exactly what's missing
  if [ "$NEXT_PHASE" = "2" ] && [ -d "$REF_DIR" ]; then
    echo ""
    echo "Running extraction gate check:"
    bash "$SCRIPT_DIR/validate-gate.sh" "$REF_DIR" extraction 2>/dev/null || true
  fi
else
  echo -e "${GREEN}All phases complete!${NC}"
fi

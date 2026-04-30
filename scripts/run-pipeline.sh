#!/usr/bin/env bash
# run-pipeline.sh — Determine current pipeline phase and tell the LLM what to do next
#
# Usage: bash run-pipeline.sh <url> <component-name> <session> status
#
# This is the FIRST command the LLM must run. It checks which artifacts exist
# and reports exactly which phase/step to execute next. The LLM should follow
# its output instead of guessing where it is in the pipeline.

set -euo pipefail

# ── Dependency check ──
DOCTOR_FAIL=0
for cmd in agent-browser ffmpeg jq; do
  command -v "$cmd" &>/dev/null || { echo -e "\033[0;31m✗\033[0m Missing: $cmd"; DOCTOR_FAIL=1; }
done
for cmd in compare identify; do
  command -v "$cmd" &>/dev/null || { echo -e "\033[0;31m✗\033[0m Missing: $cmd (brew install imagemagick)"; DOCTOR_FAIL=1; }
done
for cmd in python3 curl bc; do
  command -v "$cmd" &>/dev/null || { echo -e "\033[0;31m✗\033[0m Missing: $cmd (brew install $cmd)"; DOCTOR_FAIL=1; }
done
command -v dssim &>/dev/null || echo -e "\033[0;33m⚠\033[0m Optional: dssim (brew install dssim)"
if [ "$DOCTOR_FAIL" -eq 1 ]; then
  echo "  brew install imagemagick ffmpeg dssim && npm i -g @anthropic-ai/agent-browser"
  exit 2
fi

URL="${1:?Usage: run-pipeline.sh <url> <component-name> <session> status}"
COMPONENT="${2:?}"
SESSION="${3:?}"
ACTION="${4:-status}"

# Resolve project root (same priority as hooks: CLAUDE_PROJECT_DIR → git → walk-up → PWD)
_find_project_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    echo "$CLAUDE_PROJECT_DIR"; return
  fi
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_root" ]; then echo "$git_root"; return; fi
  local dir="$PWD" best=""
  while [ "$dir" != "/" ]; do
    [ -d "$dir/tmp/ref" ] && best="$dir"
    dir=$(dirname "$dir")
  done
  [ -n "$best" ] && echo "$best" && return
  echo "$PWD"
}
PROJECT_ROOT=$(_find_project_root)
REF_DIR="$PROJECT_ROOT/tmp/ref/$COMPONENT"
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

# ── Phase 0A: Render type detection (runs once, saves canvas-webgl-detection.json) ──
# Detecting Canvas/WebGL early prevents hours of CSS-based replication attempts on invisible sources.
echo -e "${BOLD}Phase 0A — Render Type Detection${NC}"
CANVAS_DETECT="$REF_DIR/canvas-webgl-detection.json"
if [ -f "$CANVAS_DETECT" ]; then
  # Use env var to pass path — avoids single-quote breakage in python inline string
  CANVAS_TYPE=$(DETECT_PATH="$CANVAS_DETECT" python3 -c "import json,os; d=json.load(open(os.environ['DETECT_PATH'])); print(d.get('primaryRenderType','unknown'))" 2>/dev/null || echo "unknown")
  HAS_CANVAS=$(DETECT_PATH="$CANVAS_DETECT" python3 -c "import json,os; d=json.load(open(os.environ['DETECT_PATH'])); print(d.get('hasCanvas', False))" 2>/dev/null || echo "False")
  HAS_WEBGL=$(DETECT_PATH="$CANVAS_DETECT" python3 -c "import json,os; d=json.load(open(os.environ['DETECT_PATH'])); print(d.get('hasWebGL', False))" 2>/dev/null || echo "False")
  echo -e "  ${GREEN}✓${NC} Render type: $CANVAS_TYPE (canvas=$HAS_CANVAS, webgl=$HAS_WEBGL)"
  if [ "$HAS_CANVAS" = "True" ] || [ "$HAS_WEBGL" = "True" ]; then
    echo -e "  ${YELLOW}⚠${NC}  Canvas/WebGL detected — CSS replication will be APPROXIMATE."
    echo -e "       Read canvas-webgl-extraction.md before Phase 2 extraction."
    echo -e "       Add NEXT_PUBLIC_SPLASH_TEST=true / animation debug panel for iterating."
  fi
else
  echo -e "  ${YELLOW}○${NC} canvas-webgl-detection.json missing — run detection FIRST (prevents wasted CSS work on Canvas sites):"
  echo -e "     agent-browser --session $SESSION open $URL"
  echo -e "     agent-browser --session $SESSION eval \\"
  echo -e "       \"(() => ({ hasCanvas: !!document.querySelector('canvas'),"
  echo -e "         hasWebGL: (() => { try { return !!document.createElement('canvas').getContext('webgl'); } catch(e) { return false; } })(),"
  echo -e "         canvasCount: document.querySelectorAll('canvas').length,"
  echo -e "         primaryRenderType: document.querySelector('canvas') ? 'canvas' : 'dom' }))()\" \\"
  echo -e "     > $CANVAS_DETECT"
  # Set NEXT_PHASE only if REF_DIR doesn't exist yet (brand-new session)
  # If ref dir already has data, canvas detection was merely skipped — warn but don't block.
  if [ ! -d "$REF_DIR" ]; then
    [ -z "$NEXT_PHASE" ] && NEXT_PHASE="0A" && NEXT_STEP="Run canvas/WebGL detection above, then re-run status."
  fi
fi
echo ""

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
phase_status "transitions/ref/ videos" has_files "$REF_DIR/transitions/ref" "*.webm" 1 || true
phase_status "regions.json" has_file "$REF_DIR/regions.json" || true
if [ "$HAS_REF" = false ] && [ -z "$NEXT_PHASE" ]; then
  NEXT_PHASE="1"
  NEXT_STEP="Invoke /ui-capture $URL. See SKILL.md Phase 1."
fi
echo ""

# ── Phase 2: Extraction ──
# Skip phase 2 checks entirely if Phase 1 isn't done — avoids misleading "Phase 2 next" message
# when screenshots haven't even been captured yet.
if [ "$HAS_REF" = false ]; then
  echo -e "${BOLD}Phase 2 — Extraction${NC}"
  echo -e "  ${YELLOW}○${NC} (skipped — complete Phase 1 first)"
  echo ""
  # Jump to next action output
else
echo -e "${BOLD}Phase 2 — Extraction${NC}"

# Step 1-2: DOM + section enumeration
phase_status "Step 1-2: structure.json + section-map.json" test -f "$REF_DIR/structure.json" -a -f "$REF_DIR/section-map.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read dom-extraction.md → run Step 2 (structure) + semantic section enumeration (section-map)."
  true
}

# Step 2.5: Head/assets/fonts
phase_status "Step 2.5: head.json + fonts.json" test -f "$REF_DIR/head.json" -a -f "$REF_DIR/fonts.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read asset-extraction.md → extract head, assets, fonts."
  true
}

# Step 2.5b: SVG-as-text detection
phase_status "Step 2.5b: svg-text-elements.json" has_file "$REF_DIR/svg-text-elements.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read dom-extraction.md Step 2.5b → SVG-as-text detection."
  true
}

# Step 2.6: Animation init styles
phase_status "Step 2.6: animation-init-styles.json" has_file "$REF_DIR/animation-init-styles.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read dom-extraction.md Steps 2.6a-b → extract animation init styles."
  true
}

# Step 3: Styles
phase_status "Step 3: styles.json + design-bundles" test -f "$REF_DIR/styles.json" -a -f "$REF_DIR/design-bundles.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read style-extraction.md → extract computed styles."
  true
}

# Step 4: Responsive
phase_status "Step 4: detected-breakpoints.json" has_file "$REF_DIR/detected-breakpoints.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read responsive-detection.md → sweep viewports."
  true
}
phase_status "Step 4-C2: sizing-expressions.json" has_file "$REF_DIR/responsive/sizing-expressions.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read responsive-detection.md Step 4-C2 → multi-viewport element sizing comparison."
  true
}

# Step 5: Interactions
phase_status "Step 5: interactions-detected.json" has_file "$REF_DIR/interactions-detected.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read interaction-detection.md → detect interactions."
  true
}

# Step 5c: Bundles
phase_status "Step 5c: bundles/ (≥3 JS files)" has_files "$REF_DIR/bundles" "*.js" 3 || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read bundle-analysis.md → download ALL JS chunks, detect scroll engine. Gate: bundle"
  true
}
phase_status "Step 5c: external-sdks.json" has_file "$REF_DIR/external-sdks.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read bundle-analysis.md → detect external SDKs (GSAP/Lenis/Framer). Write external-sdks.json ({} if none)."
  true
}

# Step 5d: Spec + hover artifacts
phase_status "Step 5d: transition-spec.json" has_file "$REF_DIR/transition-spec.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read bundle-analysis.md + transition-spec-rules.md → write transition-spec.json. Gate: spec"
  true
}
phase_status "Step 5d-2b: hover-css-rules.json" has_file "$REF_DIR/hover-css-rules.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read interaction-detection.md Step 5d-2b → extract ALL :hover CSS rules from live page."
  true
}

# Step 6b: Assembled extraction
phase_status "Step 6b: extracted.json (assembled)" has_file "$REF_DIR/extracted.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Assemble extracted.json from all artifacts."
  true
}

# ── Staleness quick-check (runs inline, not just at pre-generate gate) ──
# If any parent artifact is newer than extracted.json, warn early so the LLM
# doesn't waste time generating code against stale data.
if [ -f "$REF_DIR/extracted.json" ]; then
  EXTRACTED_MTIME=$(stat -f %m "$REF_DIR/extracted.json" 2>/dev/null || stat -c %Y "$REF_DIR/extracted.json" 2>/dev/null || echo "0")
  STALE_PARENTS=""
  for _p in structure.json styles.json component-map.json interactions-detected.json hover-css-rules.json transition-coverage.json; do
    if [ -f "$REF_DIR/$_p" ]; then
      _PMTIME=$(stat -f %m "$REF_DIR/$_p" 2>/dev/null || stat -c %Y "$REF_DIR/$_p" 2>/dev/null || echo "0")
      if [ "$_PMTIME" -gt "$EXTRACTED_MTIME" ]; then
        STALE_PARENTS="${STALE_PARENTS} $_p"
      fi
    fi
  done
  if [ -n "$STALE_PARENTS" ]; then
    echo -e "  ${YELLOW}⚠${NC}  extracted.json is STALE — newer than:${STALE_PARENTS}"
    echo -e "     Re-run Step 6b (assemble) before generating code."
  fi
fi

# Step 6c: Section audit
phase_status "Step 6c: component-map.json (section audit)" has_file "$REF_DIR/component-map.json" || {
  [ -z "$NEXT_PHASE" ] && NEXT_PHASE="2" && NEXT_STEP="Read section-audit.md → six-stage audit → component-map.json. Gate: pre-generate"
  true
}
echo ""
fi  # end: HAS_REF guard

# ── Auto-gate: run pre-generate check when entering Phase 3 ──
if [ -z "$NEXT_PHASE" ] && [ -d "$REF_DIR" ]; then
  echo -e "${BOLD}Pre-generate gate (auto)${NC}"
  if ! bash "$SCRIPT_DIR/validate-gate.sh" "$REF_DIR" pre-generate; then
    NEXT_PHASE="2"
    NEXT_STEP="Pre-generate gate FAILED. Fix missing artifacts before code generation."
  fi
  echo ""
fi

# ── Phase 3: Generation ──
echo -e "${BOLD}Phase 3 — Generation${NC}"
# Check for component files in the app directory (search from project root)
# Prefer component name match to avoid picking wrong workspace in monorepos.
APP_DIR=""
# Priority 1: component-name-specific app dir (monorepo)
for d in \
  "$PROJECT_ROOT/apps/$COMPONENT/src/components" \
  "$PROJECT_ROOT/apps/$COMPONENT/src" \
  "$PROJECT_ROOT/apps/$COMPONENT/app"; do
  if [ -d "$d" ]; then
    APP_DIR="$(cd "$d/../.." 2>/dev/null && pwd || dirname "$(dirname "$d")")"
    break
  fi
done
# Priority 2: flat project layout
if [ -z "$APP_DIR" ]; then
  for d in "$PROJECT_ROOT/src/components" "$PROJECT_ROOT/app" "$PROJECT_ROOT/src"; do
    if [ -d "$d" ]; then
      APP_DIR="$(cd "$d/.." 2>/dev/null && pwd || dirname "$d")"
      break
    fi
  done
fi
# Priority 3: first match in monorepo (fallback — may be wrong workspace)
if [ -z "$APP_DIR" ]; then
  for d in "$PROJECT_ROOT/apps/"*/src/components; do
    if [ -d "$d" ]; then
      APP_DIR="$(dirname "$(dirname "$d")")"
      echo -e "  ${YELLOW}⚠${NC}  Monorepo: using first app dir found. Set CLAUDE_PROJECT_DIR to target workspace."
      break
    fi
  done
fi
if [ -n "$APP_DIR" ]; then
  COMP_COUNT=$(find "$APP_DIR/src/components" "$APP_DIR/src/app" "$APP_DIR/app" -name "*.tsx" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  phase_status "Components generated ($COMP_COUNT .tsx files)" test "$COMP_COUNT" -ge 5 || {
    [ -z "$NEXT_PHASE" ] && NEXT_PHASE="3" && NEXT_STEP="Read component-generation.md → generate from extracted.json. Gate: pre-generate"
    true
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

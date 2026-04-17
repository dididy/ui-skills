#!/usr/bin/env bash
# validate-gate.sh — Enforces extraction gates before proceeding
# Usage: bash scripts/validate-gate.sh <component-dir> <gate-name>
# Example: bash scripts/validate-gate.sh tmp/ref/9to5studio bundle
#          bash scripts/validate-gate.sh tmp/ref/9to5studio spec
#          bash scripts/validate-gate.sh tmp/ref/9to5studio pre-generate
#          bash scripts/validate-gate.sh tmp/ref/9to5studio post-implement

set -euo pipefail

DIR="${1:?Usage: validate-gate.sh <component-dir> <gate-name>}"
GATE="${2:?Usage: validate-gate.sh <component-dir> <gate-name>}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAIL=0

# ── JSON output ──
START_TIME=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000))")
MISSING_FILES="[]"

record_missing() {
  MISSING_FILES=$(echo "$MISSING_FILES" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d.append('$1')
print(json.dumps(d))
" 2>/dev/null || echo "$MISSING_FILES")
}

check_file() {
  local file="$1"
  local min_bytes="${2:-10}"
  local desc="${3:-}"

  if [ ! -f "$DIR/$file" ]; then
    echo -e "${RED}❌ MISSING${NC} $file${desc:+ — $desc}" >&2
    FAIL=$((FAIL + 1))
    record_missing "$file"
    return 1
  fi

  local size
  size=$(wc -c < "$DIR/$file" | tr -d ' ')
  if [ "$size" -lt "$min_bytes" ]; then
    echo -e "${RED}❌ TOO SMALL${NC} $file (${size}B < ${min_bytes}B)${desc:+ — $desc}" >&2
    FAIL=$((FAIL + 1))
    record_missing "$file"
    return 1
  fi

  echo -e "${GREEN}✅${NC} $file (${size}B)" >&2
  return 0
}

check_json_key() {
  local file="$1"
  local key="$2"
  local desc="${3:-}"

  if [ ! -f "$DIR/$file" ]; then
    echo -e "${RED}❌ MISSING${NC} $file${desc:+ — $desc}" >&2
    FAIL=$((FAIL + 1))
    record_missing "$file"
    return 1
  fi

  if ! jq -e "$key" "$DIR/$file" > /dev/null 2>&1; then
    echo -e "${RED}❌ KEY MISSING${NC} $file → $key${desc:+ — $desc}" >&2
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo -e "${GREEN}✅${NC} $file has $key" >&2
  return 0
}

check_glob_count() {
  local pattern="$1"
  local min_count="$2"
  local desc="${3:-}"

  local count
  count=$(find "$DIR" -path "$DIR/$pattern" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -lt "$min_count" ]; then
    echo -e "${RED}❌ INSUFFICIENT${NC} $pattern — found $count, need ≥$min_count${desc:+ — $desc}" >&2
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo -e "${GREEN}✅${NC} $pattern ($count files)" >&2
  return 0
}

# ─────────────────────────────────────────────
# Gate: bundle — ALL chunks downloaded
# Run after Step 5c (bundle download)
# ─────────────────────────────────────────────
gate_bundle() {
  echo "═══ GATE: Bundle Analysis ═══" >&2
  check_glob_count "bundles/*.js" 1 "Download ALL loaded chunks via performance API"

  # Each JS file should be > 1KB (not error pages)
  local small=0
  for f in "$DIR"/bundles/*.js; do
    [ -f "$f" ] || continue
    local sz
    sz=$(wc -c < "$f" | tr -d ' ')
    if [ "$sz" -lt 1024 ]; then
      echo -e "${YELLOW}⚠️  $(basename "$f") is only ${sz}B — may be an error page${NC}" >&2
      small=$((small + 1))
    fi
  done
  if [ "$small" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $small chunk(s) suspiciously small${NC}" >&2
  fi

  check_file "bundle-analysis.json" 50 "Chunk analysis (from download-chunks.sh)"
  check_file "element-animation-map.json" 50 "Bundle values mapped to DOM elements"
}

# ─────────────────────────────────────────────
# Gate: spec — transition-spec.json + bundle-map.json
# Run after Step 5d (transition spec)
# ─────────────────────────────────────────────
gate_spec() {
  echo "═══ GATE: Transition Spec ═══" >&2
  check_file "bundle-map.json" 50 "Chunk → feature mapping"
  check_file "transition-spec.json" 100 "Per-transition spec"

  # Validate transition-spec structure
  check_json_key "transition-spec.json" '.transitions' "Must have transitions array"
  check_json_key "transition-spec.json" '.transitions[0].id' "Each entry needs id"
  check_json_key "transition-spec.json" '.transitions[0].trigger' "Each entry needs trigger"
  check_json_key "transition-spec.json" '.transitions[0].source_chunk' "Each entry needs source_chunk"
  check_json_key "transition-spec.json" '.transitions[0].bundle_branch' "Each entry needs bundle_branch"
  check_json_key "transition-spec.json" '.transitions[0].animation' "Each entry needs animation"

  # Reject placeholder values — bundle_branch must be specific
  if [ -f "$DIR/transition-spec.json" ]; then
    local branch
    branch=$(jq -r '.transitions[0].bundle_branch // ""' "$DIR/transition-spec.json" 2>/dev/null)
    if [ "$branch" = "unknown" ] || [ "$branch" = "" ] || [ "$branch" = "null" ]; then
      echo -e "${RED}❌ PLACEHOLDER${NC} transition-spec.json → bundle_branch is '$branch' — must specify which conditional branch (e.g. 'n=true, first visit')" >&2
      FAIL=$((FAIL + 1))
    else
      echo -e "${GREEN}✅${NC} bundle_branch: $branch" >&2
    fi

    # Check animation has at least duration or property
    local has_anim
    has_anim=$(jq -r '.transitions[0].animation | keys | length' "$DIR/transition-spec.json" 2>/dev/null || echo "0")
    if [ "$has_anim" -lt 2 ]; then
      echo -e "${RED}❌ INCOMPLETE${NC} transition-spec.json → animation object has < 2 keys" >&2
      FAIL=$((FAIL + 1))
    fi
  fi

  # Validate bundle-map structure
  check_json_key "bundle-map.json" '.chunks' "Must have chunks array"
  check_json_key "bundle-map.json" '.chunks[0].file' "Each chunk needs file"
  check_json_key "bundle-map.json" '.chunks[0].contains' "Each chunk needs contains list"
}

# ─────────────────────────────────────────────
# Gate: pre-generate — everything needed before code generation
# Run before Step 7 (component generation)
# ─────────────────────────────────────────────
gate_pre_generate() {
  echo "═══ GATE: Pre-Generation ═══" >&2

  # Critical extraction artifacts (Step 2-6)
  check_file "structure.json" 100
  check_file "styles.json" 100
  check_file "interactions-detected.json" 10
  check_file "scroll-engine.json" 10 "Scroll engine type"
  check_file "extracted.json" 100

  # Transition spec (HARD BLOCK — #1 source of errors without it)
  check_file "transition-spec.json" 100 "HARD BLOCK — cannot generate without this"
  check_file "bundle-map.json" 50

  # Original CSS files (CSS-First strategy)
  local css_count
  css_count=$(find "$DIR/css" -name "*.css" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$css_count" -gt 0 ]; then
    echo -e "${GREEN}✅${NC} Original CSS files ($css_count files)" >&2
    # Check CSS variables extracted
    if [ -f "$DIR/css/variables.txt" ]; then
      local var_count
      var_count=$(wc -l < "$DIR/css/variables.txt" | tr -d ' ')
      echo -e "${GREEN}✅${NC} CSS variables extracted ($var_count variables)" >&2
    else
      echo -e "${RED}❌ CSS variables NOT extracted${NC} — run: cat css/*.css | grep -oE '--[a-zA-Z0-9_-]+:\\s*[^;]+' | sort -u > css/variables.txt" >&2
      FAIL=$((FAIL + 1))
    fi
  else
    echo -e "${YELLOW}⚠️${NC} No original CSS files — will use extract-values strategy" >&2
  fi

  # Background/asset images for showcase sections
  if [ -f "$DIR/transition-spec.json" ]; then
    local bg_refs
    bg_refs=$(grep -c "background\|bgImage\|overlay" "$DIR/transition-spec.json" 2>/dev/null || echo "0")
    if [ "$bg_refs" -gt 0 ]; then
      local img_count
      img_count=$(find "$DIR" -path "*/assets/*" -o -path "*/images/*" 2>/dev/null | wc -l | tr -d ' ')
      if [ "$img_count" -lt 3 ]; then
        echo -e "${YELLOW}⚠️${NC} Transitions reference backgrounds but few images downloaded ($img_count) — run extract-assets.sh" >&2
      fi
    fi
  fi

  # Reference frames
  local frame_count
  frame_count=$(find "$DIR" -name "*.png" -path "*/ref/*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$frame_count" -lt 1 ]; then
    echo -e "${RED}❌ NO REFERENCE FRAMES${NC} — capture original before implementing" >&2
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}✅${NC} Reference frames ($frame_count files)" >&2
  fi

  # ── Interaction state captures (MANDATORY — prevents guessing UI) ──
  # Each hover/click interaction in interactions-detected.json must have
  # idle + active reference screenshots in transitions/ref/
  if [ -f "$DIR/interactions-detected.json" ] && command -v jq &>/dev/null; then
    local interaction_count
    interaction_count=$(jq '[.interactions[]? // empty | select(.type == "hover" or .type == "click" or .triggerType == "css-hover" or .triggerType == "js-class")] | length' "$DIR/interactions-detected.json" 2>/dev/null || echo "0")

    if [ "$interaction_count" -gt 0 ]; then
      local capture_count
      capture_count=$(find "$DIR/transitions/ref" -name "*-idle.png" -o -name "*-active.png" 2>/dev/null | wc -l | tr -d ' ')

      if [ "$capture_count" -lt 2 ]; then
        echo -e "${RED}❌ NO INTERACTION CAPTURES${NC} — $interaction_count hover/click interactions detected but no idle+active screenshots found" >&2
        echo -e "    Run Phase A-C3: for each interaction, capture idle + active states" >&2
        echo -e "    Without these, component generation will GUESS the UI layout (the #1 source of visual mismatch)" >&2
        FAIL=$((FAIL + 1))
      else
        local pair_count=$((capture_count / 2))
        if [ "$pair_count" -lt "$interaction_count" ]; then
          echo -e "${YELLOW}⚠️${NC} $pair_count/$interaction_count interactions have captures — missing interactions will be guessed" >&2
        else
          echo -e "${GREEN}✅${NC} Interaction captures ($capture_count files for $interaction_count interactions)" >&2
        fi
      fi
    else
      echo -e "${GREEN}✅${NC} No hover/click interactions detected — no captures needed" >&2
    fi
  fi
}

# ─────────────────────────────────────────────
# Gate: post-implement — verify after each transition
# Run after implementing a transition
# ─────────────────────────────────────────────
gate_post_implement() {
  echo "═══ GATE: Post-Implementation ═══" >&2

  # Resolve SCRIPT_DIR for sibling scripts
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # ── 0. Transition coverage check ──
  if [ -f "$DIR/transition-spec.json" ]; then
    local trans_count
    trans_count=$(python3 -c "import json; d=json.load(open('$DIR/transition-spec.json')); print(len(d.get('transitions',[])))" 2>/dev/null || echo "0")
    if [ "$trans_count" -gt 0 ]; then
      echo "" >&2
      echo "  ── Transition coverage check ($trans_count transitions in spec) ──" >&2
      echo -e "  ${YELLOW}⚠️  Verify each transition in transition-spec.json is implemented:${NC}" >&2
      python3 -c "
import json, sys
d = json.load(open('$DIR/transition-spec.json'))
for t in d.get('transitions', []):
    name = t.get('name', t.get('id', '?'))
    trigger = t.get('trigger', '?')
    target = t.get('target', '?')[:50]
    print(f'    □ {name} ({trigger}) → {target}', file=sys.stderr)
" 2>/dev/null
      echo "  If ANY are missing from the code, implementation is incomplete." >&2
      echo "" >&2
    fi
  fi

  # ── 0b. Mandatory artifact checks ──
  local MISSING=0

  # Layout health check (mandatory before visual comparison)
  if [ -f "$DIR/layout-health.json" ]; then
    echo "  ✓ layout-health.json" >&2
  else
    echo "  ✗ layout-health.json missing — run layout-health-check.sh first" >&2
    echo "    bash \"\$PLUGIN_ROOT/skills/visual-debug/scripts/layout-health-check.sh\" <session> <orig> <impl> $DIR" >&2
    MISSING=$((MISSING + 1))
  fi

  # Style audit (mandatory)
  if [ -f "$DIR/style-audit-diff.json" ]; then
    echo "  ✓ style-audit-diff.json" >&2
    # Check score
    SCORE=$(node -e "const d=require('./$DIR/style-audit-diff.json'); console.log(d.score || 0)" 2>/dev/null || echo "0")
    if [ "$(echo "$SCORE < 9" | bc -l 2>/dev/null || echo 1)" = "1" ]; then
      echo "  ⚠️  Score $SCORE < 9 — needs improvement" >&2
    fi
  else
    echo "  ✗ style-audit-diff.json missing — run style audit" >&2
    MISSING=$((MISSING + 1))
  fi

  # Pixel-perfect diff (produced by Phase D — run separately after auto-verify)
  if [ -f "$DIR/pixel-perfect-diff.json" ]; then
    echo "  ✓ pixel-perfect-diff.json" >&2
  else
    echo -e "  ${YELLOW}⚠️  pixel-perfect-diff.json not found — run Phase D after auto-verify passes${NC}" >&2
  fi

  FAIL=$((FAIL + MISSING))

  # ── 1. Check clips exist (preferred) or fallback to frames ──
  local ref_dir=""
  local impl_dir=""
  local use_clips=false

  # Prefer section clips (from section-clips.sh)
  if [ -d "$DIR/clips/ref/sections" ] && ls "$DIR"/clips/ref/sections/*.png &>/dev/null; then
    ref_dir="$DIR/clips/ref/sections"
    echo -e "${GREEN}✅${NC} Reference section clips: $ref_dir" >&2
    use_clips=true
  elif [ -d "$DIR/frames/ref" ] && ls "$DIR"/frames/ref/*.png &>/dev/null; then
    ref_dir="$DIR/frames/ref"
    echo -e "${YELLOW}⚠️${NC} Using full-page frames (run section-clips.sh for better accuracy)" >&2
  elif ls "$DIR"/compare-ref-*.png &>/dev/null 2>&1; then
    ref_dir="$DIR"
    echo -e "${YELLOW}⚠️${NC} Using compare-ref screenshots" >&2
  else
    echo -e "${RED}❌ NO REFERENCE SCREENSHOTS${NC}" >&2
    echo "  Run: bash $SCRIPT_DIR/section-clips.sh <session> $DIR ref" >&2
    FAIL=$((FAIL + 1))
  fi

  if [ -d "$DIR/clips/impl/sections" ] && ls "$DIR"/clips/impl/sections/*.png &>/dev/null; then
    impl_dir="$DIR/clips/impl/sections"
    echo -e "${GREEN}✅${NC} Implementation section clips: $impl_dir" >&2
  elif [ -d "$DIR/frames/impl" ] && ls "$DIR"/frames/impl/*.png &>/dev/null; then
    impl_dir="$DIR/frames/impl"
    echo -e "${YELLOW}⚠️${NC} Using full-page frames (run section-clips.sh for better accuracy)" >&2
  elif ls "$DIR"/compare-impl-*.png &>/dev/null 2>&1; then
    impl_dir="$DIR"
    echo -e "${YELLOW}⚠️${NC} Using compare-impl screenshots" >&2
  else
    echo -e "${RED}❌ NO IMPLEMENTATION SCREENSHOTS${NC}" >&2
    echo "  Run: bash $SCRIPT_DIR/section-clips.sh <session> $DIR impl" >&2
    FAIL=$((FAIL + 1))
  fi

  # ── 2. Visual comparison ──
  # Prefer compare-sections.sh (section clips) over inline full-page comparison.
  # Section clips isolate each section from background, giving much tighter accuracy.

  if [ -n "$ref_dir" ] && [ -n "$impl_dir" ] && command -v compare &>/dev/null; then

    if [ "$use_clips" = true ] && [ -f "$SCRIPT_DIR/compare-sections.sh" ]; then
      # ── Section-clip comparison (preferred) ──
      echo "" >&2
      echo "  Running compare-sections.sh..." >&2
      echo "" >&2
      bash "$SCRIPT_DIR/compare-sections.sh" "$DIR"
      local cs_exit=$?
      if [ $cs_exit -ne 0 ]; then
        FAIL=$((FAIL + 1))
      fi
    else
      # ── Fallback: inline full-page SSIM ──
      echo "" >&2
      echo "  ── Full-page SSIM comparison (fallback) ──" >&2
      echo "  For better accuracy, run: bash $SCRIPT_DIR/section-clips.sh <session> $DIR ref" >&2
      echo "" >&2

      local SSIM_THRESHOLD=0.25
      local compared=0

      for ref_file in "$ref_dir"/*.png; do
        [ -f "$ref_file" ] || continue
        local bname
        bname=$(basename "$ref_file")
        local impl_file="$impl_dir/$bname"
        [ ! -f "$impl_file" ] && impl_file="$impl_dir/compare-impl-$bname"
        [ ! -f "$impl_file" ] && continue

        local ref_size
        ref_size=$(identify -format "%wx%h" "$ref_file" 2>/dev/null) || continue

        local ssim_raw ssim_val rmse_raw rmse_val
        ssim_raw=$(compare -metric SSIM -resize "$ref_size" "$impl_file" "$ref_file" /dev/null 2>&1 || true)
        ssim_val=$(echo "$ssim_raw" | grep -oE '\(([0-9.]+)\)' | tr -d '()') || ssim_val="1.0"
        [ -z "$ssim_val" ] && ssim_val="1.0"

        rmse_raw=$(compare -metric RMSE -resize "$ref_size" "$impl_file" "$ref_file" /dev/null 2>&1 || true)
        rmse_val=$(echo "$rmse_raw" | grep -oE '\(([0-9.]+)\)' | tr -d '()') || rmse_val="1.0"
        [ -z "$rmse_val" ] && rmse_val="1.0"

        compared=$((compared + 1))

        local ssim_ok
        ssim_ok=$(echo "$ssim_val <= $SSIM_THRESHOLD" | bc -l 2>/dev/null || echo "0")

        if [ "$ssim_ok" = "0" ]; then
          echo -e "  ${RED}❌ $bname: SSIM=$ssim_val (>$SSIM_THRESHOLD) RMSE=$rmse_val${NC}" >&2
          FAIL=$((FAIL + 1))
        else
          echo -e "  ${GREEN}✅ $bname: SSIM=$ssim_val RMSE=$rmse_val${NC}" >&2
        fi
      done

      echo "  Compared $compared pairs" >&2
    fi

  elif ! command -v compare &>/dev/null; then
    echo -e "${YELLOW}⚠️  ImageMagick 'compare' not installed — visual gate skipped${NC}" >&2
    echo "  Install: brew install imagemagick" >&2
  fi
}

# ─────────────────────────────────────────────
# Gate: dynamic-heights — Check for zero-height sections
# caused by cleaning GSAP inline styles that contained
# layout values (height in svh/vh). Run after HTML cleanup.
# ─────────────────────────────────────────────
gate_dynamic_heights() {
  echo "═══ GATE: Dynamic Heights ═══" >&2

  # Check if raw-html directory exists
  local html_dir="$DIR/raw-html"
  if [ ! -d "$html_dir" ]; then
    html_dir="$DIR"
  fi

  # Check if dynamic-styles.json was generated
  if [ -f "$DIR/dynamic-styles.json" ]; then
    echo -e "${GREEN}✅${NC} dynamic-styles.json exists" >&2

    # Check for layout values that need to be re-set by JS
    local layout_count
    layout_count=$(python3 -c "
import json
d = json.load(open('$DIR/dynamic-styles.json'))
count = 0
for el in d.get('elements', []):
    if el.get('layout'):
        for prop, val in el['layout'].items():
            if 'svh' in val or 'vh' in val:
                count += 1
                print(f'  ⚠️  {el[\"selector\"][:60]}: {prop}={val}', flush=True)
print(f'TOTAL={count}', flush=True)
" 2>/dev/null | tee /dev/stderr | tail -1 | grep -oE '[0-9]+')

    if [ "${layout_count:-0}" -gt 0 ]; then
      echo -e "${YELLOW}⚠️  $layout_count layout values use svh/vh units${NC}" >&2
      echo "  These MUST be re-set by ClientShell JS after HTML injection." >&2
      echo "  If removed during GSAP cleanup, sections will have height: 0." >&2
    else
      echo -e "${GREEN}✅${NC} No svh/vh layout values to preserve" >&2
    fi
  else
    echo -e "${YELLOW}⚠️${NC} dynamic-styles.json not found" >&2
    echo "  Run: bash scripts/extract-dynamic-styles.sh <session> $DIR" >&2
  fi

  # Check extracted HTML files for stripped height/width in svh/vh
  local stripped=0
  for html_file in "$html_dir"/*.html; do
    [ -f "$html_file" ] || continue
    local basename
    basename=$(basename "$html_file")

    # Check if the HTML has any elements that should have svh/vh heights
    # but don't (GSAP cleanup may have removed them)
    local has_scroll_sentinel
    has_scroll_sentinel=$(grep -c 'program-services-scroll\|scroll-sentinel' "$html_file" 2>/dev/null || echo "0")
    if [ "$has_scroll_sentinel" -gt 0 ]; then
      local has_svh_height
      has_svh_height=$(grep -c 'svh\|vh' "$html_file" 2>/dev/null || echo "0")
      if [ "$has_svh_height" -eq 0 ]; then
        echo -e "${RED}❌ $basename: has scroll sentinel but NO svh/vh heights${NC}" >&2
        echo "  This section likely needs dynamic height set by JS." >&2
        stripped=$((stripped + 1))
        FAIL=$((FAIL + 1))
      fi
    fi
  done

  if [ "$stripped" -eq 0 ]; then
    echo -e "${GREEN}✅${NC} No stripped dynamic heights detected" >&2
  fi
}

# ─────────────────────────────────────────────
# Run the requested gate
# ─────────────────────────────────────────────
case "$GATE" in
  bundle)         gate_bundle ;;
  spec)           gate_spec ;;
  pre-generate)   gate_pre_generate ;;
  post-implement) gate_post_implement ;;
  dynamic-heights) gate_dynamic_heights ;;
  all)
    gate_bundle
    echo "" >&2
    gate_spec
    echo "" >&2
    gate_pre_generate
    ;;
  *)
    echo "Unknown gate: $GATE" >&2
    echo "Available: bundle | spec | pre-generate | post-implement | dynamic-heights | all" >&2
    exit 1
    ;;
esac

# ─────────────────────────────────────────────
# Final verdict — JSON to stdout, human-readable to stderr
# ─────────────────────────────────────────────
END_TIME=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000))")
DURATION_MS=$(( END_TIME - START_TIME ))

cat <<ENDJSON
{
  "status": "$( [ "$FAIL" -gt 0 ] && echo "fail" || echo "pass" )",
  "phase": "$GATE",
  "data": {
    "gate": "$GATE",
    "checks_failed": $FAIL,
    "missing": $MISSING_FILES
  },
  "defects": [],
  "errors": [],
  "duration_ms": $DURATION_MS
}
ENDJSON

echo "" >&2
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}⛔ BLOCKED — $FAIL check(s) failed. Fix before proceeding.${NC}" >&2
  exit 1
else
  echo -e "${GREEN}✅ GATE PASSED${NC}" >&2
  exit 0
fi

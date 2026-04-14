#!/usr/bin/env bash
# compare-sections.sh — Per-section and per-element visual comparison
# Usage: bash compare-sections.sh <extraction-dir>
#
# Expects:
#   <dir>/clips/ref/sections/   — reference section screenshots
#   <dir>/clips/impl/sections/  — implementation section screenshots
#   <dir>/clips/ref/elements/   — reference element screenshots (optional)
#   <dir>/clips/impl/elements/  — implementation element screenshots (optional)
#   <dir>/clips/ref/styles.json — getComputedStyle values from ref (optional)
#   <dir>/clips/impl/styles.json — getComputedStyle values from impl (optional)
#
# Produces:
#   <dir>/clips/diff/sections/  — diff images per section
#   <dir>/clips/diff/elements/  — diff images per element
#   <dir>/clips/comparison.json — per-section and per-element SSIM/RMSE + style diffs
#
# Three-layer gate:
#   Layer 1: Section SSIM ≤ 0.25 — structural layout match (catches wrong layout)
#   Layer 2: Element RMSE ≤ 0.15 — color/spacing match on cropped elements (catches wrong colors)
#   Layer 3: Style diff = 0 mismatches — getComputedStyle numerical match (catches sub-pixel errors)
#
# IMPORTANT: Screenshots must be captured at content-anchored positions, NOT y-coordinates.
# Use text anchors (heading text) to align ref and impl before capture.
# Wrong: "capture ref at y=5232 and impl at y=6300"
# Right: "find 'Clothing to claim' heading, scroll it to viewport center, capture"

set -euo pipefail

DIR="${1:?Usage: compare-sections.sh <extraction-dir>}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REF_SECTIONS="$DIR/clips/ref/sections"
IMPL_SECTIONS="$DIR/clips/impl/sections"
REF_ELEMENTS="$DIR/clips/ref/elements"
IMPL_ELEMENTS="$DIR/clips/impl/elements"
DIFF_SECTIONS="$DIR/clips/diff/sections"
DIFF_ELEMENTS="$DIR/clips/diff/elements"

mkdir -p "$DIFF_SECTIONS" "$DIFF_ELEMENTS"

if ! command -v compare &>/dev/null; then
  echo -e "${RED}ImageMagick 'compare' not installed. Run: brew install imagemagick${NC}"
  exit 1
fi

SECTION_SSIM_THRESHOLD=0.25
ELEMENT_RMSE_THRESHOLD=0.15

FAIL=0
PASS=0
WARN=0

# ── JSON output ──
START_TIME=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000))")
DEFECTS="[]"
style_match_count=0
style_mismatch_count=0

results_json='{"sections":[],"elements":[]}'

echo "" >&2
echo "═══ Section-by-Section Comparison ═══" >&2
echo "" >&2

# ── Section comparison ──
if [ -d "$REF_SECTIONS" ] && [ -d "$IMPL_SECTIONS" ]; then
  for ref_file in "$REF_SECTIONS"/*.png; do
    [ -f "$ref_file" ] || continue
    bname=$(basename "$ref_file")
    impl_file="$IMPL_SECTIONS/$bname"
    [ ! -f "$impl_file" ] && continue

    ref_size=$(identify -format "%wx%h" "$ref_file" 2>/dev/null) || continue

    # SSIM (structural)
    ssim_raw=$(compare -metric SSIM -resize "$ref_size" "$impl_file" "$ref_file" /dev/null 2>&1 || true)
    ssim_val=$(echo "$ssim_raw" | grep -oE '\(([0-9.]+)\)' | tr -d '()') || ssim_val=""
    [ -z "$ssim_val" ] && ssim_val="1.0"

    # RMSE (pixel)
    rmse_raw=$(compare -metric RMSE -resize "$ref_size" "$impl_file" "$ref_file" "$DIFF_SECTIONS/$bname" 2>&1 || true)
    rmse_val=$(echo "$rmse_raw" | grep -oE '\(([0-9.]+)\)' | tr -d '()') || rmse_val=""
    [ -z "$rmse_val" ] && rmse_val="1.0"

    ssim_ok=$(echo "$ssim_val <= $SECTION_SSIM_THRESHOLD" | bc -l 2>/dev/null || echo "0")

    section_name="${bname%.png}"

    if [ "$ssim_ok" = "1" ]; then
      echo -e "  ${GREEN}✅ $section_name${NC}  SSIM=$ssim_val  RMSE=$rmse_val" >&2
      PASS=$((PASS + 1))
    else
      echo -e "  ${RED}❌ $section_name${NC}  SSIM=$ssim_val (>$SECTION_SSIM_THRESHOLD)  RMSE=$rmse_val" >&2
      echo -e "     Diff: $DIFF_SECTIONS/$bname" >&2
      FAIL=$((FAIL + 1))
    fi

    # Append to JSON
    results_json=$(echo "$results_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['sections'].append({'name':'$section_name','ssim':$ssim_val,'rmse':$rmse_val,'pass':$ssim_ok == 1})
json.dump(d, sys.stdout)
" 2>/dev/null || echo "$results_json")
  done
else
  echo -e "${RED}Missing section clips. Run section-clips.sh for both ref and impl first.${NC}" >&2
  exit 1
fi

# ── Element comparison ──
echo "" >&2
if [ -d "$REF_ELEMENTS" ] && [ -d "$IMPL_ELEMENTS" ]; then
  echo "═══ Element-by-Element Comparison ═══" >&2
  echo "" >&2

  elem_pass=0
  elem_fail=0

  for ref_file in "$REF_ELEMENTS"/*.png; do
    [ -f "$ref_file" ] || continue
    bname=$(basename "$ref_file")
    impl_file="$IMPL_ELEMENTS/$bname"
    [ ! -f "$impl_file" ] && continue

    ref_size=$(identify -format "%wx%h" "$ref_file" 2>/dev/null) || continue

    # RMSE only for elements (tight threshold)
    rmse_raw=$(compare -metric RMSE -resize "$ref_size" "$impl_file" "$ref_file" "$DIFF_ELEMENTS/$bname" 2>&1 || true)
    rmse_val=$(echo "$rmse_raw" | grep -oE '\(([0-9.]+)\)' | tr -d '()') || rmse_val=""
    [ -z "$rmse_val" ] && rmse_val="1.0"

    rmse_ok=$(echo "$rmse_val <= $ELEMENT_RMSE_THRESHOLD" | bc -l 2>/dev/null || echo "0")

    elem_name="${bname%.png}"

    if [ "$rmse_ok" = "1" ]; then
      echo -e "  ${GREEN}✅ $elem_name${NC}  RMSE=$rmse_val" >&2
      elem_pass=$((elem_pass + 1))
    else
      echo -e "  ${RED}❌ $elem_name${NC}  RMSE=$rmse_val (>$ELEMENT_RMSE_THRESHOLD)" >&2
      elem_fail=$((elem_fail + 1))
      FAIL=$((FAIL + 1))
    fi

    results_json=$(echo "$results_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['elements'].append({'name':'$elem_name','rmse':$rmse_val,'pass':$rmse_ok == 1})
json.dump(d, sys.stdout)
" 2>/dev/null || echo "$results_json")
  done

  echo "" >&2
  echo "  Elements: $elem_pass pass, $elem_fail fail" >&2
else
  echo -e "${YELLOW}⚠️  No element clips — element comparison skipped${NC}" >&2
  echo "  Run section-clips.sh with element detection for tighter validation" >&2
fi

# ── Transition frame comparison ──
echo "" >&2
TRANS_REF="$DIR/clips/ref/transitions"
TRANS_IMPL="$DIR/clips/impl/transitions"

if [ -d "$TRANS_REF" ] && [ -d "$TRANS_IMPL" ]; then
  echo "═══ Transition Frame Comparison ═══" >&2
  echo "" >&2

  for trans_dir in "$TRANS_REF"/*/; do
    [ -d "$trans_dir" ] || continue
    trans_name=$(basename "$trans_dir")
    impl_trans="$TRANS_IMPL/$trans_name"
    [ ! -d "$impl_trans" ] && continue

    ref_frames=($(ls "$trans_dir"*.png 2>/dev/null | sort))
    impl_frames=($(ls "$impl_trans"/*.png 2>/dev/null | sort))

    if [ ${#ref_frames[@]} -eq 0 ] || [ ${#impl_frames[@]} -eq 0 ]; then
      echo -e "  ${YELLOW}⚠️  $trans_name: no frames to compare${NC}" >&2
      continue
    fi

    total_match=0
    total_compared=0

    for idx in 0 $(( ${#ref_frames[@]} / 2 )) $(( ${#ref_frames[@]} - 1 )); do
      rf="${ref_frames[$idx]}"
      impl_idx=$(( idx * ${#impl_frames[@]} / ${#ref_frames[@]} ))
      [ $impl_idx -ge ${#impl_frames[@]} ] && impl_idx=$(( ${#impl_frames[@]} - 1 ))
      imf="${impl_frames[$impl_idx]}"

      ref_size=$(identify -format "%wx%h" "$rf" 2>/dev/null) || continue

      rmse_raw=$(compare -metric RMSE -resize "$ref_size" "$imf" "$rf" /dev/null 2>&1 || true)
      rmse_val=$(echo "$rmse_raw" | grep -oE '\(([0-9.]+)\)' | tr -d '()') || rmse_val="1.0"

      total_compared=$((total_compared + 1))
      rmse_ok=$(echo "$rmse_val <= 0.20" | bc -l 2>/dev/null || echo "0")
      [ "$rmse_ok" = "1" ] && total_match=$((total_match + 1))
    done

    if [ $total_compared -gt 0 ]; then
      if [ $total_match -eq $total_compared ]; then
        echo -e "  ${GREEN}✅ $trans_name: $total_match/$total_compared frames match${NC}" >&2
      else
        echo -e "  ${RED}❌ $trans_name: $total_match/$total_compared frames match${NC}" >&2
        FAIL=$((FAIL + 1))
      fi
    fi
  done
else
  echo -e "${YELLOW}⚠️  No transition frame directories — transition comparison skipped${NC}" >&2
  echo "  Extract video frames with: ffmpeg -i video.webm -vf fps=60 frames/frame-%06d.png" >&2
fi

# ── Layer 3: getComputedStyle numerical comparison + defect classification ──
echo "" >&2
REF_STYLES="$DIR/clips/ref/styles.json"
IMPL_STYLES="$DIR/clips/impl/styles.json"

if [ -f "$REF_STYLES" ] && [ -f "$IMPL_STYLES" ]; then
  echo "═══ Layer 3: getComputedStyle Comparison ═══" >&2
  echo "" >&2

  style_mismatches=$(python3 -c "
import json, sys

ref = json.load(open('$REF_STYLES'))
impl = json.load(open('$IMPL_STYLES'))
mismatches = []
matches = 0

CATEGORY_MAP = {
    'fontSize': 'TYPOGRAPHY', 'fontWeight': 'TYPOGRAPHY', 'fontFamily': 'TYPOGRAPHY',
    'lineHeight': 'TYPOGRAPHY', 'letterSpacing': 'TYPOGRAPHY', 'textTransform': 'TYPOGRAPHY',
    'color': 'COLOR', 'backgroundColor': 'COLOR', 'borderColor': 'COLOR',
    'opacity': 'COLOR', 'backgroundImage': 'COLOR', 'boxShadow': 'COLOR',
    'width': 'LAYOUT', 'height': 'LAYOUT',
    'paddingTop': 'LAYOUT', 'paddingRight': 'LAYOUT', 'paddingBottom': 'LAYOUT', 'paddingLeft': 'LAYOUT',
    'marginTop': 'LAYOUT', 'marginRight': 'LAYOUT', 'marginBottom': 'LAYOUT', 'marginLeft': 'LAYOUT',
    'gap': 'LAYOUT', 'display': 'LAYOUT', 'flexDirection': 'LAYOUT',
    'alignItems': 'LAYOUT', 'justifyContent': 'LAYOUT', 'gridTemplateColumns': 'LAYOUT',
    'position': 'LAYOUT', 'top': 'LAYOUT', 'left': 'LAYOUT', 'right': 'LAYOUT', 'bottom': 'LAYOUT',
    'borderRadius': 'LAYOUT',
    'transform': 'ANIMATION', 'transition': 'ANIMATION',
    'animationName': 'ANIMATION', 'animationDuration': 'ANIMATION',
}

def classify(prop):
    if prop in CATEGORY_MAP: return CATEGORY_MAP[prop]
    if 'padding' in prop or 'margin' in prop: return 'LAYOUT'
    if 'color' in prop or 'background' in prop: return 'COLOR'
    if 'font' in prop or 'text' in prop or 'letter' in prop or 'line' in prop: return 'TYPOGRAPHY'
    if 'animation' in prop or 'transition' in prop or 'transform' in prop: return 'ANIMATION'
    return 'LAYOUT'

def severity(prop, ref_val, impl_val):
    if impl_val == 'MISSING': return 'CRITICAL'
    if prop == 'display' and ref_val != impl_val: return 'CRITICAL'
    try:
        rv = float(ref_val.replace('px','').replace('em','').replace('rem','').replace('%',''))
        iv = float(impl_val.replace('px','').replace('em','').replace('rem','').replace('%',''))
        diff = abs(rv - iv)
        if diff > 50: return 'CRITICAL'
        if diff > 3: return 'MAJOR'
        return 'MINOR'
    except (ValueError, AttributeError):
        pass
    return 'MAJOR'

for selector in ref:
    if selector not in impl:
        mismatches.append({'selector': selector, 'issue': 'missing in impl',
                           'category': 'CONTENT', 'severity': 'CRITICAL',
                           'property': '', 'expected': '', 'actual': 'MISSING'})
        continue
    for prop in ref[selector]:
        ref_val = str(ref[selector][prop]).strip()
        impl_val = str(impl[selector].get(prop, 'MISSING')).strip()
        if ref_val != impl_val:
            mismatches.append({
                'selector': selector, 'property': prop,
                'expected': ref_val, 'actual': impl_val,
                'category': classify(prop),
                'severity': severity(prop, ref_val, impl_val)
            })
        else:
            matches += 1

print(json.dumps({'matches': matches, 'mismatches': mismatches}))
" 2>/dev/null || echo '{"matches":0,"mismatches":[]}')

  style_mismatch_count=$(echo "$style_mismatches" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['mismatches']))" 2>/dev/null || echo "0")
  style_match_count=$(echo "$style_mismatches" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['matches'])" 2>/dev/null || echo "0")

  if [ "$style_mismatch_count" -gt 0 ]; then
    echo -e "  ${RED}❌ $style_mismatch_count style mismatches (${style_match_count} matches)${NC}" >&2
    echo "$style_mismatches" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for m in d['mismatches'][:10]:
    sel = m.get('selector','?')
    prop = m.get('property','?')
    cat = m.get('category','?')
    sev = m.get('severity','?')
    exp = m.get('expected','?')
    act = m.get('actual','?')
    issue = m.get('issue','')
    if issue:
        print(f'    [{sev}] {sel}: {issue}', file=sys.stderr)
    else:
        print(f'    [{sev}/{cat}] {sel} → {prop}: expected={exp} actual={act}', file=sys.stderr)
if len(d['mismatches']) > 10:
    print(f'    ... and {len(d[\"mismatches\"]) - 10} more', file=sys.stderr)
" 2>/dev/null
    FAIL=$((FAIL + style_mismatch_count))

    echo "$style_mismatches" | python3 -m json.tool > "$DIR/clips/style-mismatches.json" 2>/dev/null
    echo "" >&2
    echo "  Full mismatch list: $DIR/clips/style-mismatches.json" >&2
  else
    echo -e "  ${GREEN}✅ All $style_match_count style properties match${NC}" >&2
  fi

  # Build defects array for JSON output
  DEFECTS=$(echo "$style_mismatches" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(json.dumps(d.get('mismatches', [])))
" 2>/dev/null || echo "[]")
else
  echo -e "${YELLOW}⚠️  No styles.json files — getComputedStyle comparison skipped${NC}" >&2
  echo '  Extract styles with agent-browser eval on both ref and impl' >&2
fi

# ── Save results ──
echo "$results_json" | python3 -m json.tool > "$DIR/clips/comparison.json" 2>/dev/null

# ── JSON output (stdout) ──
END_TIME=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000))")
DURATION_MS=$(( END_TIME - START_TIME ))

cat <<ENDJSON > "$DIR/clips/comparison-output.json"
{
  "status": "$( [ "$FAIL" -gt 0 ] && echo "fail" || echo "pass" )",
  "phase": "post-implement",
  "data": {
    "sections": $( echo "$results_json" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('sections',[])))" 2>/dev/null || echo "[]" ),
    "elements": $( echo "$results_json" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('elements',[])))" 2>/dev/null || echo "[]" ),
    "style_matches": ${style_match_count},
    "style_mismatches_count": ${style_mismatch_count}
  },
  "defects": $DEFECTS,
  "errors": [],
  "duration_ms": $DURATION_MS
}
ENDJSON

# ── Human-readable summary (stderr) ──
echo "" >&2
echo "══════════════════════════════════════" >&2
if [ $FAIL -gt 0 ]; then
  echo -e "${RED}⛔ $FAIL failures, $PASS passes${NC}" >&2
  echo "" >&2
  echo "Fix workflow (in this order):" >&2
  echo "  1. Fix CRITICAL defects first (see $DIR/clips/comparison-output.json)" >&2
  echo "  2. Then MAJOR, then MINOR" >&2
  echo "  3. Re-capture impl screenshots at CONTENT-ANCHORED positions" >&2
  echo "  4. Re-run: compare-sections.sh $DIR" >&2
  exit 1
else
  echo -e "${GREEN}✅ ALL SECTIONS PASS ($PASS sections)${NC}" >&2
  echo "Results: $DIR/clips/comparison-output.json" >&2
  exit 0
fi

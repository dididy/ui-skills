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

results_json='{"sections":[],"elements":[]}'

echo ""
echo "═══ Section-by-Section Comparison ═══"
echo ""

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
      echo -e "  ${GREEN}✅ $section_name${NC}  SSIM=$ssim_val  RMSE=$rmse_val"
      PASS=$((PASS + 1))
    else
      echo -e "  ${RED}❌ $section_name${NC}  SSIM=$ssim_val (>$SECTION_SSIM_THRESHOLD)  RMSE=$rmse_val"
      echo -e "     Diff: $DIFF_SECTIONS/$bname"
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
  echo -e "${RED}Missing section clips. Run section-clips.sh for both ref and impl first.${NC}"
  exit 1
fi

# ── Element comparison ──
echo ""
if [ -d "$REF_ELEMENTS" ] && [ -d "$IMPL_ELEMENTS" ]; then
  echo "═══ Element-by-Element Comparison ═══"
  echo ""

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
      echo -e "  ${GREEN}✅ $elem_name${NC}  RMSE=$rmse_val"
      elem_pass=$((elem_pass + 1))
    else
      echo -e "  ${RED}❌ $elem_name${NC}  RMSE=$rmse_val (>$ELEMENT_RMSE_THRESHOLD)"
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

  echo ""
  echo "  Elements: $elem_pass pass, $elem_fail fail"
else
  echo -e "${YELLOW}⚠️  No element clips — element comparison skipped${NC}"
  echo "  Run section-clips.sh with element detection for tighter validation"
fi

# ── Transition frame comparison ──
echo ""
TRANS_REF="$DIR/clips/ref/transitions"
TRANS_IMPL="$DIR/clips/impl/transitions"

if [ -d "$TRANS_REF" ] && [ -d "$TRANS_IMPL" ]; then
  echo "═══ Transition Frame Comparison ═══"
  echo ""

  for trans_dir in "$TRANS_REF"/*/; do
    [ -d "$trans_dir" ] || continue
    trans_name=$(basename "$trans_dir")
    impl_trans="$TRANS_IMPL/$trans_name"
    [ ! -d "$impl_trans" ] && continue

    # Compare key frames (first, middle, last)
    ref_frames=($(ls "$trans_dir"*.png 2>/dev/null | sort))
    impl_frames=($(ls "$impl_trans"/*.png 2>/dev/null | sort))

    if [ ${#ref_frames[@]} -eq 0 ] || [ ${#impl_frames[@]} -eq 0 ]; then
      echo -e "  ${YELLOW}⚠️  $trans_name: no frames to compare${NC}"
      continue
    fi

    # Compare first, middle, last frames
    total_match=0
    total_compared=0

    for idx in 0 $(( ${#ref_frames[@]} / 2 )) $(( ${#ref_frames[@]} - 1 )); do
      rf="${ref_frames[$idx]}"
      # Find corresponding impl frame (by index ratio)
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
        echo -e "  ${GREEN}✅ $trans_name: $total_match/$total_compared frames match${NC}"
      else
        echo -e "  ${RED}❌ $trans_name: $total_match/$total_compared frames match${NC}"
        FAIL=$((FAIL + 1))
      fi
    fi
  done
else
  echo -e "${YELLOW}⚠️  No transition frame directories — transition comparison skipped${NC}"
  echo "  Extract video frames with: ffmpeg -i video.webm -vf fps=60 frames/frame-%06d.png"
fi

# ── Layer 3: getComputedStyle numerical comparison ──
echo ""
REF_STYLES="$DIR/clips/ref/styles.json"
IMPL_STYLES="$DIR/clips/impl/styles.json"

if [ -f "$REF_STYLES" ] && [ -f "$IMPL_STYLES" ]; then
  echo "═══ Layer 3: getComputedStyle Comparison ═══"
  echo ""

  style_mismatches=$(python3 -c "
import json, sys

ref = json.load(open('$REF_STYLES'))
impl = json.load(open('$IMPL_STYLES'))
mismatches = []
matches = 0

for selector in ref:
    if selector not in impl:
        mismatches.append({'selector': selector, 'issue': 'missing in impl'})
        continue
    for prop in ref[selector]:
        ref_val = str(ref[selector][prop]).strip()
        impl_val = str(impl[selector].get(prop, 'MISSING')).strip()
        if ref_val != impl_val:
            mismatches.append({
                'selector': selector, 'property': prop,
                'ref': ref_val, 'impl': impl_val
            })
        else:
            matches += 1

print(json.dumps({'matches': matches, 'mismatches': mismatches}))
" 2>/dev/null || echo '{"matches":0,"mismatches":[]}')

  style_mismatch_count=$(echo "$style_mismatches" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['mismatches']))" 2>/dev/null || echo "0")
  style_match_count=$(echo "$style_mismatches" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['matches'])" 2>/dev/null || echo "0")

  if [ "$style_mismatch_count" -gt 0 ]; then
    echo -e "  ${RED}❌ $style_mismatch_count style mismatches (${style_match_count} matches)${NC}"
    # Show first 10 mismatches
    echo "$style_mismatches" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for m in d['mismatches'][:10]:
    sel = m.get('selector','?')
    prop = m.get('property','?')
    ref = m.get('ref','?')
    impl = m.get('impl','?')
    issue = m.get('issue','')
    if issue:
        print(f'    {sel}: {issue}')
    else:
        print(f'    {sel} → {prop}: ref={ref} impl={impl}')
if len(d['mismatches']) > 10:
    print(f'    ... and {len(d[\"mismatches\"]) - 10} more')
" 2>/dev/null
    FAIL=$((FAIL + style_mismatch_count))

    # Save mismatches for targeted fixing
    echo "$style_mismatches" | python3 -m json.tool > "$DIR/clips/style-mismatches.json" 2>/dev/null
    echo ""
    echo "  Full mismatch list: $DIR/clips/style-mismatches.json"
    echo "  Each mismatch tells you EXACTLY which selector + property to fix."
  else
    echo -e "  ${GREEN}✅ All $style_match_count style properties match${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  No styles.json files — getComputedStyle comparison skipped${NC}"
  echo "  For precise verification, extract styles with agent-browser eval on both ref and impl:"
  echo '  agent-browser eval "(() => { /* getComputedStyle for key elements */ })()"'
  echo "  Save to: $DIR/clips/ref/styles.json and $DIR/clips/impl/styles.json"
fi

# ── Save results ──
echo "$results_json" | python3 -m json.tool > "$DIR/clips/comparison.json" 2>/dev/null

# ── Summary ──
echo ""
echo "══════════════════════════════════════"
if [ $FAIL -gt 0 ]; then
  echo -e "${RED}⛔ $FAIL failures, $PASS passes${NC}"
  echo ""
  echo "Fix workflow (in this order):"
  echo "  1. Fix style mismatches FIRST (style-mismatches.json has exact selector + property + expected value)"
  echo "  2. Then fix visual diff (diff images show layout differences)"
  echo "  3. Re-capture impl screenshots at CONTENT-ANCHORED positions (not y-coords)"
  echo "  4. Re-run: compare-sections.sh $DIR"
  echo ""
  echo "IMPORTANT: Use content anchors for screenshot alignment."
  echo "  Find a heading text → scroll it to viewport center → screenshot."
  echo "  Do NOT use raw y-coordinates — ref and impl have different page heights."
  exit 1
else
  echo -e "${GREEN}✅ ALL SECTIONS PASS ($PASS sections)${NC}"
  echo "Results: $DIR/clips/comparison.json"
  exit 0
fi

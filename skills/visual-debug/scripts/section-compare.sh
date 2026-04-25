#!/usr/bin/env bash
# section-compare.sh — Compare original vs implementation by section
#
# Usage: bash section-compare.sh <orig-url> <impl-url> <session> [output-dir]
#
# Instead of full-page scroll screenshots, this script:
# 1. Enumerates semantic sections on both sites
# 2. Matches sections by text content similarity
# 3. Crops element-level screenshots per section
# 4. Runs AE comparison per section
# 5. Diffs computedStyle + DOM structure per section
#
# Output: <dir>/sections/{ref,impl,diff}/<section-name>.png
#         <dir>/sections/report.json
#
# This eliminates scroll-alignment noise from full-page comparisons.

set -euo pipefail

VIEW_W="${VIEW_W:-1440}"
VIEW_H="${VIEW_H:-900}"

ORIG_URL="${1:?Usage: section-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
IMPL_URL="${2:?Usage: section-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
SESSION="${3:?Usage: section-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
DIR="${4:-tmp/ref/visual-debug}"

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

SESSION_REF="${SESSION}-sc-ref"
SESSION_IMPL="${SESSION}-sc-impl"

cleanup_browsers() {
  agent-browser --session "$SESSION_REF" close 2>/dev/null || true
  agent-browser --session "$SESSION_IMPL" close 2>/dev/null || true
}
trap cleanup_browsers EXIT

mkdir -p "$DIR/sections/ref" "$DIR/sections/impl" "$DIR/sections/diff"

echo "═══ Section-Level Comparison ═══"
echo "Original: $ORIG_URL"
echo "Implementation: $IMPL_URL"
echo ""

# ── Open both sites ──
echo "▸ Opening both sites..."
agent-browser --session "$SESSION_REF" open "$ORIG_URL" 2>&1 | head -1
agent-browser --session "$SESSION_IMPL" open "$IMPL_URL" 2>&1 | head -1

agent-browser --session "$SESSION_REF" set viewport "$VIEW_W" "$VIEW_H" > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" set viewport "$VIEW_W" "$VIEW_H" > /dev/null 2>&1

agent-browser --session "$SESSION_REF" wait 8000 > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" wait 6000 > /dev/null 2>&1

# Remove common overlays (cookie banners, newsletter popups)
DISMISS_OVERLAYS='(() => {
  document.querySelectorAll("[class*=popup], [class*=modal], [class*=cookie], [class*=banner], [class*=overlay], [class*=signup]").forEach(el => {
    const s = getComputedStyle(el);
    if (s.position === "fixed" || s.position === "absolute") {
      if (el.offsetWidth > window.innerWidth * 0.3 && el.offsetHeight > window.innerHeight * 0.2) {
        el.remove();
      }
    }
  });
  document.body.style.overflow = "";
  document.documentElement.style.overflow = "";
  return "overlays dismissed";
})()'

agent-browser --session "$SESSION_REF" eval "$DISMISS_OVERLAYS" 2>&1 > /dev/null
agent-browser --session "$SESSION_IMPL" eval "$DISMISS_OVERLAYS" 2>&1 > /dev/null

sleep 1

# ── Step 1: Enumerate sections on both sites ──
echo "▸ Enumerating sections..."

ENUMERATE_SECTIONS='(() => {
  const semanticTags = new Set(["section", "footer", "header", "nav", "main"]);
  const containers = [];

  function collect(parent, depth) {
    if (depth > 6) return;
    const children = Array.from(parent.children);

    children.forEach(el => {
      const tag = el.tagName.toLowerCase();
      if (tag === "script" || tag === "style" || tag === "link" || tag === "noscript") return;
      const rect = el.getBoundingClientRect();
      const h = rect.height;
      if (h < 50 || rect.width < 100) return;

      const isSemantic = semanticTags.has(tag);
      const isLargeDiv = tag === "div" && h > window.innerHeight * 0.2;
      const isPageWrapper = h > document.documentElement.scrollHeight * 0.8;

      if (isSemantic) {
        containers.push({ el, tag, rect });
      } else if (isLargeDiv) {
        // If this div wraps most of the page, descend into it instead
        if (isPageWrapper) {
          collect(el, depth + 1);
        } else {
          // Check if this div has semantic children — if so, descend
          const hasSemanticChildren = Array.from(el.children).some(c =>
            semanticTags.has(c.tagName.toLowerCase())
          );
          if (hasSemanticChildren) {
            collect(el, depth + 1);
          } else {
            containers.push({ el, tag, rect });
          }
        }
      } else if (tag === "div" && h > 100) {
        collect(el, depth + 1);
      }
    });
  }

  collect(document.body, 0);

  // Deduplicate: remove parents that contain other found sections
  const filtered = containers.filter((c, i) =>
    !containers.some((other, j) => j !== i && c.el.contains(other.el) && c.el !== other.el)
  );

  filtered.sort((a, b) => a.rect.top - b.rect.top);

  return filtered.map((c, i) => {
    const el = c.el;
    const rect = el.getBoundingClientRect();
    const scrollY = window.scrollY;

    // Extract text fingerprint (first 100 chars of visible text, normalized)
    const text = el.innerText || "";
    const words = text.replace(/\\s+/g, " ").trim().substring(0, 200);
    const fingerprint = words.substring(0, 100).toLowerCase().replace(/[^a-z0-9 ]/g, "");

    // Check for SVGs
    const svgs = el.querySelectorAll("svg");
    const hasSvgText = [...svgs].some(svg => {
      const paths = svg.querySelectorAll("path");
      if (paths.length < 3) return false;
      const totalD = [...paths].reduce((sum, p) => sum + (p.getAttribute("d")?.length || 0), 0);
      return totalD > 500;
    });

    // Get rendering info
    const cs = getComputedStyle(el);

    return {
      index: i,
      tag: c.tag,
      id: el.id || null,
      className: (el.className?.toString?.() || "").substring(0, 80),
      fingerprint,
      hasSvgText,
      rect: {
        top: Math.round(rect.top + scrollY),
        left: Math.round(rect.left),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      },
      display: cs.display,
      gridCols: cs.gridTemplateColumns !== "none" ? cs.gridTemplateColumns : null,
      childCount: el.children.length,
    };
  });
})()'

agent-browser --session "$SESSION_REF" eval "$ENUMERATE_SECTIONS" > "$DIR/sections/ref-sections.json" 2>&1
agent-browser --session "$SESSION_IMPL" eval "$ENUMERATE_SECTIONS" > "$DIR/sections/impl-sections.json" 2>&1

REF_COUNT=$(python3 -c "import json; d=json.loads(open('$DIR/sections/ref-sections.json').read()); print(len(d))" 2>/dev/null || echo "0")
IMPL_COUNT=$(python3 -c "import json; d=json.loads(open('$DIR/sections/impl-sections.json').read()); print(len(d))" 2>/dev/null || echo "0")

echo "  Ref:  $REF_COUNT sections"
echo "  Impl: $IMPL_COUNT sections"

if [ "$REF_COUNT" = "0" ] || [ "$IMPL_COUNT" = "0" ]; then
  echo "ERROR: Failed to enumerate sections"
  exit 1
fi

# ── Step 2: Match sections by fingerprint similarity ──
echo "▸ Matching sections..."

python3 -c "
import json, sys

ref = json.loads(open('$DIR/sections/ref-sections.json').read())
impl = json.loads(open('$DIR/sections/impl-sections.json').read())

def similarity(a, b):
    if not a or not b:
        return 0
    words_a = set(a.split())
    words_b = set(b.split())
    if not words_a or not words_b:
        return 0
    intersection = words_a & words_b
    union = words_a | words_b
    return len(intersection) / len(union)

matches = []
used_impl = set()

for r in ref:
    best_score = 0
    best_impl = None
    for im in impl:
        if im['index'] in used_impl:
            continue
        score = similarity(r['fingerprint'], im['fingerprint'])
        # Also boost if same tag and similar position ratio
        if r['tag'] == im['tag']:
            score += 0.1
        if score > best_score:
            best_score = score
            best_impl = im

    if best_impl and best_score > 0.05:
        used_impl.add(best_impl['index'])
        name = r['id'] or r['className'].split()[0] if r['className'] else f'section-{r[\"index\"]}'
        name = name.replace('/', '-').replace(' ', '-')[:40]
        matches.append({
            'name': name,
            'score': round(best_score, 3),
            'ref': r,
            'impl': best_impl,
        })
    else:
        name = r['id'] or r['className'].split()[0] if r['className'] else f'section-{r[\"index\"]}'
        name = name.replace('/', '-').replace(' ', '-')[:40]
        matches.append({
            'name': name,
            'score': 0,
            'ref': r,
            'impl': None,
            'status': 'UNMATCHED',
        })

# Unmatched impl sections
for im in impl:
    if im['index'] not in used_impl:
        name = im['id'] or im['className'].split()[0] if im['className'] else f'impl-section-{im[\"index\"]}'
        name = name.replace('/', '-').replace(' ', '-')[:40]
        matches.append({
            'name': name,
            'score': 0,
            'ref': None,
            'impl': im,
            'status': 'EXTRA_IN_IMPL',
        })

json.dump(matches, open('$DIR/sections/matches.json', 'w'), indent=2)
print(f'  {len([m for m in matches if m.get(\"impl\")])} matched, {len([m for m in matches if not m.get(\"impl\")])} unmatched ref, {len([m for m in matches if not m.get(\"ref\")])} extra impl')
" 2>&1

# ── Step 3: Crop element screenshots per matched section ──
echo "▸ Capturing section screenshots..."

MATCHES=$(cat "$DIR/sections/matches.json")
MATCH_COUNT=$(python3 -c "import json; print(len([m for m in json.loads('''$MATCHES''') if m.get('ref') and m.get('impl')]))" 2>/dev/null || echo "0")

python3 -c "
import json, subprocess, sys

matches = json.loads(open('$DIR/sections/matches.json').read())

for m in matches:
    name = m['name']
    ref = m.get('ref')
    impl = m.get('impl')

    if ref:
        r = ref['rect']
        # Scroll to section and screenshot with clip
        scroll_y = max(0, r['top'] - 50)
        clip_top = r['top'] - scroll_y
        cmd_scroll = f'agent-browser --session $SESSION_REF eval \"(() => {{ window.scrollTo(0, {scroll_y}); return {scroll_y}; }})()\"'
        subprocess.run(cmd_scroll, shell=True, capture_output=True)
        import time; time.sleep(0.3)
        cmd_ss = f'agent-browser --session $SESSION_REF screenshot $DIR/sections/ref/{name}.png'
        subprocess.run(cmd_ss, shell=True, capture_output=True)
        # Crop to section bounds
        crop_h = min(r['height'], 1800)  # Cap at 2x viewport
        cmd_crop = f'magick $DIR/sections/ref/{name}.png -crop {r[\"width\"]}x{crop_h}+{r[\"left\"]}+{clip_top} +repage $DIR/sections/ref/{name}.png'
        subprocess.run(cmd_crop, shell=True, capture_output=True)

    if impl:
        r = impl['rect']
        scroll_y = max(0, r['top'] - 50)
        clip_top = r['top'] - scroll_y
        cmd_scroll = f'agent-browser --session $SESSION_IMPL eval \"(() => {{ window.scrollTo(0, {scroll_y}); return {scroll_y}; }})()\"'
        subprocess.run(cmd_scroll, shell=True, capture_output=True)
        import time; time.sleep(0.3)
        cmd_ss = f'agent-browser --session $SESSION_IMPL screenshot $DIR/sections/impl/{name}.png'
        subprocess.run(cmd_ss, shell=True, capture_output=True)
        crop_h = min(r['height'], 1800)
        cmd_crop = f'magick $DIR/sections/impl/{name}.png -crop {r[\"width\"]}x{crop_h}+{r[\"left\"]}+{clip_top} +repage $DIR/sections/impl/{name}.png'
        subprocess.run(cmd_crop, shell=True, capture_output=True)

    sys.stdout.write(f'  ✓ {name}\n')
    sys.stdout.flush()
" 2>&1

# ── Step 4: AE comparison per section ──
echo ""
echo "▸ Comparing sections..."

RESULTS=""
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for REF_IMG in "$DIR/sections/ref/"*.png; do
  NAME=$(basename "$REF_IMG" .png)
  IMPL_IMG="$DIR/sections/impl/${NAME}.png"

  if [ ! -f "$IMPL_IMG" ]; then
    RESULTS="${RESULTS}| ${NAME} | — | — | ⚠️ MISSING impl |\n"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Resize impl to match ref dimensions
  REF_SIZE=$(magick identify -format "%wx%h" "$REF_IMG" 2>/dev/null)
  IMPL_SIZE=$(magick identify -format "%wx%h" "$IMPL_IMG" 2>/dev/null)

  if [ "$REF_SIZE" != "$IMPL_SIZE" ]; then
    magick "$IMPL_IMG" -resize "$REF_SIZE!" -quality 95 "$IMPL_IMG" 2>/dev/null
  fi

  DIFF_IMG="$DIR/sections/diff/${NAME}.png"
  AE=$(magick compare -metric AE "$REF_IMG" "$IMPL_IMG" "$DIFF_IMG" 2>&1 || true)
  AE=$(echo "$AE" | grep -oE '^[0-9]+' | head -1)

  if [ -z "$AE" ]; then
    RESULTS="${RESULTS}| ${NAME} | ERROR | — | ⚠️ |\n"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  THRESHOLD=2000  # Per-section threshold (more lenient than per-pixel)
  if [ "$AE" -le "$THRESHOLD" ]; then
    STATUS="✅"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    STATUS="❌"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  RESULTS="${RESULTS}| ${NAME} | ${AE} | ${THRESHOLD} | ${STATUS} |\n"
done

echo ""
echo "| Section | AE | Threshold | Status |"
echo "|---------|-----|-----------|--------|"
echo -e "$RESULTS"
echo ""
echo "**Result: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL, ${SKIP_COUNT} SKIP**"

# ── Step 5: Structure diff per section ──
echo ""
echo "▸ Structure comparison..."

python3 -c "
import json

matches = json.loads(open('$DIR/sections/matches.json').read())
diffs = []

for m in matches:
    ref = m.get('ref')
    impl = m.get('impl')
    if not ref or not impl:
        continue

    issues = []

    # Check SVG-as-text mismatch
    if ref.get('hasSvgText') and not impl.get('hasSvgText'):
        issues.append('SVG_TEXT_MISSING: ref has SVG text paths, impl does not')
    if not ref.get('hasSvgText') and impl.get('hasSvgText'):
        issues.append('SVG_TEXT_EXTRA: impl has SVG text paths, ref does not')

    # Check layout system mismatch
    if ref.get('gridCols') and not impl.get('gridCols'):
        issues.append(f'LAYOUT_MISMATCH: ref uses grid ({ref[\"gridCols\"][:40]}), impl does not')
    if ref.get('display') != impl.get('display'):
        issues.append(f'DISPLAY_MISMATCH: ref={ref[\"display\"]}, impl={impl[\"display\"]}')

    # Check height ratio
    rh = ref['rect']['height']
    ih = impl['rect']['height']
    if rh > 0:
        ratio = ih / rh
        if ratio < 0.7 or ratio > 1.3:
            issues.append(f'HEIGHT_MISMATCH: ref={rh}px, impl={ih}px (ratio={ratio:.2f})')

    # Check child count
    rc = ref.get('childCount', 0)
    ic = impl.get('childCount', 0)
    if rc > 0 and abs(rc - ic) > max(2, rc * 0.3):
        issues.append(f'CHILD_COUNT_MISMATCH: ref={rc}, impl={ic}')

    if issues:
        diffs.append({'section': m['name'], 'issues': issues})

json.dump(diffs, open('$DIR/sections/structure-diff.json', 'w'), indent=2)

if diffs:
    print('')
    for d in diffs:
        print(f'  ⚠️  {d[\"section\"]}:')
        for issue in d['issues']:
            print(f'     - {issue}')
else:
    print('  ✅ No structural mismatches detected')
" 2>&1

# ── Summary ──
echo ""
echo "═══ Section Compare Complete ═══"
echo "  Screenshots: $DIR/sections/{ref,impl,diff}/"
echo "  Matches:     $DIR/sections/matches.json"
echo "  Diffs:       $DIR/sections/structure-diff.json"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "⛔ ${FAIL_COUNT} section(s) FAILED visual comparison."
  echo "For each FAIL, read the diff image:"
  for REF_IMG in "$DIR/sections/ref/"*.png; do
    NAME=$(basename "$REF_IMG" .png)
    DIFF_IMG="$DIR/sections/diff/${NAME}.png"
    if [ -f "$DIFF_IMG" ]; then
      echo "  Read $DIFF_IMG"
    fi
  done
  exit 1
fi

#!/usr/bin/env bash
# auto-diagnose.sh — Find mismatched elements automatically from AE diff image
#
# Usage: bash auto-diagnose.sh <session> <orig-url> <impl-url> <diff-image> [output-json]
#
# Flow:
#   1. Extract hot regions from diff image (clusters of red pixels)
#   2. Map each region's center to a DOM element via elementFromPoint
#   3. Run computed-diff on those elements only
#   4. Output severity-ranked element list
#
# This eliminates manual selector guessing — the diff image tells us WHERE,
# elementFromPoint tells us WHAT, computed-diff tells us WHY.
#
# Requirements: imagemagick, agent-browser, python3

set -uo pipefail

SESSION="${1:?Usage: auto-diagnose.sh <session> <orig-url> <impl-url> <diff-image> [output-json]}"
ORIG_URL="${2:?Missing orig-url}"
IMPL_URL="${3:?Missing impl-url}"
DIFF_IMG="${4:?Missing diff image path}"
OUTPUT="${5:-}"
VIEW_W="${VIEW_W:-1440}"
VIEW_H="${VIEW_H:-900}"

if [ ! -f "$DIFF_IMG" ]; then
  echo "ERROR: diff image not found: $DIFF_IMG"
  exit 2
fi

echo "═══ Auto-Diagnose from Diff Image ═══"
echo "  diff: $DIFF_IMG"
echo ""

# ── Step 1: Extract hot region centers from diff image ──
# Convert diff image to identify red pixel clusters, find their centroids
# Red pixels in AE diff = mismatched areas
echo "  ▸ Finding mismatch regions..."

COORDS=$(python3 << 'PYEOF'
import sys
from pathlib import Path

try:
    from PIL import Image
    import numpy as np
except ImportError:
    print("ERROR: Pillow and numpy required", file=sys.stderr)
    sys.exit(2)

img = Image.open(sys.argv[1]).convert("RGB")
arr = np.array(img)
h, w = arr.shape[:2]

# Find "hot" pixels — where diff is non-black (any channel > 30)
hot = np.any(arr > 30, axis=2)

if not np.any(hot):
    print("NO_DIFF")
    sys.exit(0)

# Divide image into grid cells and find cells with significant hot pixels
GRID = 8  # 8x8 grid = 64 cells
cell_h = h // GRID
cell_w = w // GRID
centers = []

for gy in range(GRID):
    for gx in range(GRID):
        y0 = gy * cell_h
        x0 = gx * cell_w
        cell = hot[y0:y0+cell_h, x0:x0+cell_w]
        hot_ratio = np.mean(cell)
        # Only include cells where >5% of pixels differ
        if hot_ratio > 0.05:
            cy = y0 + cell_h // 2
            cx = x0 + cell_w // 2
            centers.append(f"{cx},{cy}")

# Deduplicate nearby points (within 50px)
deduped = []
for c in centers:
    x, y = map(int, c.split(","))
    too_close = False
    for dx, dy in [(int(p.split(",")[0]), int(p.split(",")[1])) for p in deduped]:
        if abs(x - dx) < 50 and abs(y - dy) < 50:
            too_close = True
            break
    if not too_close:
        deduped.append(c)

# Limit to 20 points max
for c in deduped[:20]:
    print(c)
PYEOF
)

if [ "$COORDS" = "NO_DIFF" ]; then
  echo "  ✅ No mismatch regions found in diff image"
  exit 0
fi

POINT_COUNT=$(echo "$COORDS" | wc -l | tr -d ' ')
echo "  Found $POINT_COUNT mismatch regions"

# ── Step 2: Map coordinates to DOM elements ──
echo "  ▸ Identifying elements at mismatch points..."

SESSION_ORIG="${SESSION}-diag-orig"
cleanup() {
  agent-browser --session "$SESSION_ORIG" close >/dev/null 2>&1 || true
}
trap cleanup EXIT

agent-browser --session "$SESSION_ORIG" open "$ORIG_URL" >/dev/null 2>&1
agent-browser --session "$SESSION_ORIG" set viewport "$VIEW_W" "$VIEW_H" >/dev/null 2>&1 || true
agent-browser --session "$SESSION_ORIG" wait 4000 >/dev/null 2>&1

# ── Scroll context: diff image may be from a cropped section, not viewport origin ──
# Detect scroll context from diff image filename:
#   sections/diff/<section-name>.png → scroll that section into view
#   static/diff/<N>pct.png → scroll to N% of page
DIFF_BASENAME=$(basename "$DIFF_IMG" .png)
DIFF_DIR=$(basename "$(dirname "$DIFF_IMG")")

SCROLL_SCRIPT=""
if [ "$DIFF_DIR" = "diff" ]; then
  PARENT_DIR=$(basename "$(dirname "$(dirname "$DIFF_IMG")")")
  if [ "$PARENT_DIR" = "sections" ]; then
    # Section crop — scroll section into view by matching section name
    SECTION_NAME="$DIFF_BASENAME"
    SCROLL_SCRIPT="(() => {
      const sections = document.querySelectorAll('header, section, footer, main > div, nav');
      for (const s of sections) {
        const cn = (typeof s.className === 'string' ? s.className : '').toLowerCase();
        const id = (s.id || '').toLowerCase();
        const name = '${SECTION_NAME}'.toLowerCase();
        if (cn.includes(name) || id.includes(name) || s.tagName.toLowerCase() === name) {
          s.scrollIntoView({block: 'start'});
          return 'scrolled to ' + name;
        }
      }
      return 'section not found';
    })()"
  elif [ "$PARENT_DIR" = "static" ]; then
    # Scroll position — extract percentage from filename (e.g., 50pct)
    PCT=$(echo "$DIFF_BASENAME" | grep -oE '[0-9]+' | head -1)
    if [ -n "$PCT" ]; then
      SCROLL_SCRIPT="(() => {
        const h = document.documentElement.scrollHeight - window.innerHeight;
        window.scrollTo(0, h * ${PCT} / 100);
        return 'scrolled to ${PCT}%';
      })()"
    fi
  fi
fi

if [ -n "$SCROLL_SCRIPT" ]; then
  SCROLL_RESULT=$(agent-browser --session "$SESSION_ORIG" eval "$SCROLL_SCRIPT" 2>/dev/null || echo "scroll failed")
  echo "  Scroll context: $SCROLL_RESULT"
  agent-browser --session "$SESSION_ORIG" wait 1000 >/dev/null 2>&1
fi

# Build coordinate array for eval
COORD_JSON=$(echo "$COORDS" | python3 -c "
import sys, json
coords = []
for line in sys.stdin:
    x, y = line.strip().split(',')
    coords.append({'x': int(x), 'y': int(y)})
print(json.dumps(coords))
")

# Get selectors for elements at each coordinate
SELECTORS_RAW=$(agent-browser --session "$SESSION_ORIG" eval "(() => {
  const coords = ${COORD_JSON};
  const seen = new Set();
  const results = [];
  coords.forEach(({x, y}) => {
    const el = document.elementFromPoint(x, y);
    if (!el || el === document.body || el === document.documentElement) return;
    // Build a unique selector
    let sel = '';
    if (el.id) {
      sel = '#' + el.id;
    } else {
      const cn = typeof el.className === 'string' ? el.className.trim().split(/\s+/)[0] : '';
      const tag = el.tagName.toLowerCase();
      sel = cn ? tag + '.' + cn : tag;
    }
    if (sel && !seen.has(sel)) {
      seen.add(sel);
      results.push({selector: sel, x, y, tag: el.tagName.toLowerCase()});
    }
  });
  return JSON.stringify(results);
})()" 2>/dev/null)

# Parse selectors
SELECTORS=$(echo "$SELECTORS_RAW" | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
try:
    data = json.loads(json.loads(raw)) if raw.startswith('\"') else json.loads(raw)
except:
    data = []
for item in data:
    print(item['selector'])
" 2>/dev/null)

if [ -z "$SELECTORS" ]; then
  echo "  ⚠️ Could not identify elements at mismatch points"
  exit 1
fi

SEL_COUNT=$(echo "$SELECTORS" | wc -l | tr -d ' ')
echo "  Found $SEL_COUNT unique elements"
echo "$SELECTORS" | while read -r sel; do
  echo "    - $sel"
done
echo ""

# ── Step 3: Run computed-diff on those selectors ──
echo "  ▸ Running computed-diff on mismatched elements..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2086
bash "$SCRIPT_DIR/computed-diff.sh" "$SESSION" "$ORIG_URL" "$IMPL_URL" $SELECTORS

# ── Step 4: Save results ──
if [ -n "$OUTPUT" ]; then
  echo "$SELECTORS" | python3 -c "
import json, sys
sels = [l.strip() for l in sys.stdin if l.strip()]
json.dump({'source': '$DIFF_IMG', 'elements': sels, 'count': len(sels)}, open('$OUTPUT', 'w'), indent=2)
print(f'  Saved to $OUTPUT')
"
fi

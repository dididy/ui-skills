# Responsive Detection — Step 4

> All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.

## Overview

Detect real breakpoints by sweeping viewport width and measuring layout changes. Do NOT rely on hardcoded 375/768/1440 — find where the layout actually breaks.

## Step 4-A: Extract CSS `@media` rules (hints)

CSS media queries are hints, not ground truth. The layout may break at widths not covered by any `@media` rule.

```bash
agent-browser eval "
(() => {
  const breakpoints = [];
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSMediaRule) breakpoints.push(rule.conditionText);
      }
    } catch(e) {}
  }
  return JSON.stringify([...new Set(breakpoints)], null, 2);
})()"
```

Save the result — these are candidate breakpoints to verify against the sweep.

## Step 4-B: Viewport Sweep — Auto-Detect Breakpoints

Resize the actual viewport and measure layout at each width. This is the only reliable method — JS width overrides and iframe tricks do not trigger real media queries.

**Strategy: 2-pass (coarse → fine) to balance speed and accuracy.**

### Pass 1: Coarse sweep (1440 → 320, step 40px)

```bash
mkdir -p tmp/ref/<component>/responsive

# Register measure function
agent-browser eval "
(() => {
  window.__responsiveMeasure = function() {
    // Adapt selectors to your target component — these are starting points
    const selectors = ['body', 'nav', 'header', 'main', 'footer', 'section', '.hero', '.grid', '.container', '[class*=nav]', '[class*=header]', '[class*=grid]'];
    const props = ['display', 'flexDirection', 'gridTemplateColumns', 'fontSize', 'padding', 'gap', 'visibility', 'position'];
    const result = {};
    selectors.forEach(sel => {
      const el = document.querySelector(sel);
      if (!el) return;
      const s = getComputedStyle(el);
      const vals = {};
      props.forEach(p => vals[p] = s[p]);
      vals._w = el.offsetWidth;
      vals._h = el.offsetHeight;
      vals._visible = el.offsetWidth > 0 && el.offsetHeight > 0;
      result[sel] = vals;
    });
    return result;
  };
  return 'ready';
})()"

# Coarse sweep (1440 → 320 in 40px steps ≈ 29 iterations, ~5s total)
RESULTS="["
FIRST=true
for W in $(seq 1440 -40 320); do
  agent-browser set viewport $W 900
  agent-browser wait 80
  # Verify measure function survived (page may reload mid-sweep)
  CHECK=$(agent-browser eval "(() => typeof window.__responsiveMeasure)()")
  if [ "$CHECK" != "function" ]; then
    # Re-register — paste the same eval block from above
    agent-browser eval "
(() => {
  window.__responsiveMeasure = function() {
    const selectors = ['body', 'nav', 'header', 'main', 'footer', 'section', '.hero', '.grid', '.container', '[class*=nav]', '[class*=header]', '[class*=grid]'];
    const props = ['display', 'flexDirection', 'gridTemplateColumns', 'fontSize', 'padding', 'gap', 'visibility', 'position'];
    const result = {};
    selectors.forEach(sel => {
      const el = document.querySelector(sel);
      if (!el) return;
      const s = getComputedStyle(el);
      const vals = {};
      props.forEach(p => vals[p] = s[p]);
      vals._w = el.offsetWidth;
      vals._h = el.offsetHeight;
      vals._visible = el.offsetWidth > 0 && el.offsetHeight > 0;
      result[sel] = vals;
    });
    return result;
  };
  return 'ready';
})()"
  fi
  M=$(agent-browser eval "(() => JSON.stringify({ width: window.innerWidth, layout: window.__responsiveMeasure() }))()")
  if [ "$FIRST" = true ]; then FIRST=false; else RESULTS="$RESULTS,"; fi
  RESULTS="$RESULTS$M"
done
RESULTS="$RESULTS]"
echo "$RESULTS" > tmp/ref/<component>/responsive/sweep-coarse.json
```

### Detect coarse change zones

```bash
node -e "
const data = JSON.parse(require('fs').readFileSync('./tmp/ref/<component>/responsive/sweep-coarse.json', 'utf8'));
const zones = [];
for (let i = 1; i < data.length; i++) {
  const prev = data[i-1], curr = data[i];
  const changes = [];
  for (const sel of Object.keys(curr.layout || {})) {
    if (!prev.layout?.[sel]) continue;
    for (const prop of Object.keys(curr.layout[sel])) {
      if (prop.startsWith('_')) continue;
      if (curr.layout[sel][prop] !== prev.layout[sel][prop]) {
        changes.push({ selector: sel, property: prop, from: prev.layout[sel][prop], to: curr.layout[sel][prop] });
      }
    }
  }
  if (changes.length) zones.push({ lo: curr.width, hi: prev.width, changes });
}
console.log(JSON.stringify(zones, null, 2));
" > tmp/ref/<component>/responsive/change-zones.json
```

### Pass 2: Fine sweep around change zones (step 5px)

```bash
# Generate fine sweep widths from change zones
node -e "
const z = JSON.parse(require('fs').readFileSync('./tmp/ref/<component>/responsive/change-zones.json', 'utf8'));
const widths = new Set();
z.forEach(x => {
  for (let w = x.hi + 10; w >= Math.max(x.lo - 10, 320); w -= 5) widths.add(w);
});
console.log([...widths].sort((a,b) => b - a).join('\n'));
" > tmp/ref/<component>/responsive/fine-widths.txt

# Verify measure function is still registered (page may have reloaded between passes)
CHECK=$(agent-browser eval "(() => typeof window.__responsiveMeasure)()")
if [ "$CHECK" != "function" ]; then
  agent-browser eval "
(() => {
  window.__responsiveMeasure = function() {
    const selectors = ['body', 'nav', 'header', 'main', 'footer', 'section', '.hero', '.grid', '.container', '[class*=nav]', '[class*=header]', '[class*=grid]'];
    const props = ['display', 'flexDirection', 'gridTemplateColumns', 'fontSize', 'padding', 'gap', 'visibility', 'position'];
    const result = {};
    selectors.forEach(sel => {
      const el = document.querySelector(sel);
      if (!el) return;
      const s = getComputedStyle(el);
      const vals = {};
      props.forEach(p => vals[p] = s[p]);
      vals._w = el.offsetWidth;
      vals._h = el.offsetHeight;
      vals._visible = el.offsetWidth > 0 && el.offsetHeight > 0;
      result[sel] = vals;
    });
    return result;
  };
  return 'ready';
})()"
fi

# Sweep those widths
RESULTS="["
FIRST=true
while read W; do
  agent-browser set viewport $W 900
  agent-browser wait 80
  # Verify measure function survived (page may reload mid-sweep)
  CHECK=$(agent-browser eval "(() => typeof window.__responsiveMeasure)()")
  if [ "$CHECK" != "function" ]; then
    agent-browser eval "
(() => {
  window.__responsiveMeasure = function() {
    const selectors = ['body', 'nav', 'header', 'main', 'footer', 'section', '.hero', '.grid', '.container', '[class*=nav]', '[class*=header]', '[class*=grid]'];
    const props = ['display', 'flexDirection', 'gridTemplateColumns', 'fontSize', 'padding', 'gap', 'visibility', 'position'];
    const result = {};
    selectors.forEach(sel => {
      const el = document.querySelector(sel);
      if (!el) return;
      const s = getComputedStyle(el);
      const vals = {};
      props.forEach(p => vals[p] = s[p]);
      vals._w = el.offsetWidth;
      vals._h = el.offsetHeight;
      vals._visible = el.offsetWidth > 0 && el.offsetHeight > 0;
      result[sel] = vals;
    });
    return result;
  };
  return 'ready';
})()"
  fi
  M=$(agent-browser eval "(() => JSON.stringify({ width: window.innerWidth, layout: window.__responsiveMeasure() }))()")
  if [ "$FIRST" = true ]; then FIRST=false; else RESULTS="$RESULTS,"; fi
  RESULTS="$RESULTS$M"
done < tmp/ref/<component>/responsive/fine-widths.txt
RESULTS="$RESULTS]"
echo "$RESULTS" > tmp/ref/<component>/responsive/sweep-fine.json
```

## Step 4-C: Extract Breakpoints

Parse the fine sweep data to find exact change widths:

```bash
node -e "
const fs = require('fs');
const coarse = JSON.parse(fs.readFileSync('./tmp/ref/<component>/responsive/sweep-coarse.json', 'utf8'));
const fine = JSON.parse(fs.readFileSync('./tmp/ref/<component>/responsive/sweep-fine.json', 'utf8'));
const all = [...coarse, ...fine].sort((a,b) => b.width - a.width);

// Deduplicate by width
const seen = new Set();
const data = all.filter(d => { if (seen.has(d.width)) return false; seen.add(d.width); return true; });

const breakpoints = [];
for (let i = 1; i < data.length; i++) {
  const prev = data[i-1], curr = data[i];
  const changes = [];
  for (const sel of Object.keys(curr.layout || {})) {
    if (!prev.layout?.[sel]) continue;
    for (const prop of Object.keys(curr.layout[sel])) {
      if (prop.startsWith('_')) continue;
      if (curr.layout[sel][prop] !== prev.layout[sel][prop]) {
        changes.push({ selector: sel, property: prop, from: prev.layout[sel][prop], to: curr.layout[sel][prop] });
      }
    }
  }
  if (changes.length) breakpoints.push({ width: curr.width, prevWidth: prev.width, changes });
}

// Cluster nearby breakpoints (within 10px) into single breakpoint
const clustered = [];
for (const bp of breakpoints) {
  const last = clustered[clustered.length - 1];
  if (last && Math.abs(last.width - bp.width) <= 10) {
    last.changes.push(...bp.changes);
    last.width = Math.min(last.width, bp.width);
  } else {
    clustered.push({ ...bp, changes: [...bp.changes] });
  }
}

console.log(JSON.stringify(clustered, null, 2));
" > tmp/ref/<component>/responsive/detected-breakpoints.json
```

## Step 4-D: Capture Per-Breakpoint Screenshots + Styles

For each detected breakpoint, capture a screenshot and extract computed styles. Replace `<bp-width>` for each breakpoint found:

```bash
agent-browser set viewport <bp-width> 900
agent-browser wait 300
agent-browser screenshot tmp/ref/<component>/responsive/ref-<bp-width>.png
agent-browser eval "
(() => {
  // Adapt selectors to match your target component
  const selectors = ['body', 'nav', 'header', 'main', 'section', '.hero', '.grid', '.container'];
  const props = [
    'display', 'flexDirection', 'alignItems', 'justifyContent', 'gap',
    'gridTemplateColumns', 'gridTemplateRows',
    'width', 'height', 'maxWidth', 'minHeight',
    'padding', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
    'margin', 'marginTop', 'marginRight', 'marginBottom', 'marginLeft',
    'fontSize', 'fontWeight', 'lineHeight', 'letterSpacing',
    'color', 'backgroundColor',
    'borderRadius', 'boxShadow',
    'position', 'top', 'right', 'bottom', 'left',
  ];
  const result = {};
  selectors.forEach(sel => {
    const el = document.querySelector(sel);
    if (!el) return;
    const s = getComputedStyle(el);
    result[sel] = {};
    const positionProps = new Set(['top','right','bottom','left','marginTop','marginRight','marginBottom','marginLeft','paddingTop','paddingRight','paddingBottom','paddingLeft']);
    props.forEach(p => {
      const v = s[p];
      if (v && (v !== '0px' || positionProps.has(p)) && (v !== 'none' || p === 'display')) result[sel][p] = v;
    });
  });
  return JSON.stringify({ viewport: window.innerWidth, styles: result }, null, 2);
})()"
```

Save per-breakpoint styles to `tmp/ref/<component>/responsive/styles-<bp-width>.json`.

## Step 4-E: Record Resize Video (optional)

Record a video while stepping down the actual viewport to visually review layout transitions:

```bash
agent-browser set viewport 1440 900
agent-browser record start tmp/ref/<component>/responsive/resize-sweep.webm

# Step viewport down in 20px increments
for W in $(seq 1440 -20 320); do
  agent-browser set viewport $W 900
  agent-browser wait 100
done

agent-browser record stop

# Extract frames for review (10fps is sufficient for resize review)
mkdir -p tmp/ref/<component>/responsive/sweep-frames
ffmpeg -i tmp/ref/<component>/responsive/resize-sweep.webm -vf fps=10 tmp/ref/<component>/responsive/sweep-frames/frame-%04d.png -y
```

## Responsive Verification (Phase A-R / B-R / C-R)

### A-R: Reference responsive screenshots

**Already captured in Step 4-D** (`ref-<bp-width>.png` for each detected breakpoint). Additionally capture the extremes if not already present:

```bash
# Only if not already captured in Step 4-D:
agent-browser set viewport 320 900
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/ref-320.png
agent-browser set viewport 1440 900
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/ref-1440.png
```

### B-R: Implementation responsive screenshots

Same breakpoints, on localhost:

```bash
agent-browser open http://localhost:<port>

# For each detected breakpoint width:
agent-browser set viewport <bp-width> 900
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser wait 300
agent-browser screenshot tmp/ref/<component>/responsive/impl-<bp-width>.png

# Extremes
agent-browser set viewport 320 900
agent-browser screenshot tmp/ref/<component>/responsive/impl-320.png
agent-browser set viewport 1440 900
agent-browser screenshot tmp/ref/<component>/responsive/impl-1440.png
```

### C-R: Responsive comparison table

```
| Breakpoint | Width | Ref                    | Impl                    | Match? | Issue |
|------------|-------|------------------------|-------------------------|--------|-------|
| min        | 320   | responsive/ref-320     | responsive/impl-320     | ✅/❌  |       |
| bp-1       | <w1>  | responsive/ref-<w1>    | responsive/impl-<w1>    | ✅/❌  |       |
| bp-2       | <w2>  | responsive/ref-<w2>    | responsive/impl-<w2>    | ✅/❌  |       |
| ...        | ...   | ...                    | ...                     | ✅/❌  |       |
| max        | 1440  | responsive/ref-1440    | responsive/impl-1440    | ✅/❌  |       |
```

ALL rows must be ✅. For each ❌: identify which layout property differs at that width → fix → re-capture impl only.

## Output

Save to `tmp/ref/<component>/responsive/detected-breakpoints.json`:

```json
{
  "cssMediaQueries": ["(max-width: 768px)", "(max-width: 1024px)"],
  "detectedBreakpoints": [
    {
      "width": 768,
      "changes": [
        { "selector": ".grid", "property": "gridTemplateColumns", "from": "repeat(3, 1fr)", "to": "repeat(2, 1fr)" }
      ]
    },
    {
      "width": 640,
      "changes": [
        { "selector": "nav", "property": "display", "from": "flex", "to": "none" },
        { "selector": ".grid", "property": "gridTemplateColumns", "from": "repeat(2, 1fr)", "to": "1fr" }
      ]
    }
  ],
  "tailwindBreakpoints": {
    "sm": 640,
    "md": 768,
    "lg": 1024
  }
}
```

The `tailwindBreakpoints` field maps detected breakpoints to the nearest Tailwind breakpoint for code generation.

## Fallback

If viewport sweep fails (e.g., CORS, bot detection, or no responsive CSS), fall back to standard breakpoints and note it in `extracted.json`:

| Label   | Width | Height |
|---------|-------|--------|
| mobile  | 375   | 812    |
| tablet  | 768   | 1024   |
| desktop | 1440  | 900    |

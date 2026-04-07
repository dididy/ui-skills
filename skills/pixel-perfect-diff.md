# Pixel-Perfect Diff — Mandatory Numerical Verification

> **This step separates "looks similar" from "pixel-perfect".**
> The Visual Gate (Phase 1) is the pass/fail criterion. Numerical Diagnosis (Phase 2) always runs — because sub-pixel mismatches pass the Visual Gate but are caught by numerical comparison (`font-size: 15px vs 16px`, subtle `letter-spacing` differences, etc.).

---

## Flow

```
Phase 1: Visual Gate (always runs)
  — per-element pixel comparison via DOM clip screenshots
  — record pass/fail

Phase 2: Numerical Diagnosis (always runs — regardless of Phase 1 result)
  — compare all property values via getComputedStyle
  — report numerical mismatches even if Visual Gate passes
  — if numerical mismatches exist, fix and re-run Phase 1

Gate: Phase 1 all pass AND Phase 2 mismatches = 0
```

---

## Phase 1: Visual Gate

### Step V1: Define element list for comparison

Select key elements from each region in regions.json and static sections (header, footer, hero):
- Layout-defining containers
- Typography carriers (heading, nav link, label)
- Visually distinct elements (card, button, image)

Also define the **states** to capture for each element:

| triggerType | exploration | verification |
|---|---|---|
| static (none) | — | idle 1 shot |
| `css-hover` | — | idle + active 2 shots |
| `js-class` | — | idle + active 2 shots |
| `intersection` | — | before + after 2 shots |
| `scroll-driven` | identify transition range (trigger_y, mid_y, settled_y) via video | before + mid + after 3 shots |
| `mousemove` | video only (continuous cursor-position response) | — |
| `auto-timer` | video only (time-based loop) | — |

> For scroll-driven, without an exploration video you cannot determine which y positions to capture clips at. Identify the range via video first, then verify with clips.

### Step V2: Measure ref element rect + capture per state

For each element, activate the state per triggerType and measure the rect.

**idle state (common to all elements):**

```bash
agent-browser --session <project> eval "(() => {
  const selectors = [
    'header',
    'nav a:first-child',
    /* ... */
  ];
  return JSON.stringify(
    selectors.map(sel => {
      const el = document.querySelector(sel);
      if (!el) return { sel, error: 'NOT FOUND' };
      el.scrollIntoView({ block: 'center' });
      const r = el.getBoundingClientRect();
      return { sel, x: r.x, y: r.y, width: r.width, height: r.height };
    })
  );
})()"
```

**active state (css-hover / js-class / intersection elements):**

Re-measure rect immediately after applying state via eval — rect may change due to `transform: scale()` on hover.

```bash
# css-hover: measure after applying CDP hover
agent-browser --session <project> hover <selector>
agent-browser --session <project> wait <transitionDuration + 100>
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  const r = el.getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"

# js-class: measure after classList.add
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  el.classList.add('<triggerClass>');
  return new Promise(resolve => setTimeout(() => {
    const r = el.getBoundingClientRect();
    resolve(JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height }));
  }, <transitionDuration + 100>));
})()"

# intersection: measure after adding class
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  el.classList.add('in-view', 'is-visible');
  return new Promise(resolve => setTimeout(() => {
    const r = el.getBoundingClientRect();
    resolve(JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height }));
  }, <transitionDuration + 100>));
})()"

# scroll-driven: measure each state at y values identified from exploration video
# before (trigger_y - 50)
agent-browser --session <project> eval "(() => window.scrollTo(0, <trigger_y - 50>))()"
agent-browser --session <project> wait 500
agent-browser --session <project> eval "(() => {
  const r = document.querySelector('<selector>').getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"

# mid (mid_y)
agent-browser --session <project> eval "(() => window.scrollTo(0, <mid_y>))()"
agent-browser --session <project> wait 500
agent-browser --session <project> eval "(() => {
  const r = document.querySelector('<selector>').getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"

# after (settled_y + 50)
agent-browser --session <project> eval "(() => window.scrollTo(0, <settled_y + 50>))()"
agent-browser --session <project> wait 500
agent-browser --session <project> eval "(() => {
  const r = document.querySelector('<selector>').getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"
```

### Step V3: Per-element clip screenshot

Capture the same element with the same rect for both ref and impl. **Capture each state separately.**

```bash
# idle (static / css-hover / js-class / intersection — before state activation)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-idle.png

# active (css-hover / js-class — after state activation)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-active.png

# after (intersection — after applying in-view class)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-after.png

# scroll-driven: before / mid / after respectively
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-before.png  # trigger_y - 50
# (re-measure rect at mid_y, then:)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-mid.png     # mid_y
# (re-measure rect at settled_y + 50, then:)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-after.png   # settled_y + 50
```

Filename convention:
- `css-hover` / `js-class`: `<name>-idle.png`, `<name>-active.png`
- `intersection`: `<name>-idle.png` (before-animate), `<name>-after.png` (after-animate)
- `scroll-driven`: `<name>-before.png`, `<name>-mid.png`, `<name>-after.png`
- static elements: `<name>-idle.png`

Repeat identically for impl (change ref → impl in paths).

> **Note:** ref and impl may have different class names (CSS Modules hash). find the same logical element.

### Step V4: Run pixel diff

Run diff for each state separately.

Run for all captured state files.

```bash
# ImageMagick (brew install imagemagick)
# State filenames differ by triggerType — Apply patterns below
for STATE in idle active; do           # css-hover / js-class
  compare -metric AE \
    tmp/ref/capture/clip/ref/<name>-${STATE}.png \
    tmp/ref/capture/clip/impl/<name>-${STATE}.png \
    tmp/ref/capture/clip/diff/<name>-${STATE}.png 2>&1
done

for STATE in before after; do          # intersection
  compare -metric AE \
    tmp/ref/capture/clip/ref/<name>-${STATE}.png \
    tmp/ref/capture/clip/impl/<name>-${STATE}.png \
    tmp/ref/capture/clip/diff/<name>-${STATE}.png 2>&1
done

for STATE in before mid after; do      # scroll-driven
  compare -metric AE \
    tmp/ref/capture/clip/ref/<name>-${STATE}.png \
    tmp/ref/capture/clip/impl/<name>-${STATE}.png \
    tmp/ref/capture/clip/diff/<name>-${STATE}.png 2>&1
done
# → Output = different pixel count. 0 = pass.

# If ImageMagick unavailable, use ffmpeg SSIM instead:
ffmpeg -i tmp/ref/capture/clip/ref/<name>-<state>.png \
       -i tmp/ref/capture/clip/impl/<name>-<state>.png \
       -lavfi "ssim" -f null - 2>&1 | grep SSIM
# → All:1.000000 = exact match
```

> It's common for idle to pass while active/mid/after fail. Run all states without exception.

### Step V5: Judgment

| Result | Criterion |
|------|------|
| ✅ PASS | AE = 0 or SSIM All ≥ 0.995 |
| ❌ FAIL | Otherwise |

> **"Looks approximately the same" is FAIL.** Phase 2 always runs regardless of result.

Open diff images (`diff/<name>-<state>.png`) with the Read tool to visually confirm which regions differ.

### Step V6: Save Visual Gate JSON

```json
{
  "component": "<name>",
  "measuredAt": "<ISO timestamp>",
  "viewport": { "width": 1440, "height": 900 },
  "result": "pass",
  "elements": [
    { "selector": "header", "state": "idle", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".btn", "state": "idle", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".btn", "state": "active", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".hero-text", "state": "before", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".hero-text", "state": "mid", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".hero-text", "state": "after", "ae": 0, "ssim": 1.0, "status": "pass" }
  ]
}
```

**Always run Phase 2 regardless of Phase 1 result.**

---

## Phase 2: Numerical Diagnosis

> **Always runs regardless of Phase 1 result.**
> Sub-pixel mismatches are not caught even when Visual Gate passes. Numerical diagnosis produces the complete report.

### What This Measures

| Property group | Properties |
|---|---|
| Typography | `fontSize`, `fontWeight`, `lineHeight`, `letterSpacing`, `fontFamily`, `textTransform`, `color` |
| Spacing | `paddingTop`, `paddingRight`, `paddingBottom`, `paddingLeft`, `marginTop`, `marginRight`, `marginBottom`, `marginLeft`, `gap`, `rowGap`, `columnGap` |
| Sizing | `width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight` |
| Layout | `display`, `flexDirection`, `alignItems`, `justifyContent`, `gridTemplateColumns`, `gridTemplateRows` |
| Visual | `backgroundColor`, `borderRadius`, `border`, `boxShadow`, `opacity`, `transform` |
| Position | `position`, `top`, `right`, `bottom`, `left` |

### Step P1: Measure ref

**Measure idle state:**

```bash
agent-browser --session <project> eval "(() => {
  const selectors = [
    /* selectors of Phase 1 FAIL elements */
  ];

  const props = [
    'fontSize','fontWeight','lineHeight','letterSpacing','fontFamily',
    'color','backgroundColor','textTransform',
    'paddingTop','paddingRight','paddingBottom','paddingLeft',
    'marginTop','marginRight','marginBottom','marginLeft',
    'gap','rowGap','columnGap',
    'width','height','maxWidth','minWidth',
    'display','flexDirection','alignItems','justifyContent',
    'gridTemplateColumns','gridTemplateRows',
    'borderRadius','boxShadow','border','opacity','transform',
    'position','top','right','bottom','left'
  ];

  const result = {};
  for (const sel of selectors) {
    const el = document.querySelector(sel);
    if (!el) { result[sel] = 'NOT FOUND'; continue; }
    const cs = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    result[sel] = {
      _boundingRect: { width: Math.round(rect.width), height: Math.round(rect.height), top: Math.round(rect.top), left: Math.round(rect.left) }
    };
    for (const p of props) result[sel][p] = cs[p];
  }
  return JSON.stringify(result, null, 2);
})()"
```

Save to `tmp/ref/<component>/ref-styles-idle.json`.

**Measure active / mid / after states:**

Apply state via eval then measure the same props.

```bash
# css-hover: apply CDP hover
agent-browser --session <project> hover <selector>
agent-browser --session <project> wait <transitionDuration + 100>

# js-class: classList.add
agent-browser --session <project> eval "document.querySelector('<sel>').classList.add('<cls>')"
agent-browser --session <project> wait <transitionDuration + 100>

# scroll-driven: measure each state in order at y values from exploration video
# scrollTo for each before → mid → after, wait 500, then measure

agent-browser --session <project> eval "(() => {
  const sel = '<selector>';
  const props = ['color','backgroundColor','borderColor','boxShadow','transform','opacity','filter','fontSize','fontWeight','letterSpacing'];
  const el = document.querySelector(sel);
  if (!el) return JSON.stringify({ error: 'NOT FOUND' });
  const cs = getComputedStyle(el);
  const result = { _state: '<state>' };  // 'active' | 'mid' | 'after'
  for (const p of props) result[p] = cs[p];
  return JSON.stringify(result, null, 2);
})()"
```

Save per state:
- `tmp/ref/<component>/ref-styles-active.json` (css-hover / js-class)
- `tmp/ref/<component>/ref-styles-before.json`, `ref-styles-mid.json`, `ref-styles-after.json` (scroll-driven)

> **CSS Modules site selector lookup:**
> ```bash
> agent-browser eval "document.querySelector('header')?.className"
> ```

### Step P2: Measure impl

Run the same script on the impl URL. Save path:
- idle → `tmp/ref/<component>/impl-styles-idle.json`
- active → `tmp/ref/<component>/impl-styles-active.json` (css-hover / js-class)
- before / mid / after → `tmp/ref/<component>/impl-styles-before.json`, `impl-styles-mid.json`, `impl-styles-after.json` (scroll-driven)

### Step P3: Build Diff Table

Include a state column — The same element may have different values per idle/active/before/mid/after state.

| Element | State | Property | Ref value | Impl value | Status |
|---|---|---|---|---|---|
| `.brand` | idle | `fontSize` | `24px` | `16px` | ❌ |
| `.brand` | idle | `color` | `#000` | `#000` | ✅ |
| `.btn` | active | `backgroundColor` | `#0070f3` | `#005cc5` | ❌ |
| `.hero-text` | mid | `transform` | `translateY(0px) scale(1)` | `translateY(12px) scale(0.95)` | ❌ |

**Rules:**
- `rgb()` vs `rgba()` alpha=1: if rgb values match → ✅
- `width: 1349px` vs `1347px`: within 2px → ✅ (subpixel)
- `width: 72px` vs `810px`: ❌
- **Never declare equal by rounding.** `16px ≠ 14px`

### Step P4: Fix

For each ❌ row:
1. Find the CSS file/rule controlling that property in impl
2. Fix to ref value
3. Re-measure P2 for that element only
4. Confirm ✅

**Repeat until all ❌ become ✅.**

### Step P5: Re-run after fixes

After all fixes, **re-run both Phase 1 Visual Gate and Phase 2 Numerical Diagnosis**.

Phase 1 all pass AND Phase 2 mismatches = 0 → Done.
Otherwise → Re-diagnose.

---

## Gate

```
PIXEL-PERFECT GATE:
□ Phase 1 Visual Gate JSON exists
□ all elements status = "pass" (idle / active / before / mid / after — per triggerType)
□ Phase 2 Numerical Diagnosis complete
□ mismatches = 0

Phase 1 all pass AND mismatches = 0 → Done.
Either falls short → fix and re-run.
"Approximately identical" = FAIL.
```

---

## Anti-patterns

| Anti-pattern | Why forbidden |
|---|---|
| "Screenshots look similar" | The eye cannot catch 2px font differences or 10px spacing errors |
| "Skip numerical diagnosis because Visual Gate passed" | Sub-pixel mismatches may have different values even with AE=0. Phase 2 always runs. |
| "Close enough" | Declaration without criteria. Judge by numbers. |
| Using `offsetWidth` | Rounds to integer. Use `getComputedStyle`. |
| Only diagnose FAIL elements | First check FAIL range via diff image, then measure everything. |

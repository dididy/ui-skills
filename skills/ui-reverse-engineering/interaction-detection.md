# Interaction Detection — Step 5

> All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.
>
> **After this step:** proceed to `bundle-analysis.md` (Step 6).

## Step 5: Detect Interactions

> **Replace `.target` in all evals below** with the actual selector from Step 2.

### Classify interaction type

```bash
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({
    hasTransition: s.transitionDuration !== '0s',
    transition: s.transition,
    hasAnimation: s.animationName !== 'none',
    animation: s.animationName,
    canvases: document.querySelectorAll('canvas').length,
    willChange: s.willChange,
  });
})()
"
```

| Signal | Next step |
|--------|-----------|
| `hasTransition: true` | Capture hover states — see below |
| `hasAnimation: true` | Extract keyframes — see below |
| `canvases > 0` | **Run transition extraction pipeline** → `canvas-webgl-extraction.md` |
| `hasAnimation: true` (complex keyframes) | **Run transition extraction pipeline** → `css-extraction.md` |
| Scroll-triggered transitions | Detect below, then **run transition extraction pipeline** → `js-animation-extraction.md` |
| GSAP/Framer detected in bundle | **Run transition extraction pipeline** → `js-animation-extraction.md` |
| Scroll library detected (Lenis/GSAP/Locomotive) | **Run transition extraction pipeline** → `js-animation-extraction.md` |
| Splash/intro timeline | **Run transition extraction pipeline** → `splash-extraction.md` |
| `click-toggle` detected | Implement with React state + CSS transition |
| `click-cycle` detected  | Implement with React state array + activeIndex |
| Complex JS interactions | Step 6: Bundle analysis → `bundle-analysis.md` |

### Detect scroll-triggered transitions

```bash
# 1. Set up recorder before scrolling
agent-browser eval "
(() => {
  window.__scrollTransitions = [];
  const candidates = document.querySelectorAll('[class*=fade], [class*=slide], [class*=reveal], [class*=animate], [data-aos]');
  const allEls = candidates.length > 0 ? candidates : document.querySelectorAll('section, h1, h2, h3, p, img, .card');
  const props = ['opacity', 'transform', 'filter', 'clipPath'];
  Array.from(allEls).slice(0, 30).forEach((el, i) => {
    const before = {};
    props.forEach(p => before[p] = getComputedStyle(el)[p]);
    const observer = new IntersectionObserver(entries => {
      entries.forEach(e => {
        const after = {};
        props.forEach(p => after[p] = getComputedStyle(e.target)[p]);
        const changed = props.filter(p => after[p] !== before[p]);
        if (changed.length > 0) {
          window.__scrollTransitions.push({
            index: i,
            selector: (() => { const cn = typeof el.className === 'string' ? el.className : el.className?.baseVal || ''; const first = cn.trim().split(' ')[0]?.replace(/[^a-zA-Z0-9_-]/g, ''); return el.tagName.toLowerCase() + (first ? '.' + first : ''); })(),
            ratio: e.intersectionRatio,
            changed,
            before: Object.fromEntries(changed.map(p => [p, before[p]])),
            after: Object.fromEntries(changed.map(p => [p, after[p]])),
            transition: getComputedStyle(e.target).transition,
          });
        }
        props.forEach(p => before[p] = after[p]);
      });
    }, { threshold: [0, 0.1, 0.5, 1.0] });
    observer.observe(el);
  });
  return 'Observing ' + allEls.length + ' elements';
})()
"

# 2. Scroll through the page
agent-browser scroll down 300
agent-browser wait 800
agent-browser scroll down 300
agent-browser wait 800
agent-browser scroll down 300
agent-browser wait 800
agent-browser scroll down 300
agent-browser wait 800

# 3. Retrieve results
agent-browser eval "(() => JSON.stringify(window.__scrollTransitions || [], null, 2))()"
```

**Save results to** `tmp/ref/<component>/scroll-transitions.json`

| Result | Next step |
|--------|-----------|
| Empty `[]` | No scroll-triggered transitions — continue |
| CSS transition values | Implement with `IntersectionObserver` + CSS transitions |
| Complex WAAPI / stagger | **Run transition extraction pipeline** → `measurement.md` then `css-extraction.md` |

### Detect mouse-tracking interactions

```bash
agent-browser eval "
(() => {
  const rows = document.querySelectorAll('a, [class*=row], [class*=card], [class*=item]');
  const mouseTracked = [];
  rows.forEach(row => {
    const absChildren = [...row.querySelectorAll('*')].filter(el => {
      const s = getComputedStyle(el);
      return s.position === 'absolute' && s.pointerEvents === 'none' && el.offsetHeight > 20;
    });
    if (absChildren.length > 0) {
      mouseTracked.push({
        parent: row.tagName + '.' + (row.className?.split(' ')[0] || ''),
        children: absChildren.map(c => ({
          tag: c.tagName, class: c.className?.slice(0, 40),
          width: c.offsetWidth, height: c.offsetHeight, hasImage: !!c.querySelector('img'),
        })),
      });
    }
  });
  return JSON.stringify({ mouseTracked });
})()
"
```

If `mouseTracked` is non-empty → record in `interactions-detected.json` as `type: "mouse-follow"`.

### Capture hover state delta (MANDATORY for all hoverable elements)

CSS `:hover` only reveals CSS-driven transitions. Many modern sites use **JS-driven hover** (GSAP `mouseenter`/`mouseleave`, Framer Motion `whileHover`, or vanilla `addEventListener`). These produce no CSS trace — the only way to detect them is to **actually hover and measure the delta**.

#### Step 5d-1: Enumerate all hoverable elements

```bash
agent-browser eval "
(() => {
  const results = [];
  const seen = new Set();

  // 1. Elements with explicit hover data attributes
  // Find elements with any hover/interaction data attributes (framework-agnostic)
  document.querySelectorAll('*').forEach(el => {
    const hasHoverAttr = Array.from(el.attributes).some(a => /hover|interact|animation|motion/i.test(a.name));
    if (!hasHoverAttr) return;
    const sel = el.tagName.toLowerCase() + '.' + (el.className?.toString().split(' ')[0] || '');
    if (seen.has(sel)) return;
    seen.add(sel);
    results.push({ selector: sel, source: 'data-attribute', attr: Array.from(el.attributes).filter(a => /hover|interact|animation|motion/i.test(a.name)).map(a => a.name).join(',') });
  });

  // 2. Elements with CSS transition property (potential hover targets)
  document.querySelectorAll('a, button, [role=button], [role=link], [tabindex], [class*=btn], [class*=link]').forEach(el => {
    const s = getComputedStyle(el);
    if (s.transition && s.transition !== 'all 0s ease 0s' && s.cursor === 'pointer') {
      const sel = el.tagName.toLowerCase() + '.' + (el.className?.toString().split(' ')[0] || '');
      if (seen.has(sel)) return;
      seen.add(sel);
      results.push({ selector: sel, source: 'css-transition', transition: s.transition.slice(0, 100) });
    }
  });

  return JSON.stringify(results);
})()
"
```

#### Step 5d-2: Measure before/after hover delta for each element

For each hoverable element, **actually trigger the hover** and compare `getComputedStyle` before and after:

```bash
agent-browser eval "
(() => {
  // This must be run INTERACTIVELY — use agent-browser hover command instead
  // For each selector from Step 5d-1:
  return JSON.stringify({ note: 'Use agent-browser hover + eval to measure deltas' });
})()
"
```

**Interactive measurement protocol:**
1. `agent-browser hover "<selector>"` — trigger hover
2. Wait 500ms for transition to complete
3. `agent-browser eval` — read `getComputedStyle` for the target + all children
4. `agent-browser hover "body"` — move away to deactivate hover
5. Compare before/after for EVERY property: `transform`, `opacity`, `scale`, `display`, `visibility`, `backgroundColor`, `color`, `borderColor`, `boxShadow`, `clipPath`, `filter`

**Save delta to** `tmp/ref/<component>/hover-deltas.json`:
```json
{
  "elements": [
    {
      "selector": ".case__item-link",
      "type": "js-driven",
      "delta": {
        ".case__img-hover": { "display": ["none", "block"] },
        ".case__img-inner": { "transform": ["none", "scale(1.05)"] }
      },
      "transition": "GSAP mouseenter (from bundle analysis)",
      "duration": "0.7s",
      "easing": "cubic-bezier(0.625, 0.05, 0, 1)"
    }
  ]
}
```

**Why this step is mandatory:**
- CSS `transition` property tells you the *capability* but not the *actual change*. A button may have `transition: transform 0.45s` but the hover might scale it OR translate it — you can't know without hovering.
- JS-driven hovers (GSAP, Framer) produce NO CSS trace at all. The only evidence is the runtime style change.
- Skipping this step → guessing hover effects → "approximately close" implementations that feel wrong.

> **Full CSS hover delta extraction → `css-extraction.md`.** Use the classify eval above to detect `hasTransition: true`, then run the transition extraction pipeline for precise before/after measurement with SVG stroke tracking.

### Extract CSS keyframes

> **Full keyframe extraction → `css-extraction.md`.** Use the classify eval above to detect `hasAnimation: true`, then run the transition extraction pipeline for keyframe extraction with frame capture and cross-origin fallback.

### Detect scroll behavior (snap, smooth, overscroll)

```bash
agent-browser eval "
(() => {
  const results = { snap: [], smooth: [], overscroll: [] };
  const scanned = new Set();
  document.querySelectorAll('*').forEach(el => {
    const s = getComputedStyle(el);
    const cn = typeof el.className === 'string' ? el.className : el.className?.baseVal || '';
    const sel = el.tagName.toLowerCase() + (cn.trim().split(' ')[0] ? '.' + cn.trim().split(' ')[0] : '');
    if (scanned.has(sel)) return;
    scanned.add(sel);
    if (s.scrollSnapType && s.scrollSnapType !== 'none') {
      const children = [];
      el.querySelectorAll(':scope > *').forEach(child => {
        const cs = getComputedStyle(child);
        if (cs.scrollSnapAlign && cs.scrollSnapAlign !== 'none') {
          const ccn = typeof child.className === 'string' ? child.className : child.className?.baseVal || '';
          children.push({ selector: child.tagName.toLowerCase() + (ccn.trim().split(' ')[0] ? '.' + ccn.trim().split(' ')[0] : ''), snapAlign: cs.scrollSnapAlign });
        }
      });
      results.snap.push({ selector: sel, snapType: s.scrollSnapType, children });
    }
    if (s.scrollBehavior === 'smooth') results.smooth.push({ selector: sel });
    if (s.overscrollBehavior && s.overscrollBehavior !== 'auto auto' && s.overscrollBehavior !== 'auto')
      results.overscroll.push({ selector: sel, behavior: s.overscrollBehavior });
  });
  return JSON.stringify(results, null, 2);
})()
"
```

### Save interaction detection results (MANDATORY)

Save a summary to `tmp/ref/<component>/interactions-detected.json`. Include all discovered interactions from the evals above. If zero found, save `{ "interactions": [], "note": "static component" }`. This file is required by the Phase 2 Gate and by Step 9.

### Capture idle + active states (MANDATORY for hover/click)

> **Capture is delegated to `/ui-capture` Phase 2C.** Do not capture here — interaction-detection only detects. After saving `interactions-detected.json`, Step 5b triggers `/ui-capture` Phase 2B–2E which captures idle+active pairs for every detected interaction.

**Gate:** `validate-gate.sh pre-generate` checks idle+active pairs exist (produced by ui-capture).

### Extract click-transition structure (MANDATORY for content-swap)

When clicking triggers a **content swap**, extract the transition's DOM structure at 100ms after click — not just the visual result. See the eval script for capturing `paneCount`, `zIndex`, `background`, `animationName` to determine single-pane vs two-pane, old-on-top vs new-on-top patterns.

Save to `tmp/ref/<component>/transition-structure.json`.

### Post-detection sanitization check

```bash
grep -iE 'ignore previous|you are now|system prompt|<script|javascript:|data:text' \
  tmp/ref/<component>/interactions-detected.json && echo "Warning: Suspicious content" || echo "Clean"
```

---

## Step 5e: Classify Drag/Swipe Effects

| Effect type | Detection | Implementation |
|---|---|---|
| **State flip** (carousel) | Drag → snap to new position | `pointerup` checks `dx > threshold` → `goTo()`. **No translateX during drag.** |
| **Transform tracking** (slider) | Element follows pointer in real-time | `pointermove` applies `translateX(dx)`. `pointerup` snaps. |
| **Parallax tracking** (cursor follow) | Elements shift with cursor | `pointermove` (global) → update with lerp/decay. |

**Critical rule:** State-flip drags must NOT apply `translateX` during drag.

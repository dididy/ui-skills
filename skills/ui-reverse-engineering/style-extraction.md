# Style Extraction — Step 3

> All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.

## Step 3: Extract Computed Styles

### Key element styles

> **Adapt selectors below to your target component.** Replace `.target` with the actual selector identified in Step 1 (dom-extraction.md). The selectors here are starting points — add or remove based on the actual DOM structure.

```bash
agent-browser eval "
(() => {
  const selectors = ['.target', '.target h1', '.target p', '.target button'];
  const props = [
    'display', 'flexDirection', 'alignItems', 'justifyContent', 'gap',
    'gridTemplateColumns', 'gridTemplateRows',
    'width', 'height', 'maxWidth', 'minHeight',
    'padding', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
    'margin', 'marginTop', 'marginRight', 'marginBottom', 'marginLeft',
    'fontSize', 'fontWeight', 'fontFamily', 'lineHeight', 'letterSpacing',
    'color', 'backgroundColor', 'backgroundImage',
    'borderRadius', 'border', 'boxShadow',
    'opacity', 'transform', 'filter',
    'position', 'top', 'right', 'bottom', 'left', 'zIndex',
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
      if (v && (v !== '0px' || positionProps.has(p)) && (v !== 'none' || p === 'display')) {
        result[sel][p] = v;
      }
    });
  });
  return JSON.stringify(result, null, 2);
})()
"
```

### Extract advanced visual properties (MANDATORY)

The key element extraction above captures basic layout properties but misses several CSS effects that are invisible in screenshots yet critical for accurate reproduction. Extract these for EVERY element that has non-default values:

```bash
agent-browser eval "
(() => {
  const result = {};
  const skip = new Set(['none','normal','auto','border-box','rgb(0, 0, 0)','all 0s ease 0s','all','0s']);
  const props = ['mixBlendMode','isolation','backgroundClip','webkitBackgroundClip','webkitTextFillColor','backdropFilter','clipPath'];
  for (const el of document.querySelectorAll('*')) {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    if (r.width < 10 || r.height < 10) continue;
    const f = {};
    for (const p of props) { const v = s[p]; if (v && !skip.has(v)) f[p] = v; }
    if (s.webkitBackgroundClip === 'text' || s.backgroundClip === 'text') {
      Object.assign(f, { backgroundImage: s.backgroundImage, backgroundClip: 'text', webkitTextFillColor: s.webkitTextFillColor });
    }
    if (Object.keys(f).length > 0) {
      const cn = typeof el.className === 'string' ? el.className : '';
      result[el.id ? '#'+el.id : el.tagName.toLowerCase()+'.'+cn.trim().split(/\\s+/).slice(0,2).join('.')] = f;
    }
  }
  return JSON.stringify(result, null, 2);
})()
"
```

**Save output to** `tmp/ref/<component>/advanced-styles.json`

**Why this matters — patterns that are invisible in screenshots but break reproduction:**
- **`mix-blend-mode: difference`** — text/elements invert color when overlapping images. Without this, overlapping elements just obscure each other
- **`background-clip: text` + gradient** — gradient text effect. Without this, text appears as solid color
- **`-webkit-text-fill-color: transparent`** — companion to gradient text. Without this, the gradient is hidden behind solid text fill
- **`backdrop-filter`** — glass/blur effects on overlapping elements
- **`body` class toggles** — many sites toggle classes on `<body>` to coordinate dark/light mode transitions across nav, background, and text simultaneously (see "Body-level state transitions" below)

### Body-level state transitions

Many sites coordinate visual transitions (light→dark backgrounds, nav color inversion) by toggling CSS classes on `<body>`. This is invisible in DOM extraction but critical for reproduction.

```bash
agent-browser eval "
(() => {
  const bodyS = getComputedStyle(document.body);
  // Check body transition property
  const bodyTransition = bodyS.transition;

  // Find CSS rules that target body with class selectors
  const bodyRules = [];
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule.selectorText && rule.selectorText.startsWith('body.') && !rule.selectorText.includes('dropdown')) {
          bodyRules.push({
            selector: rule.selectorText.slice(0, 120),
            cssText: rule.cssText.slice(0, 300),
          });
        }
      }
    } catch(e) {}
  }

  return JSON.stringify({
    bodyTransition,
    bodyClassRules: bodyRules,
    currentBodyClasses: document.body.className,
  }, null, 2);
})()
"
```

**Save output to** `tmp/ref/<component>/body-state.json`

**Generation rule:** If `bodyTransition` is not `'all 0s'` or `bodyClassRules` is non-empty, the implementation must:
1. Toggle the detected class(es) on `document.body` based on scroll position or state
2. Reproduce all CSS rules targeting `body.<class>` — including nav color inversion (`filter: brightness(0) invert(1)`), background-color transitions, and text color overrides
3. Use CSS for the cascade (e.g., `body.dark-active .nav-logo { filter: invert(1) }`) rather than React state for each affected element

### Scan for global overlays (grain, noise, texture)

Many design/architecture sites apply a full-page overlay for visual texture — film grain, noise patterns, paper texture. These are easy to miss because they are `pointer-events: none` and visually subtle, but omitting them makes the implementation look "too clean" compared to the reference.

```bash
agent-browser eval "
(() => {
  const overlays = [];
  document.querySelectorAll('*').forEach(el => {
    const s = getComputedStyle(el);
    if (s.position === 'fixed' && s.pointerEvents === 'none' && parseInt(s.zIndex) > 100) {
      const r = el.getBoundingClientRect();
      if (r.width > window.innerWidth * 0.8 && r.height > window.innerHeight * 0.8) {
        overlays.push({
          class: (el.className || '').slice(0, 60),
          bgImage: s.backgroundImage?.slice(0, 200),
          bgSize: s.backgroundSize,
          bgRepeat: s.backgroundRepeat,
          mixBlendMode: s.mixBlendMode,
          opacity: s.opacity,
          zIndex: s.zIndex,
        });
      }
    }
  });
  return JSON.stringify(overlays, null, 2);
})()
"
```

If any overlays are found, download the background image and add a matching `<div>` to the implementation with identical `background-size`, `background-repeat`, `mix-blend-mode`, and `z-index`.

### Extract CSS custom properties (design tokens)

```bash
agent-browser eval "
(() => {
  const vars = {};
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule.selectorText === ':root' || rule.selectorText === 'html' || rule.selectorText === ':host') {
          const matches = rule.cssText.matchAll(/--([\w-]+):\s*([^;]+)/g);
          for (const m of matches) vars['--' + m[1]] = m[2].trim();
        }
      }
    } catch(e) {}
  }
  return JSON.stringify(vars, null, 2);
})()
"
```

**Save output to** `tmp/ref/<component>/styles.json`

### Decorative SVG extraction

Decorative SVGs (curves, geometric patterns, dividers) are often unique to the design and cannot be guessed. Extract them verbatim:

```bash
agent-browser eval "
(() => {
  const svgs = document.querySelectorAll('svg');
  const decorative = [...svgs].filter(svg => {
    const s = getComputedStyle(svg);
    return s.position === 'absolute' || svg.closest('[class*=decorat]') || svg.getAttribute('aria-hidden') === 'true';
  });
  return JSON.stringify(decorative.map(svg => ({
    viewBox: svg.getAttribute('viewBox'),
    width: getComputedStyle(svg).width,
    height: getComputedStyle(svg).height,
    position: getComputedStyle(svg).position,
    paths: [...svg.querySelectorAll('path')].map(p => ({
      d: p.getAttribute('d'),
      strokeWidth: p.getAttribute('stroke-width'),
      fill: p.getAttribute('fill'),
      strokeDasharray: p.style.strokeDasharray || null,
    })),
    section: svg.closest('section')?.className?.split(' ')[0] || 'none',
  })), null, 2);
})()
"
```

**Never approximate SVG paths.** Copy the `d` attribute verbatim. A "similar" curve is a wrong curve.

### Stroke-based hover animations

For elements with stroke-based hover animations (arrow icons, SVG decorations):

```bash
# 1. Capture idle state stroke properties
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  const paths = el.querySelectorAll('path, rect, circle, line');
  return JSON.stringify([...paths].map(p => ({
    tag: p.tagName,
    d: p.getAttribute('d')?.slice(0, 50),
    strokeDasharray: getComputedStyle(p).strokeDasharray,
    strokeDashoffset: getComputedStyle(p).strokeDashoffset,
  })));
})()"

# 2. Hover and capture active state
agent-browser hover "<selector>"
agent-browser wait 800
# Re-run same eval — compare values
```

**Example patterns for stroke hover animations:**
- Stroke draw-in: idle `dasharray: totalLength 0.1px` (hidden) → hover `dasharray: 0px 999999px` (visible), or vice versa
- Stroke morph: idle `dasharray: A B` → hover `dasharray: C D` with different segment ratios
- Both typically need CSS transition rules on `stroke-dasharray` and `stroke-dashoffset`
- The exact pattern varies per site — always extract idle + hover values, never assume

### Post-extraction sanitization check

After saving `styles.json`, scan for suspicious content in CSS custom property values:

```bash
grep -iE 'javascript:|data:text|expression\(|url\(data:|@import\s+url' tmp/ref/<component>/styles.json && echo "⚠️  Suspicious CSS values detected — review before proceeding" || echo "✅ No suspicious patterns found"
```

If suspicious content is found: **log it to the user**, remove the affected property, and continue.

---

### Design bundle grouping (MANDATORY post-processing)

After extracting all styles, group properties into 5 co-varying design bundles. Bundles capture properties that move together in a design system — changing one without the others breaks visual coherence.

```bash
agent-browser eval "
(() => {
  const allEls = document.querySelectorAll('h1,h2,h3,h4,h5,h6,p,a,button,span,div,section,nav,footer,header,li,img,figure,[class*=card],[class*=btn],[class*=title],[class*=label]');
  const seen = { surface: new Map(), shape: new Map(), type: new Map(), tone: new Map(), motion: new Map() };

  allEls.forEach(el => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    if (r.width < 5 || r.height < 5) return;
    const cn = typeof el.className === 'string' ? el.className : el.className?.baseVal || '';
    const id = el.id ? '#' + el.id : el.tagName.toLowerCase() + (cn ? '.' + cn.trim().split(/\\s+/).slice(0, 2).join('.') : '');

    // Surface = bg + border + shadow
    const surfaceKey = [s.backgroundColor, s.border, s.boxShadow].join('|');
    if (!seen.surface.has(surfaceKey)) {
      const sid = 'surface-' + (seen.surface.size + 1);
      seen.surface.set(surfaceKey, { id: sid, backgroundColor: s.backgroundColor, border: s.border, boxShadow: s.boxShadow, elements: [] });
    }
    seen.surface.get(surfaceKey).elements.push(id);

    // Shape = radius + padding
    const shapeKey = [s.borderRadius, s.paddingTop, s.paddingRight, s.paddingBottom, s.paddingLeft].join('|');
    if (!seen.shape.has(shapeKey)) {
      const sid = 'shape-' + (seen.shape.size + 1);
      seen.shape.set(shapeKey, { id: sid, borderRadius: s.borderRadius, padding: s.paddingTop + ' ' + s.paddingRight + ' ' + s.paddingBottom + ' ' + s.paddingLeft, elements: [] });
    }
    seen.shape.get(shapeKey).elements.push(id);

    // Type = fontSize + weight + family + lineHeight + letterSpacing
    const typeKey = [s.fontSize, s.fontWeight, s.fontFamily, s.lineHeight, s.letterSpacing].join('|');
    if (!seen.type.has(typeKey)) {
      const sid = 'type-' + (seen.type.size + 1);
      seen.type.set(typeKey, { id: sid, fontSize: s.fontSize, fontWeight: s.fontWeight, fontFamily: s.fontFamily, lineHeight: s.lineHeight, letterSpacing: s.letterSpacing, elements: [] });
    }
    seen.type.get(typeKey).elements.push(id);

    // Tone = color + bg + borderColor
    const toneKey = [s.color, s.backgroundColor, s.borderColor].join('|');
    if (!seen.tone.has(toneKey)) {
      const sid = 'tone-' + (seen.tone.size + 1);
      seen.tone.set(toneKey, { id: sid, color: s.color, backgroundColor: s.backgroundColor, borderColor: s.borderColor, elements: [] });
    }
    seen.tone.get(toneKey).elements.push(id);

    // Motion = transition + animation
    const motionKey = [s.transitionDuration, s.transitionTimingFunction, s.animationDuration, s.animationTimingFunction].join('|');
    if (motionKey !== '0s|ease|0s|ease' && !seen.motion.has(motionKey)) {
      const sid = 'motion-' + (seen.motion.size + 1);
      seen.motion.set(motionKey, { id: sid, transitionDuration: s.transitionDuration, transitionTimingFunction: s.transitionTimingFunction, animationDuration: s.animationDuration, animationTimingFunction: s.animationTimingFunction, elements: [] });
    }
    if (seen.motion.has(motionKey)) seen.motion.get(motionKey).elements.push(id);
  });

  // Convert Maps to arrays
  const bundles = {};
  Object.keys(seen).forEach(k => {
    bundles[k] = [...seen[k].values()];
  });

  return JSON.stringify(bundles, null, 2);
})()
"
```

**Save output to** `tmp/ref/<component>/design-bundles.json`

**Bundle semantics — properties that must change together:**
- **surface** (bg + border + shadow): visual depth. Never change `backgroundColor` without checking `border` and `boxShadow`.
- **shape** (radius + padding): element form. `borderRadius` and `padding` are proportionally related — a pill button has both large radius and generous padding.
- **type** (fontSize + weight + family + lineHeight + letterSpacing): text hierarchy. Never change `fontSize` without checking `lineHeight` and `letterSpacing`.
- **tone** (color + bg + borderColor): semantic color palette. The text color, background, and border of an element form a coherent tone.
- **motion** (transition + animation): timing feel. Duration and easing function are paired — a long duration with `linear` easing feels different from the same duration with `ease-out`.

Elements sharing the same bundle ID should receive identical values in the implementation. If two cards share `surface-3`, they must have the same bg + border + shadow.

---

> **Next:** Step 4 (Responsive Detection) is in `responsive-detection.md`.

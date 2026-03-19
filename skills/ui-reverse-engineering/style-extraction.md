# Style Extraction — Steps 3 & 4

> All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.

## Step 3: Extract Computed Styles

### Key element styles

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
    props.forEach(p => {
      const v = s[p];
      if (v && v !== 'none' && v !== '0px') {
        result[sel][p] = v;
      }
    });
  });
  return JSON.stringify(result, null, 2);
})()
"
```

### Extract CSS custom properties (design tokens)

```bash
agent-browser eval "
(() => {
  const vars = {};
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule.selectorText === ':root') {
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

---

## Step 4: Extract Responsive Styles

Extract actual breakpoints from CSS first:

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
})()
"
```

**Use the widths extracted above.** If the result is empty, either the site has no `@media` rules or CORS blocked stylesheet access — fall back to the defaults below (375 / 768 / 1440) and note this in `extracted.json`.

Repeat this block for each breakpoint — replace `<width>`, `<height>`, and `<label>` with actual values:

```bash
# <label> (<width>px) — e.g. Mobile (375px), Tablet (768px), Desktop (1440px)
agent-browser set viewport <width> <height>
agent-browser screenshot tmp/ref/<component>/<label>.png
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({ viewport: window.innerWidth, display: s.display, flexDirection: s.flexDirection, fontSize: s.fontSize, padding: s.padding, width: s.width });
})()
"
```

Default fallback breakpoints (use only when no `@media` rules found):

| Label   | Width | Height |
|---------|-------|--------|
| mobile  | 375   | 812    |
| tablet  | 768   | 1024   |
| desktop | 1440  | 900    |

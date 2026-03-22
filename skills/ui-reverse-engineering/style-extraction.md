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

### Post-extraction sanitization check

After saving `styles.json`, scan for suspicious content in CSS custom property values:

```bash
grep -iE 'javascript:|data:text|expression\(|url\(data:|@import\s+url' tmp/ref/<component>/styles.json && echo "⚠️  Suspicious CSS values detected — review before proceeding" || echo "✅ No suspicious patterns found"
```

If suspicious content is found: **log it to the user**, remove the affected property, and continue.

---

> **Next:** Step 4 (Responsive Detection) is in `responsive-detection.md`.

# Pixel-Perfect Diff — Mandatory Numerical Verification

> **This is the gate that separates "looks similar" from "pixel-perfect."**
> Screenshot comparison misses 10px spacing errors, 2px font-size differences, and wrong font-weight.
> This step is MANDATORY before any verification can be declared PASS.

---

## What This Measures

For every key element in every section, extract and compare:

| Property group | Properties |
|---|---|
| Typography | `fontSize`, `fontWeight`, `lineHeight`, `letterSpacing`, `fontFamily`, `textTransform`, `color` |
| Spacing | `paddingTop`, `paddingRight`, `paddingBottom`, `paddingLeft`, `marginTop`, `marginRight`, `marginBottom`, `marginLeft`, `gap`, `rowGap`, `columnGap` |
| Sizing | `width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight` |
| Layout | `display`, `flexDirection`, `alignItems`, `justifyContent`, `gridTemplateColumns`, `gridTemplateRows` |
| Visual | `backgroundColor`, `borderRadius`, `border`, `boxShadow`, `opacity`, `transform` |
| Position | `position`, `top`, `right`, `bottom`, `left` |

---

## Step P1: Define Key Elements

Before measuring, list the key elements for this component. These are elements that are:
- Visible at first render (not hover-only)
- Layout-defining (containers, headings, major sections)
- Typography carriers (text nodes, labels, nav links)

Example for a Header:
```
- .header (container)
- .brand / logo text
- nav links (first link as representative)
- icon buttons (first button)
```

---

## Step P2: Measure Reference

Open the reference site and measure each key element. Use this script (run once, captures all elements):

```bash
agent-browser eval "(() => {
  const selectors = [
    /* Replace with actual selectors from dom-extraction step */
    /* Use ref site's actual class names (may be CSS Modules hashed) */
    /* Discover them via: document.querySelector('header').className */
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

Save output to `tmp/ref/<component>/ref-styles.json`.

> **Selector discovery for CSS Modules sites:** Reference sites often use hashed class names like `style_header__tjhHk`. Discover real selectors:
> ```bash
> agent-browser eval "document.querySelector('header')?.className"
> agent-browser eval "document.querySelector('nav a')?.className"
> ```
> Use the discovered class names in the selectors array.

---

## Step P3: Measure Implementation

Open the local implementation and measure the same logical elements using their local class names:

```bash
agent-browser eval "(() => {
  const selectors = [
    /* Use LOCAL class names matching the same logical elements */
    /* These will differ from ref if using CSS Modules */
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

Save output to `tmp/ref/<component>/impl-styles.json`.

---

## Step P4: Build Diff Table

For every element × property pair, produce a structured diff. **Omit a property from the table ONLY IF both ref and impl values are identical AND the value is a trivially zero-state (`none`, `auto`, `0px`). Never omit a property where ref ≠ impl, regardless of the value.**

Format:

| Element | Property | Ref value | Impl value | Status |
|---|---|---|---|---|
| `.brand` | `fontSize` | `24px` | `16px` | ❌ MISMATCH |
| `.brand` | `fontWeight` | `600` | `400` | ❌ MISMATCH |
| `.brand` | `color` | `rgb(25, 25, 25)` | `rgb(25, 25, 25)` | ✅ |
| `.header` | `height` | `72px` | `72px` | ✅ |
| `nav a` | `fontSize` | `14px` | `14px` | ✅ |
| `nav a` | `fontWeight` | `600` | `600` | ✅ |

**Rules:**
- `rgb()` vs `rgba()` with alpha=1: treat as same color if rgb values match
- Computed `lineHeight` of `normal` = browser default (~1.2): match if both are `normal`
- `width: 1349px` vs `1347px`: within 2px = ✅ (subpixel rendering)
- `width: 72px` vs `810px`: obviously different = ❌ even if "looks fine" in screenshot
- **Never round to nearest 10 and declare match.** `16px ≠ 14px`.

---

## Step P5: Fix All Mismatches

For each ❌ row:
1. Identify which CSS file/rule controls that property in the implementation
2. Apply the exact value from the Ref column
3. Re-measure (run P3 again for the affected element only)
4. Update the diff table row to ✅

**Repeat until diff table has 0 ❌ rows.**

---

## Step P6: Write pixel-perfect-diff.json

After all ❌ rows are fixed, save the final diff:

```json
{
  "component": "<component-name>",
  "measuredAt": "<ISO timestamp>",
  "refUrl": "<reference URL>",
  "implUrl": "<local URL>",
  "viewport": { "width": 1440, "height": 900 },
  "result": "pass",
  "totalElements": 12,
  "totalProperties": 156,
  "mismatches": 0,
  "diff": [
    { "element": ".brand", "property": "fontSize", "ref": "24px", "impl": "24px", "status": "pass" },
    { "element": ".brand", "property": "fontWeight", "ref": "600", "impl": "600", "status": "pass" }
  ]
}
```

`"result"` MUST be `"pass"` (0 mismatches). If any mismatch remains, `"result": "fail"` and the verification step must not advance.

---

## Gate

```
PIXEL-PERFECT GATE:
□ ref-styles.json exists with measurements for all key elements
□ impl-styles.json exists with measurements for all key elements
□ pixel-perfect-diff.json exists
□ pixel-perfect-diff.json → "result": "pass"
□ pixel-perfect-diff.json → "mismatches": 0

"거의 동일" (approximately same) = FAIL.
Only "mismatches": 0 = PASS.
```

---

## Anti-patterns (explicitly forbidden)

| Anti-pattern | Why forbidden |
|---|---|
| "The screenshot looks the same" | Eyeball misses 2px font differences, 10px spacing errors |
| "It's close enough" | There is no "close enough". Fix the number. |
| Measuring one element and extrapolating | Each element must be measured independently |
| Using `offsetWidth` instead of `getComputedStyle` | `offsetWidth` is integer-rounded; `getComputedStyle` returns exact values |
| Skipping this step because agent-browser is slow | Performance does not justify skipping correctness |
| Only measuring the properties you already suspect are wrong | Measure ALL properties in the list — you don't know what you don't know |

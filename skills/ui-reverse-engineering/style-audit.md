# Style Audit — Post-Implementation Class-Level Comparison

After code generation (Step 7), before or alongside visual verification (Step 8), run a **systematic style audit** that compares computed styles of matching elements between the reference site and the implementation.

> This catches: wrong font-size, wrong font-weight, wrong SVG (placeholder instead of original), wrong spacing, wrong colors, wrong border-radius — any property-level mismatch that screenshots might miss at a glance.

---

## When to run

- **After Step 7** (code generation) — before starting visual verification
- **After each fix iteration** — to confirm fixes and catch regressions
- **On demand** — user says "the text looks wrong" or "something's off"

---

## Step A1: Build selector map on reference site

Extract all semantically meaningful elements with their selectors and key computed properties.

```bash
agent-browser --session <ref-session> eval "(() => {
  const selectors = [];
  const seen = new Set();

  // Target: headings, paragraphs, links, buttons, images, sections, nav
  const targets = document.querySelectorAll('h1, h2, h3, h4, p, a, button, img, svg, section, nav, footer, header, [class*=title], [class*=label], [class*=card], [class*=btn]');

  targets.forEach(el => {
    const cn = typeof el.className === 'string' ? el.className : el.className?.baseVal || '';
    const first = cn.trim().split(/\s+/)[0]?.replace(/[^a-zA-Z0-9_-]/g, '');
    const sel = el.tagName.toLowerCase() + (first ? '.' + first : '');
    if (seen.has(sel)) return;
    seen.add(sel);

    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    if (r.height < 1) return;

    selectors.push({
      selector: sel,
      text: el.textContent?.trim()?.slice(0, 40) || null,
      tagName: el.tagName,
      // Typography
      fontSize: s.fontSize,
      fontWeight: s.fontWeight,
      fontFamily: s.fontFamily?.slice(0, 40),
      lineHeight: s.lineHeight,
      letterSpacing: s.letterSpacing,
      textTransform: s.textTransform !== 'none' ? s.textTransform : null,
      color: s.color,
      // Layout
      width: Math.round(r.width) + 'px',
      height: Math.round(r.height) + 'px',
      padding: s.padding,
      margin: s.margin,
      // Visual
      backgroundColor: s.backgroundColor !== 'rgba(0, 0, 0, 0)' ? s.backgroundColor : null,
      borderRadius: s.borderRadius !== '0px' ? s.borderRadius : null,
      border: s.border !== '0px none rgb(0, 0, 0)' ? s.border : null,
      boxShadow: s.boxShadow !== 'none' ? s.boxShadow?.slice(0, 60) : null,
      // Position
      position: s.position !== 'static' ? s.position : null,
      display: s.display,
      gap: s.gap !== 'normal' ? s.gap : null,
      // Image/SVG specific
      src: el.tagName === 'IMG' ? el.src?.slice(-60) : null,
      svgContent: el.tagName === 'svg' ? (el.innerHTML?.length > 0 ? 'has-content' : 'empty') : null,
    });
  });

  return JSON.stringify(selectors, null, 2);
})()"
```

**Save to** `tmp/ref/<component>/ref-styles-audit.json`

---

## Step A2: Build selector map on implementation

Run the EXACT same eval on localhost:

```bash
agent-browser --session <impl-session> eval "(() => {
  // Same eval as Step A1 — copy verbatim
})()"
```

**Save to** `tmp/ref/<component>/impl-styles-audit.json`

---

## Step A3: Compare and produce diff

For each selector present in both files, compare all properties. Report mismatches.

**Match selectors by:**
1. Exact selector match (e.g., `h1.title` = `h1.title`)
2. Text content match as fallback (e.g., both have `text: "Same Heading"`)
3. Tag + position match as last resort (e.g., 3rd `<p>` in section)

**Mismatch severity:**

| Property | Threshold | Severity |
|----------|-----------|----------|
| `fontSize` | ≠ exact | 🔴 HIGH — visually obvious |
| `fontWeight` | ≠ exact | 🔴 HIGH |
| `fontFamily` | different family name | 🔴 HIGH |
| `color` | ≠ exact | 🟡 MEDIUM |
| `width/height` | > 20px diff | 🟡 MEDIUM |
| `padding/margin` | > 10px diff | 🟡 MEDIUM |
| `backgroundColor` | ≠ exact | 🟡 MEDIUM |
| `letterSpacing` | ≠ exact | 🟢 LOW |
| `lineHeight` | > 4px diff | 🟢 LOW |
| `borderRadius` | ≠ exact | 🟢 LOW |
| `src` (IMG) | different filename | 🔴 HIGH — wrong image |
| `svgContent` | ref has content, impl empty | 🔴 HIGH — missing SVG |

**Output format:**

```json
{
  "summary": { "total": 45, "matched": 38, "mismatched": 7, "refOnly": 3, "implOnly": 2 },
  "mismatches": [
    {
      "selector": "h2.section-title",
      "text": "Section heading",
      "property": "fontSize",
      "ref": "14.4px",
      "impl": "16px",
      "severity": "HIGH"
    },
    {
      "selector": "img.hero-bg",
      "property": "src",
      "ref": "...hero-video-poster.jpg",
      "impl": "...placeholder.png",
      "severity": "HIGH"
    }
  ],
  "refOnly": [
    { "selector": "svg.logo-icon", "note": "Present in ref, missing in impl" }
  ]
}
```

**Save to** `tmp/ref/<component>/style-audit-diff.json`

---

## Step A3.5: Font-family fallback detection

**(Tailwind v4 only)** A silent failure: `font-[var(--custom-font)]` with comma-separated values does not generate a CSS class — the element inherits the body font instead.

**Detection:** For each element where `fontFamily` in ref ≠ impl, check if:
1. The impl element's computed `fontFamily` matches the `body` font — custom font class not applied
2. The Tailwind class string contains `font-[var(` — this is the broken pattern

**Fix:** Register fonts in `@theme` block and use `font-<name>` utility classes instead. See `component-generation.md`.

> In Tailwind v3, custom fonts are registered via `theme.extend.fontFamily` in `tailwind.config` and do not exhibit this issue.

---

## Step A3.6: Cross-section typography consistency

> **Skip for single-section and single-element extractions.** This check is only meaningful when 2+ sections are being implemented.

Group all extracted elements by visual role (section titles, body headings, buttons, body text) and check that elements with the same role have identical typography values across sections.

**Common failure mode:** During multi-section generation, font sizes drift between sections — one section gets a rounded value while another gets the correct extracted value for the same role. This happens when values are approximated instead of copied exactly.

```
| Role          | Expected      | Sections matching      | Sections deviating          |
|---------------|---------------|------------------------|-----------------------------|
| Section title | Xpx/weight    | section-a ✅, section-b ✅ | section-c ❌ (wrong value) |
| Button label  | Ypx/weight    | section-a ✅              | section-d ❌ (wrong value) |
```

**If ANY role has inconsistent values across sections → fix all deviating sections to match the ref value.**

---

## Step A4: Apply fixes

For each HIGH severity mismatch:
1. Identify the component file that renders this element
2. Fix the specific property (fontSize, fontWeight, src, etc.)
3. Re-run Step A2 + A3 to verify

**Do NOT re-run the full extraction pipeline** — this is a targeted fix loop.

---

## Integration with verification pipeline

Style audit runs **in parallel** with visual verification (Step 8):

```
Step 7 (Generation)
  ↓
  ├── Step 8: Visual Verification (screenshots + video comparison)
  └── Style Audit (computed style comparison)
  ↓
Both must pass before declaring done.
```

If style audit finds mismatches that visual verification missed (e.g., `font-size: 15px vs 16px`), fix them and re-verify.

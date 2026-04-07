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

## Step A4: Apply fixes

For each HIGH severity mismatch:
1. Identify the component file that renders this element
2. Fix the specific property (fontSize, fontWeight, src, etc.)
3. Re-run Step A2 + A3 to verify

**Do NOT re-run the full extraction pipeline** — this is a targeted fix loop.

---

## Integration with verification pipeline

Style audit has two layers that work together:

```
Step 7 (Generation)
  ↓
  ├── A1-A4: Detailed property-level audit (per-selector comparison)
  │   → Produces style-audit-diff.json (exact mismatches with severity)
  │
  └── 10-Point Score: Category-level summary (derived from A1-A4 results)
      → Produces score-history.json (iteration tracking)
  ↓
  ├── Step 8: Visual Verification (screenshots + video comparison)
  └── Pixel-perfect-diff (completion gate)
  ↓
All must pass before declaring done.
```

**Flow:** A1-A4 runs first to produce detailed mismatches. The 10-point score is computed FROM those results — it's a summary, not a separate audit. Score guides fix priority; A1-A4 provides the specific values to fix.

---

## 10-Point Design Fidelity Score

Diagnostic scoring system for fix iteration guidance. This does NOT replace pixel-perfect-diff — it tells you **what to fix first**. pixel-perfect-diff tells you **when you're done**.

### Checklist (1 point each)

| # | Category | What to check | Detection |
|---|----------|--------------|-----------|
| 1 | **Typography scale** | type bundles match: fontSize, fontWeight, fontFamily, lineHeight, letterSpacing | Compare impl vs ref `design-bundles.json` type entries |
| 2 | **Color tokens** | tone bundles match: text color, bg color, border color | Compare impl vs ref tone entries |
| 3 | **Spacing system** | shape bundles match: padding, margin, gap, borderRadius | Compare impl vs ref shape entries |
| 4 | **Surface depth** | surface bundles match: boxShadow, border, backgroundColor layers | Compare impl vs ref surface entries |
| 5 | **Layout structure** | display, flexDirection, alignItems, justifyContent, grid correct | getComputedStyle layout props comparison |
| 6 | **Responsive behavior** | layout transitions match at all detected breakpoints | Viewport resize + spot-check at breakpoint boundaries |
| 7 | **Interaction states** | hover/active/focus deltas match interaction-states.json | Hover eval + getComputedStyle before/after |
| 8 | **Motion timing** | motion bundles match: duration + easing correct | Compare impl vs ref motion entries |
| 9 | **Asset fidelity** | SVG paths verbatim, images correct src, favicon present | DOM check: SVG `d` attr exact match, img src |
| 10 | **Visual completeness** | No missing elements, z-index order correct, no overflow bugs | Element count ref vs impl, z-index comparison |

### Scoring eval script

Run on the implementation page after each fix iteration:

```bash
agent-browser --session <impl-session> eval "(() => {
  const score = { total: 0, breakdown: {}, failures: [] };

  // 1. Typography — check font-size consistency across headings
  const headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
  let typoPass = true;
  headings.forEach(h => {
    const s = getComputedStyle(h);
    // Compare against expected from design-bundles — agent fills these from ref data
    // If any heading fontSize/weight deviates from ref bundle → fail
  });
  score.breakdown.typography = typoPass ? 1 : 0;
  score.total += score.breakdown.typography;

  // 2-10: Similar pattern — compare computed style categories against ref bundles
  // Each category: pass = 1, fail = 0, with failure details

  return JSON.stringify(score, null, 2);
})()"
```

> **Note:** The eval script above is a template — not a standalone audit. In practice, compute the 10-point score by **categorizing mismatches from `style-audit-diff.json`** (A1-A4 output). Each HIGH/MEDIUM mismatch maps to a scoring category (e.g., fontSize mismatch → typography, backgroundColor mismatch → colors). A category scores 1 if it has zero mismatches, 0 if any. This avoids re-running getComputedStyle — A1-A4 already did that.

### Scoring loop protocol

1. **Run scoring at the START of each Step 8 fix iteration** (before pixel-perfect-diff)
2. **Save score** to `tmp/ref/<component>/score-history.json` (append):
   ```json
   [
     { "iteration": 1, "score": 6, "breakdown": { "typography": 1, "colors": 0 }, "failures": ["..."] },
     { "iteration": 2, "score": 8, "breakdown": { "typography": 1, "colors": 1 }, "failures": ["..."] }
   ]
   ```
3. **Score regression → rollback:**
   If `score[n] < score[n-1]`, the last fix made things worse.
   ```bash
   git checkout -- src/components/<Component>.tsx
   ```
   Then retry with a different approach.
4. **Fix priority:** Address the lowest-scoring category first. Within a category, fix the largest delta first.
5. **Escalation:** If after 3 iterations the score has not reached 9+, escalate to user with:
   - Current score + breakdown
   - Score history (trend)
   - Top 3 remaining failures with specific values (e.g., "font-size: 24px should be 32px on .hero h1")
6. **Completion:** Score ≥ 9 is a prerequisite for running the final pixel-perfect-diff gate. Do not run pixel-perfect-diff until scoring passes 9+.

### Relationship to pixel-perfect-diff

```
  Fix iteration loop:
  ┌─────────────────────────────────────────────┐
  │  1. Run 10-point score                      │ ← "what to fix"
  │  2. Score < previous? Rollback              │
  │  3. Score ≥ 9?                              │
  │     NO → fix lowest category                │──→ back to 1
  │     YES ↓                                   │
  │  4. Run pixel-perfect-diff                  │ ← "are we done?"
  │     FAIL → fix specific element             │──→ back to 1
  │     PASS → DONE                             │
  └─────────────────────────────────────────────┘
```

# Site Type Detection — Run at Step 1 (before extraction)

Detect the site's tech stack to choose the right extraction strategy.

## Detection script

```bash
agent-browser eval "(() => {
  const signals = {};

  // CSS strategy
  const stylesheets = [...document.querySelectorAll('link[rel=stylesheet]')].map(l => l.href);
  signals.hasTailwind = document.querySelector('[class*=tw-], [class*=sm\\:], [class*=md\\:]') !== null;
  signals.hasCSSModules = document.querySelector('[class*=_module_], [class*=__]') !== null;
  signals.hasReadableClasses = document.querySelectorAll('[class]').length > 0 &&
    [...document.querySelectorAll('[class]')].slice(0, 20).every(el =>
      !el.className.match(/^[a-z]{5,}$/)); // Not hashed single-word classes

  // Platform
  signals.isShopify = !!document.querySelector('meta[name=shopify-checkout-api-token], script[src*=shopify]');
  signals.isWordPress = !!document.querySelector('meta[name=generator][content*=WordPress], link[href*=wp-content]');
  signals.isNextJS = !!document.querySelector('script[src*=_next], #__next');
  signals.isGatsby = !!document.querySelector('#___gatsby');

  // Animation library
  signals.hasGSAP = typeof gsap !== 'undefined';
  signals.hasFramerMotion = !!document.querySelector('[style*=will-change]');
  signals.hasLenis = !!document.querySelector('[data-lenis], .lenis');

  // CSS file type
  signals.siteCSS = stylesheets.filter(s => !s.includes('cdn.shopify') && !s.includes('googleapis')).length;
  signals.hasTypekit = stylesheets.some(s => s.includes('typekit'));

  return JSON.stringify(signals);
})()"
```

## Strategy selection

| Signal | CSS Strategy | Class Strategy |
|--------|-------------|----------------|
| `hasReadableClasses + siteCSS > 0` | **CSS-First**: Download CSS, use original class names | Use original classes in JSX |
| `hasTailwind` | **Extract-Values**: Read computed styles | Rewrite with Tailwind utilities |
| `hasCSSModules` | **Extract-Values**: Read computed styles | Generate new class names |
| `isShopify` | **CSS-First** (Shopify uses readable Liquid class names) | Use original classes |
| `isNextJS + hasTailwind` | **Extract-Values** | Tailwind utilities |

**Default:** If `hasReadableClasses` is true AND `siteCSS > 2`, use CSS-First. Otherwise use Extract-Values.

## Implementation Approach Gate (MANDATORY — decide before writing ANY code)

Beyond CSS strategy, choose the **implementation approach** based on site complexity. This decision has 10x impact on token efficiency.

### Detection: run this AFTER the signals above

```bash
agent-browser eval "(() => {
  const signals = {};
  // Count CSS Module hashed classes (e.g., _card_j4aeg_2)
  const allEls = document.querySelectorAll('[class]');
  let hashedCount = 0;
  let totalCount = 0;
  allEls.forEach(el => {
    const cn = typeof el.className === 'string' ? el.className : '';
    if (cn.match(/_[a-z]+_[a-z0-9]+_\d+/)) hashedCount++;
    totalCount++;
  });
  signals.cssModuleRatio = totalCount > 0 ? (hashedCount / totalCount).toFixed(2) : 0;

  // Count JS-driven animations
  signals.hasGSAP = typeof gsap !== 'undefined' || !!document.querySelector('script[src*=gsap]');
  signals.hasLottie = !!document.querySelector('script[src*=lottie]') ||
    performance.getEntriesByType('resource').some(e => e.name.includes('lottie'));
  signals.hasCanvas = document.querySelectorAll('canvas').length;
  signals.hasMatterJS = typeof Matter !== 'undefined';

  // Count inline styles set by JS (GSAP artifacts)
  let inlineStyleCount = 0;
  allEls.forEach(el => {
    if (el.getAttribute('style')?.includes('translate') ||
        el.getAttribute('style')?.includes('rotate') ||
        el.getAttribute('style')?.includes('opacity')) inlineStyleCount++;
  });
  signals.jsInlineStyles = inlineStyleCount;

  // Total HTML size
  signals.totalHTMLSize = document.documentElement.outerHTML.length;

  return JSON.stringify(signals);
})()"
```

### Approach decision matrix

| Condition | Approach | Why |
|-----------|----------|-----|
| `cssModuleRatio > 0.3` OR `jsInlineStyles > 20` | **Raw HTML Injection** | CSS Modules hashes must be preserved; rewriting loses all styling |
| `hasGSAP + hasLottie + hasCanvas > 1` | **Raw HTML Injection** | Too many animation libraries to re-implement from scratch |
| `totalHTMLSize > 200KB` | **Raw HTML Injection** | Converting 200KB+ HTML to JSX is token-expensive and error-prone |
| `cssModuleRatio < 0.1` AND simple Tailwind | **React Component** | Clean class names, straightforward conversion |
| Static site, no JS animations | **React Component** | Simplest approach works |

### Raw HTML Injection approach

**When to use:** Complex sites with CSS Modules, GSAP, Lottie, Canvas, or 200KB+ HTML.

1. Extract outerHTML of each major section from the original site
2. Download ALL CSS files and serve from `/public/css/`
3. Download ALL fonts, images, Lottie JSON to `/public/assets/`
4. Render via `dangerouslySetInnerHTML` — **NO wrapper divs** between parent and child elements
5. Port animations to @beyond/react (or keep original library if allowed)
6. Clean GSAP inline styles carefully: **preserve layout values** (height, width in svh/vh), **remove animation values** (transform, opacity, visibility)

**Critical: wrapper div problem.**
```tsx
// ❌ WRONG — extra <div> breaks CSS Module selectors
<section className="program">
  <div dangerouslySetInnerHTML={{ __html: servicesHtml }} />
  <div dangerouslySetInnerHTML={{ __html: aboutHtml }} />
</section>

// ✅ CORRECT — concatenate HTML strings, single injection
const programHtml = servicesHtml + aboutHtml + beigeHtml;
<div dangerouslySetInnerHTML={{ __html:
  `<section class="program">${programHtml}</section>`
}} />
```

**Critical: GSAP inline style cleanup.**
JS-driven sites set inline styles for two purposes:
- **Layout values** (`height: 500svh`, `width: 350svh`) — MUST KEEP, re-set via ClientShell JS
- **Animation values** (`transform: rotateY(-180deg)`, `opacity: 0`, `visibility: hidden`) — REMOVE

Use `extract-dynamic-styles.sh` to classify:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(find ~/.claude/skills -name 'validate-gate.sh' -exec dirname {} \; 2>/dev/null | head -1 | xargs dirname)}"
bash "$PLUGIN_ROOT/scripts/extract-dynamic-styles.sh" <session> tmp/ref/<component>
```

### React Component approach

**When to use:** Simple Tailwind sites, static pages, readable class names.

1. Extract DOM structure + computed styles
2. Generate React components with Tailwind classes
3. Copy images/fonts to public
4. Standard approach from `component-generation.md`

---

## CSS-First (readable classes)

1. Download ALL site-specific CSS files
2. Extract CSS variables to `variables.txt`
3. Import CSS into project
4. Use original class names in JSX
5. Override only for React-specific needs (sticky, scroll-driven transforms)

## Extract-Values (obfuscated/Tailwind)

1. Extract computed styles via `getComputedStyle` for every element
2. Convert to Tailwind utilities or inline styles
3. No original CSS import (hashed classes are meaningless)
4. More manual work, more iteration needed

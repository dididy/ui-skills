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

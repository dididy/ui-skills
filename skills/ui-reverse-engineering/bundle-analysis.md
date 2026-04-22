# Bundle Analysis — Step 6

> **This step is MANDATORY for ALL sites.** Most modern sites use JS to drive animations (GSAP, Framer Motion), smooth scroll (Lenis), intro sequences, and state transitions invisible to `getComputedStyle`.
>
> **After this step:** produce `transition-spec.json` — see `transition-spec-rules.md`.
> **Reference patterns:** see `patterns.md` for Canvas/Disc/Lottie/StateMachine/Timer detection.

## Download ALL loaded chunks (MANDATORY)

Modern frameworks code-split aggressively. Page-specific logic lives in lazy-loaded chunks, not the main bundle.

```bash
agent-browser eval "
(() => {
  const entries = performance.getEntriesByType('resource');
  const scripts = entries
    .filter(e => e.initiatorType === 'script' && e.name.endsWith('.js'))
    .map(e => e.name)
    .filter(n => !n.includes('cloudflare') && !n.includes('analytics') && !n.includes('gtag'));
  return JSON.stringify(scripts);
})()
"

mkdir -p tmp/ref/<component>/bundles
# Download each chunk (HTTPS only, read-only analysis, never execute)
```

## Custom scroll engine detection (MANDATORY)

**Step 1: Behavioral detection**

```bash
agent-browser eval "
(() => {
  const html = document.documentElement;
  const body = document.body;
  const htmlS = getComputedStyle(html);
  const bodyS = getComputedStyle(body);
  const nativeScrollDisabled = htmlS.overflow === 'hidden' || bodyS.overflow === 'hidden';
  const wrappers = [...document.querySelectorAll('*')].filter(el => {
    const s = getComputedStyle(el);
    return (s.position === 'fixed' || s.position === 'absolute') &&
           el.scrollHeight > window.innerHeight * 2 && el.offsetWidth >= window.innerWidth * 0.9;
  });
  const transformedWrappers = wrappers.filter(el => {
    const t = el.style.transform || getComputedStyle(el).transform;
    return t && t !== 'none';
  });
  return JSON.stringify({ nativeScrollDisabled, wrapperCount: wrappers.length, hasTransformScroll: transformedWrappers.length > 0 });
})()
"
```

**Step 2: Known library detection (after download)**

```bash
grep -liE 'new Lenis|smoothWheel|locomotive-scroll|ScrollSmoother|data-scroll' \
  tmp/ref/<component>/bundles/*.js
```

**Step 3: Scroll method verification** — when custom scroll detected, verify `window.scrollTo()` actually works. If not, use `mouse wheel` for all subsequent scroll operations. Save to `scroll-engine.json`.

## Auto-timer detection

```bash
# Take 2 screenshots 4s apart — if different, auto-timer exists
agent-browser screenshot tmp/ref/<component>/timer-t0.png
agent-browser wait 4000
agent-browser screenshot tmp/ref/<component>/timer-t1.png

# Find interval timing in bundles
grep -oE 'setInterval\([^,]+,\s*[0-9]+' tmp/ref/<component>/bundles/*.js | head -10
```

## Animation library detection

> **Detailed extraction (Framer Motion decode, GSAP timeline parsing, scroll library params) → `js-animation-extraction.md`.** Run the transition extraction pipeline (Step T1→T2b) when any animation library is detected below.

### Quick detection (confirm presence)
```bash
# Framer Motion / Motion One — any hit → run transition extraction pipeline
grep -lE 'stiffness|damping|mass|bounce|useTransform|useScroll|scrollYProgress' tmp/ref/<component>/bundles/*.js

# GSAP — any hit → run transition extraction pipeline
grep -lE 'gsap\.(to|from|fromTo|timeline)|ScrollTrigger' tmp/ref/<component>/bundles/*.js

# Scroll library — any hit → run transition extraction pipeline
grep -lE 'new Lenis|smoothWheel|locomotive-scroll|ScrollSmoother' tmp/ref/<component>/bundles/*.js
```

Record detected libraries in `bundle-map.json`. Full parameter extraction happens in `js-animation-extraction.md`.

## Bundle values → DOM element mapping (MANDATORY)

Extracting values without mapping to DOM elements is useless. Find selector strings near animation calls:

```bash
grep -oE '"[.#][a-zA-Z][^"]{2,40}"[^;]{0,200}(duration|ease|stagger|yPercent|opacity)' \
  tmp/ref/<component>/bundles/*.js | head -30
```

Build `element-animation-map.json` mapping each selector to its animation parameters.

## Cross-component DOM manipulation detection

```bash
grep -oE 'querySelector\([^)]+\)\.(style\.\w+|classList\.(add|remove|toggle))' \
  tmp/ref/<component>/bundles/*.js | head -20
```

Record as `type: "cross-component"` in `interactions-detected.json`.

## Preloader/Splash Detection

**Detection (here, Step 5c):** Two signals — either confirms splash exists.

```bash
# Signal 1: Bundle grep
grep -l "preloader\|Preloader\|pre_loader\|splash\|introAnimation" tmp/ref/<c>/bundles/*.js

# Signal 2: DOM class on html/body
agent-browser eval "(() => {
  const html = document.documentElement;
  const body = document.body;
  const preloaderEl = document.querySelector('[class*=preloader], [class*=loader], [data-preloader]');
  return JSON.stringify({
    htmlClass: html.className,
    bodyClass: body.className,
    preloaderEl: preloaderEl ? preloaderEl.className : null,
    hasPreloading: html.classList.contains('rk-preloading') || html.classList.contains('is-loading') || body.classList.contains('loading'),
  });
})()"
```

If either signal hits → mark `"hasPreloader": true` in `interactions-detected.json`. Then:
- Extract timeline from bundle. Full procedure → `splash-extraction.md`.
- Step 5e capture verification will automatically capture the splash (record from blank → navigate).
- Step 6 Phase A idle capture provides additional Tier 1 AE confirmation.

## Output

After completing all analysis, produce two documents per `transition-spec-rules.md`:
1. `bundle-map.json` — which chunk owns which feature
2. `transition-spec.json` — complete transition specification (DRAFT, to be verified)

Then proceed to **Step 5e: Capture Verification** (in `transition-spec-rules.md`).

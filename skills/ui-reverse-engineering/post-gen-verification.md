# Post-Generation Verification Loops

Run BEFORE visual verification. Catches layout and behavior errors that screenshots miss.

## Loop 0: Original A/B comparison at 60fps (MANDATORY for animated components)

**The ONLY reliable way to verify animations.** Checking that values change in your impl proves nothing — you must compare AGAINST THE ORIGINAL at the same resolution. Without this, you WILL ship wrong easing, wrong axis, wrong direction, wrong timing.

**Failure mode this prevents:** You extract `clipPath: inset(0% 0% X% 0%)` (bottom clips upward), but implement `clipPath: inset(0% X% 0% 0%)` (right clips leftward). Both "animate clipPath from 0% to 5%". Both "work". Self-verification says "clipPath changes — correct!" A/B comparison instantly shows the mismatch.

### Step 1: Capture original at 60fps
Use the `agent-browser` 60fps rAF capture from `animation-detection.md` Tier 2, pointing to the original URL. Save to `tmp/ref/<component>/original-60fps.json`.

### Step 2: Capture implementation at 60fps
Same rAF capture pointing to `localhost:<port>`. Save to `tmp/ref/<component>/impl-60fps.json`.

### Step 3: Diff key properties at matching timestamps (±50ms tolerance)

**Every animated property must pass ALL 5 checks:**

```
□ DIRECTION: Which value in clipPath/transform is changing?
  Original: inset(0% 0% X% 0%) → 3rd value (bottom)
  Impl:     inset(0% X% 0% 0%) → 2nd value (right)  ← WRONG AXIS

□ RANGE: Start and end values?
  Original: opacity 1 → 0.02 (never fully 0)
  Impl:     opacity 1 → 0      ← check if intentional

□ TIMING: Transition start + end?
  Original: starts t=2111ms, reaches 3.67% at t=2611ms
  Impl:     starts t=1260ms, reaches 0% at t=1693ms  ← 850ms too early

□ EASING: Interpolation curve shape?
  Original: values at 25%/50%/75% progress → power5 (fast start, slow end)
  Impl:     values show linear or wrong easing

□ COUPLING: Which properties animate together?
  Original: clipPath + text reveal start at same time
  Impl:     clipPath starts 800ms before text  ← desynced
```

**Gate:** ANY check fails → fix before proceeding. Do NOT rationalize ("close enough", "similar feel"). Original values are the spec — match them or document the deviation.

**Anti-patterns this catches:**
- Wrong clipPath axis (right vs bottom vs top)
- Inventing animations that don't exist (e.g., "logo shrinks and moves up" when logo is static)
- Wrong easing (200ms polling looked linear)
- Desynced phases (splash/text/image should be coupled but aren't)
- Attributing GSAP's `transform: matrix(...)` init as an animation when it's just setup

## Loop 0.5: State Coupling Verification (MANDATORY for carousels/tabs)

Verify that ALL coupled elements update when shared state changes.

### Step 1: Load `state-coupling.json`
If it doesn't exist, create it now by clicking through each state on the ref and noting what changes.

### Step 2: For each state transition, verify ALL coupled elements update

```bash
# On impl: click carousel arrow, then immediately check all coupled elements
agent-browser eval "
(() => {
  // Click arrow
  document.querySelectorAll('[class*=\"carousel-control\"] button')[1]?.click();

  // Wait 1s for animations
  return new Promise(resolve => setTimeout(() => {
    // Check each coupled element
    const results = {
      sectionBg: document.querySelector('section[class*=\"carousel\"]')?.style.backgroundColor,
      cardText: document.querySelector('.card [style*=\"opacity: 1\"] h3')?.textContent,
      serviceBg: document.querySelector('[class*=\"programs-\"][class*=\"-bg\"]')?.style.backgroundColor,
      illustRotation: /* rotation wrapper transform */,
    };
    resolve(results);
  }, 1000));
})()
"
```

### Step 3: Compare against ref at same state
If ANY coupled element didn't update → fix the `goTo()` function.

**Failure modes this prevents:**
- Carousel rotates but card background stays green (missing bg coupling)
- Card text updates but illustration doesn't rotate (missing disc rotation)
- Background color changes but service section bg stays stale (missing secondary color)
- Lottie SVGs replaced with wrong asset (`kid_flower_pants` → `kid_flower_nopants`)

### Step 4: Verify auto-timer doesn't conflict with splash
```bash
# Record first 8 seconds. If carousel rotates during splash overlay → bug.
agent-browser record start tmp/ref/<c>/splash-timer-check.webm
sleep 8
agent-browser record stop
# Extract frames and check: is splash visible in any frame where illustration has rotated?
```

---

## Loop 1: Section height verification

For every section with fixed height (e.g., `style={{ height: N }}`):

```bash
agent-browser eval "(() => {
  const sections = document.querySelectorAll('section[style*=height], [style*=height]');
  const results = [];
  for (const s of sections) {
    const sr = s.getBoundingClientRect();
    const imgs = [...s.querySelectorAll('img')];
    const last = imgs.length ? imgs[imgs.length-1] : null;
    const lr = last?.getBoundingClientRect();
    if (lr) results.push({
      id: s.id || s.className.slice(0,40),
      sectionH: Math.round(sr.height),
      lastContentBottom: Math.round(lr.bottom - sr.top),
      waste: Math.round(sr.height - (lr.bottom - sr.top)),
    });
  }
  return JSON.stringify(results, null, 2);
})()"
```

**Gate:** every section `waste < 100`. If `waste > 100`, reduce section height to `lastContentBottom + 65`.

## Loop 2: Sticky lock point verification

For every sticky element in `sticky-elements.json`:

```bash
agent-browser eval "(() => {
  const results = [];
  for (let y = 0; y <= document.documentElement.scrollHeight; y += 200) {
    window.scrollTo(0, y);
    const title = document.querySelector('<sticky-selector>');
    if (!title) continue;
    const tr = title.getBoundingClientRect();
    const tc = tr.top + tr.height / 2;
    const lastImg = document.querySelector('<last-content-selector>');
    if (!lastImg) continue;
    const lr = lastImg.getBoundingClientRect();
    const lc = lr.top + lr.height / 2;
    const sticky = tr.top > 50 && tr.top < 500;
    if (!sticky && results.length > 0 && results[results.length-1].sticky) {
      results.push({ y, diff: Math.round(lc - tc), sticky, note: 'UNSTICK POINT' });
    } else if (sticky) {
      results.push({ y, diff: Math.round(lc - tc), sticky });
    }
  }
  return JSON.stringify(results.slice(-5), null, 2);
})()"
```

**Gate:** at unstick, `|diff| < 15px`. Adjust wrapper height:
- `diff > 0` → wrapper too short, increase by `diff`
- `diff < 0` → wrapper too long, decrease by `|diff|`

Re-run until `|diff| < 15`.

## Loop 3: Body state transition verification

If `body-state.json` has body class rules:

1. Scroll to position where class should be active
2. Check `document.body.className` contains expected class
3. Check CSS cascade produces expected values (nav color, logo filter, bg-color)
4. Scroll back → verify class removed + values reverted

### Body-state implementation pattern

When `body-state.json` has rules, implement this exact pattern:

**globals.css:**
```css
body { transition: background-color 0.8s; }
body.<active-class> { background-color: <extracted-value>; }
body.<active-class> #main-nav { background-color: <extracted-value>; }
body.<active-class> .nav-logo { filter: brightness(0) invert(1); }
body.<active-class> .nav-link { color: <extracted-value>; }
```

**Scroll handler (component owning the transition):**
```tsx
useEffect(() => {
  const handleScroll = () => {
    const isActive = /* scroll condition from extracted data */;
    document.body.classList.toggle('<active-class>', isActive);
  };
  window.addEventListener('scroll', handleScroll, { passive: true });
  return () => {
    window.removeEventListener('scroll', handleScroll);
    document.body.classList.remove('<active-class>');
  };
}, []);
```

**Why CSS cascade, not React state:** a single body-class toggle coordinated by CSS rules is simpler, avoids prop drilling, and matches the original site's architecture. Do NOT replicate with per-component `isDark` state + conditional classNames on every element.

## Loop 4: Hover transition verification (MANDATORY if hover-deltas.json exists)

Hover effects are the most commonly "approximately close but wrong" part of clones. The fix is simple: hover on both original and implementation, measure the same properties, compare.

### Step 1: For each element in hover-deltas.json

```bash
# On ORIGINAL site:
agent-browser open <original-url>
# scroll to element
agent-browser hover "<selector>"
# wait for transition
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  const s = getComputedStyle(el);
  // Capture all visual properties
  return JSON.stringify({
    transform: s.transform,
    opacity: s.opacity,
    scale: s.scale,
    backgroundColor: s.backgroundColor,
    color: s.color,
    boxShadow: s.boxShadow,
    borderColor: s.borderColor,
    filter: s.filter,
    clipPath: s.clipPath,
  });
})()"
```

### Step 2: Same measurement on implementation

```bash
agent-browser open <impl-url>
agent-browser hover "<selector>"
agent-browser eval "/* same property extraction */"
```

### Step 3: Compare

For each property in the delta:
```
□ Property changes in SAME direction (scale up vs scale down)
□ End value matches within 2% tolerance
□ Duration is within ±100ms
□ Easing curve SHAPE matches (bounce vs linear vs ease-out)
□ Child elements that should ALSO change are changing
```

**Common hover mismatches:**

| Symptom | Root cause |
|---|---|
| Hover works but feels "flat" | Missing easing — using `ease` instead of `cubic-bezier(0.625, 0.05, 0, 1)` |
| Hover effect instant (no transition) | CSS `transition` property missing or overridden by Tailwind reset |
| Hover shows wrong element | `display: none → block` controlled by JS, not CSS `:hover` |
| Image zooms differently | Original uses GSAP `scale: 1.05` with custom ease, impl uses CSS `hover:scale-105` with default ease |
| Text split-hover broken | Original uses GSAP SplitText per-character stagger on hover, impl does whole-block transition |
| Hover doesn't revert smoothly | `mouseleave` transition missing — GSAP has separate `leave` tween |

### Step 4: Fix and re-verify

After fixing, re-hover on both and confirm the delta matches. Maximum 3 iterations.

## Animation library → wiring pattern mapping

When Step 6 bundle analysis detects an animation library, use these patterns:

### Scroll-driven parallax

| Library | Pattern |
|---|---|
| GSAP + ScrollTrigger | `gsap.to(el, { y: offset, scrollTrigger: { trigger, scrub: true } })` |
| Framer Motion | `useScroll({ target }) + useTransform(scrollYProgress, [0,1], [startY, endY])` → `style={{ y: transformValue }}` |
| Lenis / custom lerp | Subscribe to scroll position callback → compute offset in rAF → set `el.style.transform` directly |
| No library (CSS-only) | `IntersectionObserver` + CSS custom property `--scroll-progress` |

### Scroll-trigger reveal

| Library | Pattern |
|---|---|
| GSAP | `ScrollTrigger.create({ trigger, onEnter: () => gsap.to(el, { opacity:1, y:0 }) })` |
| Framer Motion | `useInView(ref) + animate={{ opacity: inView ? 1 : 0, y: inView ? 0 : 60 }}` |
| Lenis / custom lerp | Subscribe to scroll MotionValue → `getBoundingClientRect()` in rAF → style when in viewport |
| No library | `IntersectionObserver` + CSS transition class toggle |

### Hover / click state

| Library | Pattern |
|---|---|
| Framer Motion | `whileHover={{ scale: 1.05 }}` or `variants` + `AnimatePresence` |
| GSAP | `el.addEventListener('mouseenter', () => gsap.to(el, { scale: 1.05 }))` |
| CSS-only | `transition` + `:hover` or `group-hover:` Tailwind |

### SVG / DOM child staggered animation

When bundle shows `.fromTo(".selector > *", ...)` with `stagger`:

```tsx
// SVG children animate individually — NEVER translate parent
useEffect(() => {
  const svg = svgRef.current
  if (!svg) return
  const children = Array.from(svg.children) as SVGElement[]
  const offset = svg.getBoundingClientRect().height * 2

  children.forEach(child => {
    child.style.transform = `translateY(${offset}px)`
    child.style.willChange = 'transform'
  })

  const timer = setTimeout(() => {
    children.forEach((child, i) => {
      child.style.transition = `transform 1s cubic-bezier(...) ${i * stagger}s`
      child.style.transform = 'translateY(0)'
    })
  }, delay)

  return () => clearTimeout(timer)
}, [])
```

**When:** bundle contains `> *`, `.children`, or `stagger` on children. Common for logo assembly, icon reveals, grid card entrances, text character animations. **Never** translate the parent when the bundle animates children individually.

### Custom scroll engine — architectural insight

If the site uses `overflow: hidden` + `translate3d` wrapper:

- Standard `IntersectionObserver` will NOT fire — elements don't actually scroll in the DOM
- Must subscribe to the scroll engine's value stream (MotionValue, event emitter, callback)
- `getBoundingClientRect()` returns correct values (browser accounts for transforms)
- Pattern: `scrollValue.on('change', () => requestAnimationFrame(() => { const rect = el.getBoundingClientRect(); /* visibility check */ }))`

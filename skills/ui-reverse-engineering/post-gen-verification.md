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

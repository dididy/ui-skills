# Transition Implementation Guide

When implementing scroll/page-load/interaction transitions extracted from JS bundles.

## Core principle

**Transitions are part of component generation, not a separate step.** When generating a component, read `transition-spec.json` + the source bundle file, and implement the transition IN the component — not as a later pass.

If you generate a component without its transitions, it is incomplete.

## Bundle → Code translation

### Scroll-driven animations (GSAP ScrollTrigger / custom)

Original JS libraries use scroll position to drive CSS transforms. Without GSAP, replicate with:

1. **Scroll listener** (`{ passive: true }`) in `useEffect`
2. **Progress calculation** from section's scroll position
3. **Direct DOM manipulation** via refs (not React state — for performance)

#### Progress formula

```
ScrollTrigger start: 'top 90%'  →  section top at 90% of viewport
ScrollTrigger end: 'bottom top' →  section bottom exits viewport top

const rect = section.getBoundingClientRect()
const vh = window.innerHeight
const scrollStart = vh * 0.9
const progress = clamp((scrollStart - rect.top) / (scrollStart + section.offsetHeight), 0, 1)
```

Adjust `scrollStart` based on the original `start` value:
- `'top top'` → `scrollStart = 0`
- `'top 80%'` → `scrollStart = vh * 0.8`
- `'top center'` → `scrollStart = vh * 0.5`

#### Common patterns

| Bundle pattern | Implementation |
|---|---|
| `scrub: N` (scroll-driven) | Progress-based transform via ref, no CSS transition |
| `pin: true` | `position: sticky; top: 0` (override parent `overflow: hidden` if needed) |
| `from(el, { y: '100%' })` with scrub | `translateY((1 - progress) * 100%)` |
| `set(el, { y: '20vh' })` + `to(el, { y: '-20vh' })` | `translateY(20 - progress * 40)vh` |
| `to(el, { scale: 1.1 })` with scrub | `scale(1 + progress * 0.1)` |
| Background crossfade overlays | Multiple absolute divs, toggle `opacity: 0/1` by active index |

### Click-triggered content transitions (view swap / search results)

When clicking an element swaps the visible content (e.g., image grid → search results), the implementation depends on `transition-structure.json` from interaction detection.

**MANDATORY:** Read `transition-structure.json` before implementing. Never guess the pane architecture.

#### Pattern: New-on-top (most common for image grids)

The new pane sits above the old pane. New images load asynchronously with fadein, progressively covering the old pane. Old pane fades out underneath.

```
DOM order: old pane (first) → new pane (last, renders on top)
z-index:   old=1, new=2
background: new pane = transparent (old pane shows through image gaps)
```

Implementation:
1. On click: snapshot current images → `oldImages` state, render old pane with fadegray+fadeout CSS
2. Clear `currentImages` to `[]` → new pane is empty (transparent bg shows old pane)
3. Set new layout (column count, viewMode)
4. Fetch API → set `currentImages` to response
5. Each new `<img>` gets `se_image_fadein` class → loads with 0.15s fadein
6. As images load, they cover the old pane from top to bottom
7. Timer removes old pane after fadeout animation completes (e.g., 4.5s)

CSS:
```css
/* Old pane — below, fades out */
.old_pane {
  animation: fadegray 0.35s forwards, fadeout 4s 0.35s forwards;
  z-index: 1;
}

/* New pane — above, transparent so old shows through gaps */
.new_pane {
  z-index: 2;
  background: transparent;
}

/* Individual images fade in as they load */
.image_fadein {
  animation: fadein 0.15s forwards;
}
```

#### Pattern: Old-on-top (old content fades revealing new)

Old pane sits above with `background: #fff`. Fadegray runs on old pane, then fadeout reveals new pane underneath. **Requires `background: #fff`** on old pane — otherwise both panes' images blend through each other.

#### Pattern: Single pane (class toggle)

One pane element. `old_pane` class is added (triggering fadegray CSS), then removed when new images arrive (canceling animation, showing fresh content).

Simplest implementation but no progressive image loading effect.

#### Anti-patterns (all observed in real failures)

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Old pane on top WITHOUT `background: #fff` | New pane images bleed through during fadegray | Add `background: #fff` to old pane OR use new-on-top pattern |
| Old pane on top WITH fadeout + same images in both panes | Fadegray desaturates then color returns as old fades | Clear new pane images OR use new-on-top pattern |
| New pane with fadein CSS + old pane also has fadeout | Both layers animate simultaneously, double-ghost effect | Only ONE pane should have opacity animation |
| `setViewMode` before API response with two panes | Column count changes, same images in wrong layout visible | Keep viewMode until API responds, or clear images first |
| Timer removes old pane before images load | White flash | Extend timer OR use API response timing |

### Page-load animations

| Bundle pattern | Implementation |
|---|---|
| `opacity: 0 → 1` with duration | CSS transition + React state toggle in `useEffect` |
| Container expand (width/height change) | CSS transition on dimensions, triggered by state |
| Sequential reveals (A then B then C) | `setTimeout` chain matching original delays |

### Easing conversion

Convert animation library easings to CSS `cubic-bezier`:

| Library easing | CSS equivalent |
|---|---|
| `power1.out` | `cubic-bezier(0, 0, 0.58, 1)` |
| `power2.out` | `cubic-bezier(0.215, 0.61, 0.355, 1)` |
| `power2.inOut` | `cubic-bezier(0.645, 0.045, 0.355, 1)` |
| `power3.out` | `cubic-bezier(0.165, 0.84, 0.44, 1)` |
| `none` / `linear` | `linear` (or no CSS transition — direct progress mapping) |

Use `scripts/gsap-to-css.sh convert "<easing>"` for automated conversion.

## Bundle parameters are EXACT

If the bundle says `duration: 1.4`, use `1.4`. If it says `y: 12 * index`, use `12 * index`. Do not round or approximate. These values are tuned by the original designer.

## Pre-implementation sticky check (run BEFORE writing code)

Before implementing any `position: sticky` element, check the original CSS for conflicts:

```bash
# Check if the section has overflow:hidden or display:grid in original CSS
grep '<section-class>' tmp/ref/<component>/css/*.css | grep -E 'overflow|display.*grid|place-items'
```

If found, add inline overrides in the component:
- `overflow: hidden` → `style={{ overflow: 'visible' }}`
- `display: grid; place-items: center` → `style={{ display: 'block' }}`

These are needed because original sites use JS-based pinning (GSAP), not CSS sticky.

**Why this is a pre-check, not a debugging step:** `position: sticky` fails silently when ANY ancestor has `overflow: hidden/auto/scroll`. Original sites using GSAP `pin: true` don't need sticky (GSAP handles it via JS). Discovering this after implementation wastes an entire iteration cycle.

## Splash/intro animation timing

Page-load animations require careful timing because:
1. Video may load instantly (cached) or take seconds (first visit)
2. React hydration adds delay
3. CSS transitions need the initial state to be rendered before the target state is set

**Pattern for reliable splash timing:**

```tsx
useEffect(() => {
  // Phase 1: Show initial state (small box, opacity 0)
  const t1 = setTimeout(() => setPhase('fadeIn'), 50)

  // Phase 2: Wait for BOTH video load AND fadeIn completion
  const video = videoRef.current
  let videoReady = false
  const tryExpand = () => {
    if (!videoReady) return
    // Ensure fadeIn is visible for at least 1s before expanding
    setTimeout(() => setPhase('expand'), 1200)
  }
  const onLoaded = () => { videoReady = true; video?.play(); tryExpand() }

  if (video?.readyState >= 3) onLoaded()
  else video?.addEventListener('loadeddata', onLoaded)

  // Phase 3: Reveal UI after expand completes
  const t3 = setTimeout(() => setPhase('reveal'), 3000)

  return () => { clearTimeout(t1); clearTimeout(t3); video?.removeEventListener('loadeddata', onLoaded) }
}, [])
```

**Key: the initial state (small box) must be visible for at least 1 second before expansion starts.** If the video is cached, it loads instantly and the expand triggers too early — the user never sees the small box.

## Performance

- Use **refs** for continuous scroll-driven transforms (not `useState`)
- Use **`will-change: transform`** on animated elements
- Scroll listeners must use **`{ passive: true }`**
- Batch reads (getBoundingClientRect) before writes (style mutations)

## Click-toggle / Click-cycle transitions

### click-toggle (accordion, dropdown, single toggle)

```tsx
const [isOpen, setIsOpen] = useState(false);

<button
  aria-expanded={isOpen}
  onClick={() => setIsOpen(!isOpen)}
>
  {label}
</button>
<div
  style={{
    height: isOpen ? measuredHeight : 0,
    overflow: 'hidden',
    transition: `height ${duration}ms ${easing}`,
  }}
>
  {content}
</div>
```

**Get exact values from extraction:**
- `duration`: from `getComputedStyle(panel).transitionDuration`
- `easing`: from `getComputedStyle(panel).transitionTimingFunction`
- `measuredHeight`: from `getBoundingClientRect().height` in active state

### click-cycle (tabs)

```tsx
const [activeIndex, setActiveIndex] = useState(0);

<div role="tablist">
  {tabs.map((tab, i) => (
    <button
      key={i}
      role="tab"
      aria-selected={i === activeIndex}
      onClick={() => setActiveIndex(i)}
    >
      {tab.label}
    </button>
  ))}
</div>
<div role="tabpanel">
  {tabs[activeIndex].content}
</div>
```

**Extract per-tab content** from click-cycle capture states — each `state-N.png` corresponds to `tabs[N].content`.

---

## GSAP Premium Plugin Alternatives

When the original site uses GSAP paid/premium plugins, do NOT purchase them or skip the feature. These alternatives are listed in priority order: (1) project-specific animation library if available, (2) open-source npm packages, (3) manual CSS implementation.

### SplitText → `splitting` npm package (or project animation library)

GSAP's SplitText (paid Club plugin) splits text into chars/words/lines for stagger animations. Open-source alternative: [`splitting`](https://splitting.js.org/) npm package — splits text into chars/words/lines with CSS custom properties for index-based stagger. If the project has its own animation library with splitText support, prefer that.

```ts
// Using splitting (npm install splitting)
import Splitting from 'splitting'

const result = Splitting({ target: element, by: 'chars' })
const chars = result[0].chars

// Animate with WAAPI
chars.forEach((char, i) => {
  char.style.opacity = '0'
  char.style.transform = 'translateY(200%)'
  const anim = char.animate(
    [
      { opacity: 0, transform: 'translateY(200%) scaleY(0)' },
      { opacity: 1, transform: 'translateY(0) scaleY(1)' },
    ],
    { delay: i * 100, duration: 1000, fill: 'forwards', easing: 'cubic-bezier(0.16, 1, 0.3, 1)' }
  )
  anim.onfinish = () => { char.style.opacity = '1'; char.style.transform = 'none'; anim.cancel() }
})
```

**When to use:** Any site with `SplitText.create()` in the bundle.

### MorphSVG → Manual SVG path interpolation or rx/ry animation

GSAP's MorphSVG morphs between SVG path shapes. Without the plugin:

1. **For simple rect → circle morphs** (CTA buttons): Animate `rx`/`ry` attributes of the SVG `<rect>` from pill radius to circle radius using `gsap.to()`.
2. **For complex path morphs**: Use `flubber` (npm package) for path interpolation, or pre-compute intermediate paths and crossfade with opacity.

```ts
// Simple rect → circle morph (no MorphSVG needed)
gsap.to(rectElement, {
  attr: { rx: circleRadius, ry: circleRadius, width: circleSize, height: circleSize },
  duration: 0.9,
  ease: 'elastic.out(0.8, 0.8)',
})
```

### ScrollSmoother → Lenis (or project library)

GSAP's ScrollSmoother (paid) adds smooth scroll behavior. Alternatives:
- [`lenis`](https://github.com/darkroomengineering/lenis) npm package — widely used, lightweight, open-source
- Project-specific smooth scroll library if available

### Draggable → Native pointer events

GSAP's Draggable is actually free, but if not using GSAP at all:
- Use native `pointerdown`/`pointermove`/`pointerup` events
- Calculate drag delta and apply transforms

### DrawSVG → CSS stroke-dashoffset animation

```css
.draw-in {
  stroke-dasharray: var(--path-length);
  stroke-dashoffset: var(--path-length);
  transition: stroke-dashoffset 1s ease-out;
}
.draw-in.active {
  stroke-dashoffset: 0;
}
```

### Detection rule

When `transition-spec.json` contains entries referencing GSAP premium plugins, add a note in the spec:

```json
{
  "name": "text-reveal-stagger",
  "gsap_plugin": "SplitText",
  "oss_alternative": "splitting (npm) or project animation library",
  "notes": "Replace SplitText.create() with splitting({ target: el, by: 'chars' })"
}
```

This ensures the generation step uses the correct alternative without re-discovering it.

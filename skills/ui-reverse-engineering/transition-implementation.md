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

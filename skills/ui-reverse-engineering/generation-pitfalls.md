# Generation Pitfalls

CSS-to-React translation errors and failure-based diagnosis for common bugs.

## CSS-to-React translation — 3 categories

### 1. Exit animations are impossible with conditional rendering

**Wrong:** `{showSplash && <SplashScreen />}` — React removes the DOM node instantly. No CSS transition can run on a removed node.

**Right:** keep animated elements in the DOM. Control visibility with `opacity`, `visibility`, `pointer-events`, `clip-path`. Only unmount after exit animation completes (use `AnimatePresence` or a `transitionend` listener).

### 2. Callback chains break on React lifecycle timing

**Wrong:** parent passes `onComplete` → child calls it in `useEffect` timeout → parent sets state → enables scroll. Callback reference changes between renders or timing misaligns with commit phase → chain breaks silently.

**Right:** independent timers with the same duration values. Parent and child both know the intro is 4.6s — each manages state independently. Or use a shared ref (no re-renders) for time-critical flags.

### 3. Text line splitting must match CSS, not character counts

**Wrong:** `text.split()` with hardcoded char limit (`> 55 chars`). Different line breaks than browser layout.

**Right:** one of:
- Apply `overflow: hidden` + `translateY` to the whole text block (whole-block reveal)
- Use `splitText` AFTER initial render to detect CSS-computed line boundaries
- Never pre-split text in JS unless matching exact container width + font metrics

## Failure-based diagnosis

When implementation visually matches but **behaves wrong** — or matches poorly — scan this table before debugging.

| Symptom | Root cause | Fix |
|---|---|---|
| `position: fixed` element scrolls with content | Inside a `transform`-ed parent | `createPortal(el, document.body)` |
| Scroll animations don't trigger | Custom scroll engine — IntersectionObserver / `window.scrollY` don't work | Subscribe to scroll engine's value stream |
| Splash elements remain visible after completion | Missing terminal state | Explicit `opacity: 0` + cleanup, or `return null` |
| Hover works on element but not children | Children have `pointer-events: auto` intercepting parent hover | `pointer-events-none` on overlay children |
| Text wraps differently despite same font-size | Different `max-width`, or WordReveal spans add whitespace | Remove max-width constraint; check word-splitting effect |
| SVG icon looks "similar" but wrong | SVG was recreated instead of extracted | Use `outerHTML` from `inline-svgs.json` verbatim |
| Sticky element exits viewport instead of pinning | Custom scroll wrapper uses transform, not native scroll | Use scroll progress to toggle `position: relative` vs manual transform pinning |
| Animation timing "feels off" | Easing/duration mismatch | Extract exact `transition`/`animation` CSS or GSAP `ease`/`duration` from bundle |
| Menu opens but nav bar doesn't animate | Overlay opens but nav elements lack per-element transition rules | Add per-element `transform`/`opacity` transitions keyed to `isOpen` |
| Text doesn't invert color over images | Missing `mix-blend-mode: difference` on parent | Check `advanced-styles.json` — apply to container, not text |
| "Gradient text" shows as solid color | Missing `background-clip: text` + `-webkit-text-fill-color: transparent` | CSS class with exact gradient from `backgroundImage` |
| Background doesn't transition dark/light on scroll | Missing `body` class toggle + `transition: background-color` | Check `body-state.json` — toggle class via scroll handler, CSS cascade handles rest |
| Nav logo doesn't invert in dark sections | Per-element React state instead of CSS cascade | `body.dark-class .nav-logo { filter: brightness(0) invert(1) }` |
| Sticky element unsticks too early/late | Wrong wrapper (container) height | Measure `diff(stickyCenter, lastContentCenter)` after unstick; adjust until `\|diff\| < 15` |
| Hundreds of pixels of dead space below last card | Section height hardcoded too large | Reduce to `lastContentBottom + 65px` |
| Marquee/scroll animation speed or spacing wrong | Guessed `gap` + `animation-duration` | Extract exact `gap`, `animation`, `animationDuration` from marquee track |
| Splash/intro transition doesn't play | `{condition && <div>}` — React unmounts before CSS transition | Keep in DOM, animate `opacity: 0` + `pointer-events: none`. Use `AnimatePresence` if unmount required |
| Text line breaks differ from reference | Hardcoded char-count split | CSS handles wrapping naturally (single `<p>`). Per-line reveal: `splitText` after render, or `overflow: hidden` + `translateY` on whole block |
| Scroll-driven overlay doesn't disappear | `onReady` callback error prevents scroll enable; listener gated behind state that never becomes true | Decouple scroll listener registration from animation callbacks. Use `setTimeout` matching intro duration. Register wheel listener immediately; gate delta application on a ref flag |
| Logo "assembles" in original but slides in impl | Bundle uses `.fromTo(".selector > *", {y: off}, {y: 0})` — children animate individually | Loop over `element.children` with per-child `translateY` + stagger. Never translate parent container |
| Splash data shows "element was always static" | `agent-browser eval` + `addInitScript` both missed it — GSAP set `from` before capture, so captured "initial" is mid-animation | Use video frames (Tier 1) as ground truth. Grep bundle for exact selectors + easing. DOM polling can't reliably capture first frame of DOMContentLoaded animations |
| Animation never runs on target page | Bundle has `if (isHome) { A } else { B }` — implemented B but target runs A | Read FULL conditional structure. Trace condition to source. `n \|\| (code)` means code runs when `!n`. See `animation-detection.md` "Conditional branches" |
| All transitions fire sequentially but original fires simultaneously | Separate `setTimeout` for each, but GSAP timeline has multiple `.to()` at position `0` or `"<"` | Parse GSAP position params: `0` = timeline start; `"<"` = same time as previous. Multiple tweens at same position = ONE setTimeout triggering ALL |
| CSS transition can't do multi-step (A→B hold→C) | CSS transition only supports A→B. Chaining is fragile | Use WAAPI `element.animate()` with multi-keyframe + `offset` |
| Animation code changes don't take effect | Modified shared package but consuming app has stale build | Rebuild the package → restart dev server. Bundlers don't hot-reload package `dist` changes |
| Overlay clips gradually (clipPath) but original disappears as whole panel | Original uses `translateX(-100%)` to slide off-screen, not clipPath progression. ClipPath is set once and stays fixed; scroll drives transform | Check `getBoundingClientRect().x` of overlay after scrolling. If `x < 0`, translated. But also check: is overlay `position: fixed` with separate scroll, OR part of horizontal scroll content itself? If `scrollY` stays 0 while `x` changes → inside Lenis/GSAP horizontal scroll — make it `flex-none w-screen` child, not fixed overlay |
| Overlay disappears too fast or too slow on scroll | `position: fixed` with `translateX(scrollProgress * -100%)` across entire content width | Likely NOT a fixed overlay — it's the FIRST item in horizontal scroll container. Place as `flex-none w-screen h-screen` child before hero/work items. Scrolls at 1:1 with content, no separate math. Verify: original `window.scrollY` stays 0 while overlay's `x` decreases → Lenis virtual scroll, inline |

**Usage:** When visual verification fails and the cause isn't obvious, scan this table before debugging. Most behavioral bugs match one of these categories.

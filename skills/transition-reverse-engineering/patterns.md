# Patterns & Troubleshooting

## CSS Patterns

| Pattern | Key Properties |
|---------|---------------|
| Fade in/out | `opacity`, 200-500ms |
| Slide in | `transform: translateX/Y`, 300-600ms |
| Scale up | `transform: scale()`, 200-400ms |
| Blur reveal | `filter: blur()`, 400-800ms |
| Clip expand | `clip-path: inset()`, 300-600ms |
| Card expand on hover | `clip-path: inset(Npx)` → `inset(0)` |
| Gradient border follow | `radial-gradient` + mouse tracking JS |
| 3D tilt | `perspective(Npx) rotateX() rotateY()` |
| Stagger children | `transition-delay` per child (50-150ms gap) |
| Character stagger | `splitText` → per-char WAAPI, continuous delay (10-20ms gap), blur+opacity+transform |

## Canvas/WebGL Patterns

| Pattern | Setup |
|---------|-------|
| Particle cloud | `Points` + `BufferGeometry` + `Float32Array` |
| Sphere distribution | `phi = acos(2r - 1)`, `theta = r * 2PI` |
| Globe with arcs | `Points` + `Line` with `QuadraticBezierCurve3` |
| Mouse-follow particles | `mousemove` → normalize → lerp uniform |
| Scroll-driven canvas | `IntersectionObserver` → uniform update |
| Responsive particle count | `innerWidth < 768 ? lowCount : highCount` |

## JS Animation (WAAPI) Patterns

### Character stagger (splitText + WAAPI)

Common in: LobeHub, Linear, Vercel hero sections.

**Key gotcha — WAAPI `fill: "forwards"` doesn't set initial state during delay:**

```typescript
// ❌ WRONG: Characters flash visible during stagger delay
nodes.forEach((node, i) => {
  node.animate([
    { opacity: 0, filter: "blur(4px)" },
    { opacity: 1, filter: "blur(0)" },
  ], { delay: i * 15, duration: 600, fill: "forwards" });
  // During delay, node shows its original opacity:1 state!
});

// ✅ CORRECT: Set initial state via inline styles, animate, commit final state
nodes.forEach((node) => {
  node.style.opacity = "0";
  node.style.filter = "blur(4px)";
  node.style.transform = "translateY(40px)";
});

// Using Web Animations API directly (no library dependency)
nodes.forEach((node, i) => {
  const anim = node.animate(
    [
      { opacity: 0, filter: "blur(4px)", transform: "translateY(40px)" },
      { opacity: 1, filter: "blur(0)",   transform: "translateY(0)" },
    ],
    { delay: i * 15, duration: 600, fill: "forwards", easing: "ease-out" }
  );
  anim.onfinish = () => {
    node.style.opacity = "1";
    node.style.filter = "none";
    node.style.transform = "none";
    anim.cancel(); // release fill:forwards so GC can collect
  };
});
```

**Why `onfinish` + `anim.cancel()`:** WAAPI animations with `fill: "forwards"` are GC-retained. Without committing inline styles and calling `cancel()`, the element either reverts or holds a memory-leaking animation object.

**Multi-line continuous stagger:** Maintain `globalCharIndex` across lines — line 2 continues from where line 1 ended.

**CSS class pitfall:**
```css
/* ❌ CSS rule outlives WAAPI animation → text disappears after GC */
.beyond-char { opacity: 0; }
```
Use inline styles, not CSS classes, for initial hidden state.

### Storybook iframe notes

- Components render inside iframe — timing differs from direct page load
- `layout: "fullscreen"` needed for full-viewport animations
- `setTimeout` (200ms+) before animations to ensure paint
- Replay via `key` prop remount is cleanest

## Troubleshooting

| Problem | Solution |
|---------|---------|
| Site shows error page / blank | Bot detection. Use `--headed` mode. |
| `eval` returns SyntaxError | No top-level `return`. Use IIFE `(() => { ... })()`. |
| WebGL `readPixels` returns zeros | `preserveDrawingBuffer: false` (default). Use screenshot for colors. |
| `transferSize: 0` for bundles | Cached. Use `document.querySelectorAll('script[src]')`. |
| 60+ JS chunks (Next.js/Nuxt/Vite) | Download all, grep for `canvas\|WebGL\|requestAnimationFrame`. |
| Canvas is Spline/Rive/Lottie | Check resources for `.splinecode`, `.riv`, `.json`. Data-driven. |
| No frames captured | Wrong selector or animation done. Reload and retry. |
| Cross-origin stylesheet | `curl` the CSS URL, grep for `@keyframes`. |
| Characters flash before stagger | WAAPI `fill: "forwards"` doesn't cover delay. Set inline `opacity: 0`. |
| Text disappears after animation | WAAPI GC'd, CSS rule took over. Use `onfinish` + `anim.cancel()` to commit inline styles. |
| React `useMotion` cancels animation | Strict mode remount calls cleanup. Use direct `splitText` + `useAnimate`. |
| Stagger only partial text | Check total char count. Use `globalCharIndex` for continuous stagger. |
| Re-capturing reference wastes time | Capture ONCE. Compare against saved files. |
| `--selector` screenshot times out | Use full-page `agent-browser screenshot` + sips crop. |
| `window.__scrub` missing mid-loop | Page reloaded. Re-inject before continuing. |

# Dynamic Content Protocol

Sites with auto-timers (carousels), Lottie animations, Canvas rendering, or
video backgrounds produce **non-deterministic screenshots**. Two captures of
the same page at the same scroll position will differ because animated content
changes between frames.

This protocol handles these sites so AE comparison remains meaningful.

## Detection (Phase 2 Step 5)

During interaction detection, flag the site:

```json
// interactions-detected.json
{
  "name": "hero-carousel",
  "trigger": "auto-timer",
  "dynamicContent": true,    // ← this flag
  "interval": "3-5s"
}
```

Also record in `scroll-engine.json`:
```json
{
  "hasDynamicContent": true,
  "dynamicRegions": [
    { "name": "hero-carousel", "scrollRange": [0, 990], "type": "auto-timer" },
    { "name": "lottie-animations", "scrollRange": [0, 11000], "type": "lottie" }
  ]
}
```

## Capture Protocol

### Step 1: Freeze before capture

Run `freeze-animations.sh <session>` AFTER page load completes (splash done)
but BEFORE any screenshot capture:

```bash
bash "$SCRIPTS_DIR/freeze-animations.sh" "$SESSION"
```

This kills timers, pauses CSS animations, hides canvases.

### Step 2: Record initial state

After freezing, detect which carousel slide is active:

```bash
agent-browser eval "(()=>{
  // Find carousel state indicators
  const active = document.querySelector('[class*=active],[aria-current=true],[data-active]');
  const infoCard = document.querySelector('[class*=info-card],[class*=card]');
  const title = infoCard?.querySelector('h2,h3')?.textContent?.trim();
  return JSON.stringify({ activeSlide: title || 'unknown' });
})()" --session "$SESSION"
```

Save to `tmp/ref/<component>/capture-state.json`.

### Step 3: Match impl state

Before capturing implementation, set impl to the same carousel state:

```bash
# Read capture-state.json to get activeSlide
# Set impl's initialIndex to match
```

### Step 4: AE threshold adjustment

For positions that overlap with `dynamicRegions`, use a higher AE threshold:

| Content type | Default threshold | Dynamic threshold |
|---|---|---|
| Static layout | 500 | 500 |
| Auto-timer carousel | 500 | 50,000 |
| Lottie animation area | 500 | 10,000 |
| Canvas (hidden) | 500 | 1,000 |

The `batch-compare.sh` script accepts an optional `dynamic-regions.json` file:

```bash
bash batch-compare.sh <dir> [threshold] [dynamic-regions.json]
```

When provided, positions that fall within dynamic regions use the higher threshold.

## Why not just freeze Lottie?

Lottie-web uses its own render loop that is NOT tied to `requestAnimationFrame`.
Overriding rAF does not stop Lottie SVG transforms from updating. The options are:

1. **Clone Lottie SVGs** — breaks animation references but the clone may re-animate
2. **Remove Lottie SVGs entirely** — loses visual content
3. **Accept Lottie frame differences** — use higher AE threshold for Lottie regions
4. **Capture at exact same rAF frame** — impractical across two separate captures

Option 3 is the most practical. The freeze script stops the major sources of
non-determinism (timers, CSS, canvas), and the remaining Lottie differences
are handled by threshold adjustment.

## Implementation checklist

When implementing a site with dynamic content:

- [ ] `capture-state.json` records which carousel slide was active during ref capture
- [ ] `impl` starts on the same slide (match `initialIndex`)
- [ ] `freeze-animations.sh` run before both ref and impl captures
- [ ] `dynamic-regions.json` created from `scroll-engine.json`
- [ ] `batch-compare.sh` invoked with dynamic regions for threshold adjustment
- [ ] Remaining FAIL positions diagnosed: is the FAIL from dynamic content or layout error?

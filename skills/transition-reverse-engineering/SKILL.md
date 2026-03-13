---
name: transition-reverse-engineering
description: Sub-skill for precise animation and transition extraction. Use when ui-reverse-engineering detects complex animations — WAAPI character stagger, canvas/WebGL particle systems, Three.js scenes, scroll-driven animations. Triggers on "extract this animation precisely", "copy this transition", "replicate this canvas effect". Combines WAAPI scrubbing with frame-by-frame visual comparison.
allowed-tools: Bash(agent-browser:open|close|screenshot|eval|wait|hover|click|scroll|record|set),Bash(curl:--max-filesize|--max-time|--fail|--location|-s|-o),Bash(grep:-E|-e|-c|--include)
---

# Transition Reverse Engineering

Precise extraction of animations and transitions from live sites. Called as a sub-skill by `ui-reverse-engineering` when complex motion is detected.

**Core principles:**
1. Extract actual values. Never guess timing, easing, positions, or counts.
2. Capture reference frames ONCE. Save to `tmp/ref/<effect-name>/`. Never re-visit.
3. All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.

## Effect Classification

```bash
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({
    cssTransition: s.transitionDuration !== '0s',
    cssAnimation: s.animationName !== 'none',
    canvases: document.querySelectorAll('canvas').length,
    transition: s.transition,
    willChange: s.willChange,
  });
})()"
```

| Signal | Path |
|--------|------|
| CSS transition/animation | **CSS Path** → see css-extraction.md |
| Canvas/WebGL present | **Canvas Path** → see canvas-webgl-extraction.md |
| Both | **Hybrid** → do both |

## Reference Files

- **css-extraction.md** — computed styles, keyframes, hover/scroll/load frame capture
- **canvas-webgl-extraction.md** — engine ID (Spline/Three.js/Rive/Lottie), bundle download, grep patterns
- **patterns.md** — CSS/Canvas/WAAPI patterns, character stagger, troubleshooting table
- **waapi-scrub-inject.js** — browser injector: cancel existing WAAPI, recreate paused, expose `window.__scrub.setup()` / `window.__scrub.seek()`
- **capture-frames.sh** — steps through `window.__scrub.seek(T)` + screenshot for N frames

## WAAPI Scrubbing (page-load animations)

Problem: `agent-browser open` waits for full load — page-load animations are already done.

```bash
agent-browser open https://target-site.com

# Inject scrubber — use actual absolute path to this skill directory
SKILL_DIR="$HOME/.claude/skills/ui-skills/skills/transition-reverse-engineering"
agent-browser eval "$(cat "$SKILL_DIR/waapi-scrub-inject.js")"

# Set up animations to scrub (fill in keyframes extracted from css-extraction.md)
agent-browser eval "
(() => {
  return window.__scrub.setup([
    {
      selector: '.hero',
      keyframes: [
        { opacity: '0', transform: 'translateY(43px)', filter: 'blur(16px)' },
        { opacity: '1', transform: 'translateY(0px)', filter: 'blur(0px)' }
      ],
      duration: 600,
      delay: 0
    }
  ]);
})()"

# Capture frames (output-dir must be relative, alphanumeric/dash/slash only)
"$SKILL_DIR/capture-frames.sh" tmp/ref/<effect-name>/frames 2000 15
```

**If `window.__scrub` disappears mid-capture** (page reloaded):
```bash
agent-browser eval "(() => typeof window.__scrub)()"
# If result is "undefined" — re-inject before continuing
agent-browser eval "$(cat "$SKILL_DIR/waapi-scrub-inject.js")"
```

## Visual Verification

**Never re-capture from original site.** Compare implementation against saved references.

```
ref frames (saved ONCE) → implement → capture impl frames → visual compare → adjust → repeat
```

Frame comparison table:

| Frame | Time | Ref | Impl | Match? | Issue |
|-------|------|-----|------|--------|-------|
| 01 | 0ms | frames/ref-01.png | frames/impl-01.png | ✅/❌ | |
| 08 | 50% | frames/ref-08.png | frames/impl-08.png | ✅/❌ | |
| 15 | 100% | frames/ref-15.png | frames/impl-15.png | ✅/❌ | |

For each ❌: identify exact property → targeted fix → re-capture impl only → compare.

## Output

Save to `tmp/ref/<effect-name>/extracted.json`:

```json
{
  "trigger": "page-load | hover | scroll | click",
  "totalDuration": 1600,
  "elements": [
    {
      "selector": ".hero",
      "from": { "opacity": "0", "transform": "translateY(43px)", "filter": "blur(16px)" },
      "to":   { "opacity": "1", "transform": "translateY(0px)",  "filter": "blur(0px)" },
      "duration": 600,
      "delay": 0,
      "easing": "cubic-bezier(0.16, 1, 0.3, 1)"
    }
  ]
}
```

## Key Pitfalls

| Problem | Solution |
|---------|---------|
| `fill: forwards` finished animations have higher cascade priority than inline styles | `el.style.opacity='0'` won't work. Must call `animation.cancel()` first. The injector handles this. |
| `element.style.setProperty('opacity','0','important')` blocks new WAAPI | Use `el.style.cssText=''` to clear completely. The injector handles this. |
| `onComplete` callbacks set `element.style.opacity='1'` after animation | These persist and block scrubbing. The injector's `clearInlineStyles()` removes them. |
| Staggered child animations | Pass each child's selector + delay separately in the configs array. |
| `--selector` screenshot times out | Use full-page `agent-browser screenshot <path>` + crop with `sips`: `sips raw.png --cropOffset <y> <x> --cropToHeightWidth <h> <w> --out cropped.png` |
| `window.__scrub` disappears mid-capture | Page reloaded. Re-inject using the command above. |
| CSS class rule outlives WAAPI animation | Text disappears after GC. Use inline styles + `onComplete`, not CSS classes for initial hidden state. |
| Characters flash visible during stagger delay | WAAPI `fill: "forwards"` doesn't set initial state during delay. Set `el.style.opacity = '0'` inline before animating. |
| Bot detection / blank page | Use `--headed` mode. See ui-reverse-engineering Step 1. |
| `eval` returns SyntaxError | No top-level `return`. Use IIFE `(() => { ... })()`. |
| WebGL `readPixels` returns zeros | `preserveDrawingBuffer: false` (default). Use screenshot for colors. |
| 60+ Next.js chunks | Download all, grep for `canvas\|WebGL\|requestAnimationFrame`. |
| Canvas is Spline/Rive/Lottie | Check resources for `.splinecode`, `.riv`, `.json`. Data-driven — reference scene URL or recreate with CSS. |

## Quick Reference

```bash
agent-browser open <url>
agent-browser eval "(() => { ... })()"   # IIFE only — no top-level return
agent-browser hover <selector>
agent-browser screenshot [path]
agent-browser wait <ms>
agent-browser close
```

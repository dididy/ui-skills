---
name: transition-reverse-engineering
description: Sub-skill for precise animation and transition extraction. Use when ui-reverse-engineering detects complex animations — WAAPI character stagger, canvas/WebGL particle systems, Three.js scenes, scroll-driven animations. Triggers on "extract this animation precisely", "copy this transition", "replicate this canvas effect". Combines WAAPI scrubbing with frame-by-frame visual comparison.
---

# Transition Reverse Engineering

Precise extraction of animations and transitions from live sites. Called as a sub-skill by `ui-reverse-engineering` when complex motion is detected.

**Core principles:**
1. Extract actual values. Never guess timing, easing, positions, or counts.
2. Capture reference frames ONCE. Save to `tmp/ref/<effect-name>/`. Never re-visit.
3. All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.
4. **Extraction ≠ completion.** Extraction ends when `extracted.json` is saved. Completion requires a passing visual verification cycle (impl frames vs ref frames). Never report done without running Phase B + Phase C.
5. **Diagnose before fixing.** When a visual mismatch or runtime bug appears, write one sentence identifying the root cause before touching any code. If you cannot name the cause, add `agent-browser eval` instrumentation to find it first.

## Scope

This skill operates in one of two scopes. **Always determine scope before starting.**

| Scope | When to use | What to compare |
|-------|-------------|-----------------|
| `element` | "copy this animation", "extract this hover effect" — isolated element behavior | Cropped frames of the target element only |
| `fullpage` | Page-level transition (route change, modal open/close, page-load sequence) — anything that affects the overall screen state | Full-page screenshots across the entire transition window: before → every intermediate state → after |

**Default scope by caller:**
- Called directly by user with a specific element target → `element`
- Called from a ralph worker task (task description contains `/transition-reverse-engineering`) → `fullpage`
- Ambiguous → ask: "Are you copying an isolated element animation, or a full page transition?"

**`fullpage` scope — mandatory checks:**
- Capture frames at: T=0 (before trigger), every 100ms during transition, T=end (settled state)
- For each frame: does the original show a blank screen / loading text / white flash / layout jump? If NO and your implementation does → **FAIL**. Fix before proceeding.
- "The animation looks right" is not sufficient — intermediate state must also match frame by frame.
- **Extract pane/layer structure with `getComputedStyle`** — measure `opacity`, `visibility`, `z-index`, `animation` on all pane elements at T=0, mid-transition, and T=end. This reveals how old/new content layers interact (e.g. new pane stays `visibility:hidden` until data is ready — never expose loading state to user).

## Step 0: Capture Reference Frames FIRST

> **Before classifying or extracting anything, capture reference frames from the original site. This is your ground truth.**

```bash
mkdir -p tmp/ref/<effect-name>/frames/{ref,impl}

# For CSS transitions/hover effects:
agent-browser open https://target-site.com
agent-browser set viewport 1440 900
agent-browser screenshot tmp/ref/<effect-name>/frames/ref/before.png
agent-browser hover <target-selector>
agent-browser wait 600
agent-browser screenshot tmp/ref/<effect-name>/frames/ref/after-hover.png

# For page-load / scroll animations — use video:
agent-browser record start tmp/ref/<effect-name>/ref.webm
agent-browser wait 3000     # capture the full animation
agent-browser record stop
# Extract frames:
ffmpeg -i tmp/ref/<effect-name>/ref.webm -vf fps=60 tmp/ref/<effect-name>/frames/ref/frame-%04d.png -y
```

**GATE: `tmp/ref/<effect-name>/frames/ref/` must contain reference frames before proceeding. If empty → repeat Step 0.**

Now classify the effect:

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
| CSS transition/animation | **CSS Path** → Read `css-extraction.md`, execute |
| Canvas/WebGL present | **Canvas Path** → Read `canvas-webgl-extraction.md`, execute |
| Both | **Hybrid** → Read and execute both |

> **GATE: You must run the classification eval above and record the result before choosing a path. Do not guess the effect type — measure it.**

## Reference Files

> **MANDATORY: Use the Read tool to load the relevant `.md` file BEFORE executing each path. These contain the exact commands and procedures — do not improvise from memory.**

- **css-extraction.md** — Read this when Effect Classification → CSS Path. Contains computed style extraction, keyframe capture, hover/scroll/load frame procedures.
- **canvas-webgl-extraction.md** — Read this when Effect Classification → Canvas Path. Contains engine identification (Spline/Three.js/Rive/Lottie), bundle download, grep patterns.
- **patterns.md** — Read this when implementing. Contains CSS/Canvas/WAAPI patterns, character stagger recipes, troubleshooting table.
- **waapi-scrub-inject.js** — browser injector: cancel existing WAAPI, recreate paused, expose `window.__scrub.setup()` / `window.__scrub.seek()`
- **capture-frames.sh** — steps through `window.__scrub.seek(T)` + screenshot for N frames

## WAAPI Scrubbing (page-load animations)

Problem: `agent-browser open` waits for full load — page-load animations are already done.

```bash
agent-browser open https://target-site.com

# Inject scrubber — resolve skill directory from common install locations
SKILL_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/ui-skills/skills/transition-reverse-engineering"
# If installed via npx skills or a custom path, override: export CLAUDE_SKILLS_DIR=/your/path
if [ ! -f "$SKILL_DIR/waapi-scrub-inject.js" ]; then
  echo "Error: skill not found at $SKILL_DIR — set CLAUDE_SKILLS_DIR to your install path" >&2
  exit 1
fi
agent-browser eval "$(cat "$SKILL_DIR/waapi-scrub-inject.js")"

# Set up animations to scrub (fill in keyframes extracted from css-extraction.md)
# selector must be a valid CSS selector string (e.g. '.hero', '#title span')
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

### scope: element

Frame comparison table (cropped to element bounds):

| Frame | Time | Ref | Impl | Match? | Issue |
|-------|------|-----|------|--------|-------|
| 01 | 0ms | frames/ref-01.png | frames/impl-01.png | ✅/❌ | |
| 08 | 50% | frames/ref-08.png | frames/impl-08.png | ✅/❌ | |
| 15 | 100% | frames/ref-15.png | frames/impl-15.png | ✅/❌ | |

For each ❌: identify exact property → targeted fix → re-capture impl only → compare.

### scope: fullpage

Full-page screenshot comparison across the entire transition window:

| Frame | Time | Ref | Impl | Match? | Issue |
|-------|------|-----|------|--------|-------|
| 01 | 0ms (before) | frames/ref-01.png | frames/impl-01.png | ✅/❌ | |
| 02 | ~100ms | frames/ref-02.png | frames/impl-02.png | ✅/❌ | |
| ... | every 100ms | ... | ... | | |
| N | end (settled) | frames/ref-N.png | frames/impl-N.png | ✅/❌ | |

**Additional checks for fullpage:**
- Any frame where ref shows content but impl shows blank/loading/white → ❌ FAIL
- Any frame where ref shows smooth transition but impl shows layout jump → ❌ FAIL
- Intermediate frames (not just start/end) must match — do not skip mid-transition frames

For each ❌: write one sentence naming the root cause before touching code. If you cannot name it, run `agent-browser eval` to inspect computed styles at the exact failing frame. Only after root cause is confirmed → fix → re-capture impl only → compare.

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
| `onfinish` callbacks set `element.style.opacity='1'` after animation | These persist and block scrubbing. The injector's `clearInlineStyles()` removes them. |
| Staggered child animations | Pass each child's selector + delay separately in the configs array. |
| `--selector` screenshot times out | Use full-page `agent-browser screenshot <path>` + crop with `sips`: `sips raw.png --cropOffset <y> <x> --cropToHeightWidth <h> <w> --out cropped.png` |
| `window.__scrub` disappears mid-capture | Page reloaded. Re-inject using the command above. |
| CSS class rule outlives WAAPI animation | Text disappears after GC. Use inline styles + `onfinish` → `anim.cancel()`, not CSS classes for initial hidden state. |
| Characters flash visible during stagger delay | WAAPI `fill: "forwards"` doesn't set initial state during delay. Set `el.style.opacity = '0'` inline before animating. |
| Bot detection / blank page | Use `--headed` mode. See ui-reverse-engineering Step 1. |
| `eval` returns SyntaxError | No top-level `return`. Use IIFE `(() => { ... })()`. |
| WebGL `readPixels` returns zeros | `preserveDrawingBuffer: false` (default). Use screenshot for colors. |
| 60+ JS chunks (Next.js/Nuxt/Vite) | Download all, grep for `canvas\|WebGL\|requestAnimationFrame`. |
| Canvas is Spline/Rive/Lottie | Check resources for `.splinecode`, `.riv`, `.json`. Data-driven — reference scene URL or recreate with CSS. |

## When called from a ralph worker

If this skill is invoked as part of a ralph task (e.g. task description contains `/transition-reverse-engineering`):

1. **Dismiss any modals or overlays before capturing** — cookie banners, signup prompts, etc. must be closed first
2. **"Already implemented" is not grounds for skipping** — always capture reference frames and compare against current implementation, even if the transition appears to be done
3. **Reference frames saved once to `tmp/frames-original/<effect-name>/`** — never re-capture from original site mid-iteration
4. **Implementation frames to `tmp/frames-ours/<effect-name>/`** after each change
5. **Repeat until 100% visual match** — do not converge while any frame shows a discrepancy
6. All timing/easing values must come from extracted measurements — no guessing
7. **Capture the FULL transition window — including intermediate states.** Frames must cover: before transition starts, every mid-transition state, and after transition ends. If the original shows NO blank screen / loading text / white flash during transition, your implementation must also show none. Any intermediate state present in your implementation but absent in the original is a FAIL — fix before converging.

## Bug Diagnosis Protocol

When a visual bug is reported (white flash, wrong timing, layout jump, etc.):

**Before writing any fix:**
1. Name the root cause in one sentence: _"The white flash happens because X"_
2. If you cannot name it, instrument first:
   ```bash
   agent-browser eval "
   (() => {
     const panes = document.querySelectorAll('[class*=pane], [class*=slot]');
     return JSON.stringify([...panes].map(el => {
       const s = getComputedStyle(el);
       return { cls: el.className, opacity: s.opacity, visibility: s.visibility, zIndex: s.zIndex, position: s.position, height: el.offsetHeight };
     }));
   })()"
   ```
3. Only after root cause is confirmed → write the fix
4. After fix → re-capture impl frames → verify the specific bug frame is gone

**Do not iterate on the same approach more than twice.** If two fixes in the same direction don't work, the diagnosis was wrong — re-instrument and re-diagnose.

## Checklist: "Is This Done?"

- [ ] `extracted.json` saved
- [ ] Implementation written
- [ ] Phase B impl frames captured (localhost, same trigger sequence as ref)
- [ ] Phase C comparison table filled — every frame has ✅ or ❌
- [ ] All ❌ rows fixed and re-verified
- [ ] No white flash / blank frame / layout jump in any impl frame where ref shows content
- [ ] Entry points verified: CSS imports loaded (`body { margin: 0 }` etc. in effect), no missing `import` in main entry file

## Quick Reference

```bash
agent-browser open <url>
agent-browser eval "(() => { ... })()"   # IIFE only — no top-level return
agent-browser hover <selector>
agent-browser screenshot [path]
agent-browser wait <ms>
agent-browser close
```

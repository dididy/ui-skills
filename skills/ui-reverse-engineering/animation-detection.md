# Animation Detection — Step 6

Detect ALL motion on the page: splash/intro animations, auto-playing elements, scroll-driven transitions, and parallax effects. Uses **high-framerate video capture** + **per-element tracking**.

> This step runs AFTER interaction-detection.md (Step 5) and supplements it.
> Step 5 catches hover/click/intersection transitions.
> Step 6 catches everything that MOVES — with or without user input.

## Strategy: 3-Phase Motion Detection

```
Phase A: IDLE CAPTURE (no interaction)
  Record 8-10s video at page load. No scrolling, no mouse movement.
  → Detects: splash/intro animation, auto-timers, CSS animations, video autoplay

Phase B: SCROLL CAPTURE (scroll top to bottom)
  Record full scroll video at 60fps. Consistent scroll speed.
  → Detects: scroll-driven parallax, scale transitions, sticky elements,
             clip-path reveals, opacity fades, position changes

Phase C: PER-ELEMENT TRACKING (targeted)
  For each section/element identified in Phase A or B:
  Capture element-specific video + extract computed style at multiple scroll positions.
  → Produces: exact transform/opacity/scale values at each scroll %
```

---

## Phase A: Idle Capture (Splash + Auto-timers) — MANDATORY

> **This phase is MANDATORY for ALL sites.** It is the ONLY way to detect:
> - Splash/intro animations that play once on page load and are removed from the DOM
> - Loading sequences (logo reveal, curtain open, text stagger)
> - Auto-playing carousels, rotating text, or video backgrounds
> - Custom cursor animations
>
> **If you skip this, you will miss the entire first-impression experience.**
> Many architecture/design studio sites (like 9to5studio.it) have elaborate intro sequences
> that are invisible to static DOM inspection because the elements are removed or hidden
> after the animation completes.

**Purpose:** Find everything that moves WITHOUT user interaction.

**Execution protocol — do not split or reorder these commands:**

The commands below MUST be executed as a **single sequential block**. The critical insight is that `record start` must happen BEFORE `wait` — if you open the page, wait for it to load, and THEN start recording, the splash/intro animation has already played and you've captured nothing. This is the #1 reason idle capture fails silently.

```bash
# ══════════════════════════════════════════════════════════════
# EXECUTE THIS ENTIRE BLOCK. DO NOT INSERT OTHER STEPS BETWEEN.
# DO NOT "wait for the page to load first" — that defeats the purpose.
# The recording must start DURING page load, not after.
# ══════════════════════════════════════════════════════════════

# 1. Close any existing session (clean slate)
agent-browser --session <project> close

# 2. Open page — this triggers the splash/intro animation
agent-browser --session <project> open <url>
agent-browser --session <project> set viewport 1440 900

# 3. START RECORDING IMMEDIATELY — before any wait
#    The splash animation is playing RIGHT NOW during page load.
#    If you wait 3-6 seconds first, the splash is already gone.
agent-browser --session <project> record start tmp/ref/<component>/idle-capture.webm

# 4. Wait 10 seconds — capture the full splash + settle period
agent-browser --session <project> wait 10000

# 5. Stop recording
agent-browser --session <project> record stop

# 6. Extract frames
mkdir -p tmp/ref/<component>/idle-frames
ffmpeg -i tmp/ref/<component>/idle-capture.webm -vf fps=10 tmp/ref/<component>/idle-frames/frame-%04d.png -y

# 7. CHECKPOINT — if idle-capture.webm doesn't exist or is < 50KB, re-run from step 1
ls -la tmp/ref/<component>/idle-capture.webm
ls tmp/ref/<component>/idle-frames/ | wc -l
# Expected: video > 50KB, frames > 50

# ══════════════════════════════════════════════════════════════
```

**Why "wait first, then record" is wrong:**
A common mistake is opening the page, waiting 5-6 seconds for "the page to fully load", dismissing cookie banners, THEN starting the idle capture. By that point:
- The splash/intro animation has already played and finished
- Loading overlay elements may have been removed from DOM
- Text reveal animations have completed
- You record 10 seconds of a static page and conclude "no splash detected"

The recording must start **during** page load. Cookie banners can be dismissed after the recording — they don't interfere with splash detection since they overlay on top.

### Analyze idle frames — 3-tier approach (token-efficient)

> **Do NOT Read every frame with the LLM.** 104 frames × ~2500 tokens = 260K tokens wasted.
> Use automated tools first, LLM only for what automation can't classify.

**Tier 1: AE diff — find WHEN changes happen (zero tokens)**

```bash
# Compare consecutive frames — outputs frame numbers where visual change exceeds threshold
cd tmp/ref/<component>/idle-frames
echo "frame,ae_diff" > ../idle-frame-diffs.csv
PREV=""
for f in $(ls frame-*.png | sort); do
  if [ -n "$PREV" ]; then
    AE=$(compare -metric AE "$PREV" "$f" /dev/null 2>&1 | awk '{print $1}')
    echo "$f,$AE" >> ../idle-frame-diffs.csv
  fi
  PREV="$f"
done

# Find significant change frames (AE > 5000 = visual change, not just noise)
echo ""
echo "=== Significant changes ==="
awk -F',' '$2 > 5000 { print $1 " — AE=" $2 }' ../idle-frame-diffs.csv
```

This tells you the exact frame numbers where transitions occur — without reading any images.

**Tier 2: DOM polling at 60fps — find WHAT changed (zero tokens)**

Run this as a second pass after Tier 1 identifies change windows.

> **CRITICAL: Use `requestAnimationFrame`, NOT `setInterval`.** 200ms polling (5fps) misses
> the majority of CSS transition frames. A 0.8s ease-out transition has ~48 intermediate values
> at 60fps but only ~4 at 200ms intervals — you lose the easing curve shape entirely.
> At 200ms you can detect THAT something changed, but not HOW it changed (easing, direction, axis).

### Splash throttle protocol (MANDATORY when Tier 1 detects early motion)

`agent-browser eval` executes AFTER the page loads and JS hydrates. By that point, splash/intro
animations that fire on `DOMContentLoaded` or in the first rAF cycle have already played.
Your 60fps capture starts recording a **static, post-animation state** and you conclude
"the logo doesn't move" or "no splash transition" — when in reality the transition already finished.

**How to detect this:** If Tier 1 AE diff shows significant changes in the first 1-3 seconds
(frames 1-30 at 10fps), a splash transition exists. The splash is the data you most need
60fps CSS values for — and it's exactly what `eval` misses.

**Fix: Network throttle to slow page load, giving eval time to inject before animations fire.**

```bash
# 1. Open page with network throttle — delays JS execution so eval lands before splash fires
agent-browser --session <project> close
agent-browser --session <project> open <url>
agent-browser --session <project> set viewport 1440 900
agent-browser --session <project> throttle 3g

# 2. Inject rAF capture IMMEDIATELY — before throttled JS finishes loading
agent-browser --session <project> eval "(() => {
  window.__frames = [];
  const start = performance.now();
  const targets = [
    '[class*=load]', '[class*=intro]', '[class*=splash]', '[class*=overlay]',
    '[class*=logo]', '[class*=text]', '[class*=image]', '[class*=bg]',
    'section', 'header', 'nav', 'main'
  ];
  const capture = () => {
    const t = performance.now() - start;
    if (t > 12000) return;
    const els = [];
    for (const sel of targets) {
      document.querySelectorAll(sel).forEach(el => {
        const s = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        if (r.width < 10 && r.height < 10) return;
        els.push({
          sel: (el.className?.toString?.() || el.tagName).slice(0, 40),
          op: +s.opacity,
          tf: s.transform !== 'none' ? s.transform.slice(0, 50) : null,
          cp: s.clipPath !== 'none' ? s.clipPath.slice(0, 50) : null,
          y: Math.round(r.top), h: Math.round(r.height),
        });
      });
    }
    window.__frames.push({ t: Math.round(t), els });
    requestAnimationFrame(capture);
  };
  requestAnimationFrame(capture);
  return 'capturing with throttle...';
})()"

# 3. Remove throttle — let the page load normally, splash fires while capture is running
agent-browser --session <project> throttle off

# 4. Wait for capture to complete (longer due to throttled start)
agent-browser --session <project> wait 13000

# 5. Retrieve data
agent-browser --session <project> eval "(() => JSON.stringify(window.__frames || []))()"
```

Save to `tmp/ref/<component>/idle-dom-60fps-throttled.json`.

**When to use throttle vs non-throttle:**
- Tier 1 shows AE spikes in first 3s → use throttled Tier 2 (captures splash)
- Tier 1 shows NO changes in first 3s → use normal Tier 2 (faster, splash doesn't exist)
- Always verify: if throttled Tier 2 shows elements appearing mid-capture that weren't
  in the first frame, you caught the splash. If first frame already has all elements
  in their final state, the throttle wasn't enough — increase to `throttle 2g` or use
  Tier 3 video frame analysis instead.

**Fallback: If agent-browser doesn't support `throttle`**, use the video frames from Tier 1
to measure splash transitions visually:
1. Extract at 60fps: `ffmpeg -i idle-capture.webm -vf fps=60 idle-frames-60fps/frame-%04d.png`
2. Measure logo bounding box at frame N vs frame N+5 to compute scale/translate delta
3. Cross-reference with bundle analysis for exact easing/duration values

### MANDATORY: Video frame → bundle cross-reference for splash animations

> **Both Tier 2 methods (`agent-browser eval` and Playwright `addInitScript`) can miss splash
> animations.** `eval` runs after page load. `addInitScript` runs before page load BUT after
> React hydration — by then, GSAP/CSS animations triggered on `DOMContentLoaded` have already
> set their initial `from` values. The 60fps capture records the element moving from `from` to
> `to`, but the `from` value was already applied before capture started, so it looks like
> "the element was always at this position" (e.g., logo reports `transform: none` because
> GSAP already moved it to `y: height*2` before the capture started, then animated to `y: 0`
> which is `transform: none`).
>
> **Video frames are the ONLY reliable source for splash animation behavior.**

When Tier 1 video shows a splash transition but Tier 2 DOM data shows "no changes" or
"element was always static", follow this protocol:

**Step 1: Extract video at 60fps and identify the transition frames**
```bash
ffmpeg -i idle-capture.webm -vf fps=60 idle-frames-60fps/frame-%04d.png -y
# AE diff to find exact transition frame range
```

**Step 2: Read 3-5 frames across the transition to understand WHAT is moving**
Look for:
- Individual SVG parts moving separately (staggered assembly)
- Whole element translating vs children translating
- Scale changes on specific sub-elements
- Elements appearing from off-screen edges

**Step 3: IMMEDIATELY grep the bundle for the animation target selector**
```bash
grep -o '.\{0,150\}logo.\{0,150\}' bundles/main.js
grep -o '.\{0,150\}loader.\{0,150\}' bundles/main.js
grep -o '.\{0,150\}splash.\{0,150\}' bundles/main.js
grep -o '.\{0,150\}intro.\{0,150\}' bundles/main.js
```

**Step 4: Look for child-selector patterns in the bundle**
The critical pattern: `.fromTo(".selector > *", {y: offset}, {y: 0})` means **each child
element animates individually**, not the parent. This is common for:
- SVG logo assembly (each `<path>`, `<g>`, `<rect>` moves independently)
- Text word/letter stagger (splitType → each span moves)
- Grid card reveals (each card enters with delay)

If you find `> *` or `.children` or `stagger` in the GSAP code, the animation is
**per-child**, not per-container. Implement with a loop over `element.children`,
not a single transform on the parent.

**Anti-pattern this prevents:** You see the logo "move up" in the video, implement
`logo.style.transform = 'translateY(-150%)'`, and get a completely different visual
because the original animates each SVG rect/path individually from below.

### MANDATORY: Parse GSAP timeline structure from bundle (not just grep values)

> **Screenshots and frame comparison can show THAT something moves, but NOT the timeline structure.**
> A GSAP timeline with `delay: 0.28` and three simultaneous `.to()` calls at position `0`
> looks completely different from three sequential `setTimeout()` calls. You MUST read the
> timeline code from the bundle and reconstruct the execution order.

**What to extract from the bundle timeline:**

1. **Timeline defaults**: `delay`, `duration`, `ease` — these apply to ALL tweens unless overridden
2. **Position parameters**: `0`, `"<"`, `"<+=0.1"`, `">-0.5"` — these define WHEN each tween starts relative to others
   - `0` = at timeline start
   - `"<"` = at same time as previous tween
   - `"<+=0.1"` = 0.1s after previous tween STARTS
   - No position = after previous tween ENDS
3. **Simultaneous vs sequential**: Multiple tweens at position `0` or `"<"` = they run AT THE SAME TIME
4. **`.add(() => {...})` callbacks**: These fire at specific timeline positions and can trigger CSS class changes, DOM mutations, or sub-animations (e.g., FLIP)
5. **FLIP pattern**: `u.getState(elements)` → DOM change → `u.from(state, {targets, duration, ease})` = elements animate from their OLD position to their NEW position

**Implementation mapping:**

| GSAP timeline pattern | CSS/JS implementation |
|---|---|
| Multiple `.to()` at position `0` | Single `setTimeout` that triggers ALL transitions simultaneously |
| `.to({}, {duration: 1.2}, 0)` (empty tween) | Timer delay of 1.2s before next sequential step |
| `"<"` position | Same `setTimeout` as previous, or CSS transitions starting at same time |
| `"<+=0.1"` position | Second `setTimeout` at `firstTimer + 100ms` |
| `delay: 0.28` on timeline | Add 280ms to the base timer value |
| FLIP `u.from(state, ...)` | `translateY(largeValue) → translateY(0)` with same duration/easing |

**Fixed overlay cleanup (MANDATORY before any capture):**

Before capturing ANY reference screenshots or videos, remove all fixed/sticky overlays
that are NOT part of the site's actual UI (header/nav excluded). These corrupt every
frame comparison and AE diff.

```bash
agent-browser eval "(() => {
  const removed = [];

  // 1. Dismiss cookie/consent banners via click
  const dismissSelectors = ['.iubenda-cs-reject-btn', '.iubenda-cs-accept-btn',
    '[class*=cookie] button', 'button[class*=accept]', 'button[class*=reject]'];
  for (const sel of dismissSelectors) {
    const btn = document.querySelector(sel);
    if (btn) { btn.click(); removed.push('clicked: ' + sel); }
  }
  const btns = document.querySelectorAll('button');
  for (const b of btns) {
    if (/accept|accetta|rifiuta|reject|dismiss|got.it|agree/i.test(b.textContent)) {
      b.click(); removed.push('clicked: ' + b.textContent.trim().slice(0, 20));
    }
  }

  // 2. Force-remove remaining fixed/sticky overlays (not header/nav)
  for (const el of document.querySelectorAll('*')) {
    const s = getComputedStyle(el);
    if (s.position !== 'fixed' && s.position !== 'sticky') continue;
    const r = el.getBoundingClientRect();
    if (r.width < 100 || r.height < 50) continue; // skip tiny elements
    const tag = el.tagName.toLowerCase();
    const cls = (el.className?.toString?.() || '').toLowerCase();
    // Keep: header, nav, main navigation
    if (tag === 'header' || tag === 'nav') continue;
    if (cls.includes('header') || cls.includes('nav') || cls.includes('menu')) continue;
    // Keep: elements that are part of the page content (intro overlays, loaders)
    if (cls.includes('intro') || cls.includes('loader') || cls.includes('hero')) continue;
    // Remove: cookie banners, modals, toasts, chat widgets, promo bars
    if (cls.includes('cookie') || cls.includes('consent') || cls.includes('modal')
      || cls.includes('toast') || cls.includes('popup') || cls.includes('banner')
      || cls.includes('chat') || cls.includes('widget') || cls.includes('promo')
      || cls.includes('iubenda') || cls.includes('gdpr') || cls.includes('notice')) {
      el.remove();
      removed.push('removed: ' + cls.slice(0, 40));
      continue;
    }
    // Heuristic: if z-index > 1000 and not a nav, likely an overlay
    const z = parseInt(s.zIndex) || 0;
    if (z > 1000) {
      el.style.display = 'none';
      removed.push('hidden(z=' + z + '): ' + cls.slice(0, 30));
    }
  }

  return JSON.stringify(removed);
})()"
```

Run this ONCE after page load, BEFORE any recording or screenshot.
If overlays reappear after scroll/interaction, run again before the next capture.
If the banner cannot be dismissed, use `agent-browser cookies clear` before opening the page.

### AE diff curve analysis — easing, hold, and timing inference (zero tokens)

AE diff values over consecutive frames form a **curve** that reveals animation characteristics
without reading any images or spending tokens.

```bash
# Generate AE diff CSV at 60fps (MANDATORY — DO NOT change fps value)
# 60fps = 16.7ms per frame. Cost: zero tokens. Disk: ~180MB for 10s. Clean up after.
ffmpeg -i capture.webm -vf fps=60 frames/frame-%04d.png -y
cd frames
echo "frame,ae" > ../ae.csv
PREV=""
for f in $(ls frame-*.png | sort); do
  if [ -n "$PREV" ]; then
    AE=$(compare -metric AE "$PREV" "$f" /dev/null 2>&1 | awk '{print $1}')
    echo "$f,$AE" >> ../ae.csv
  fi
  PREV="$f"
done
```

**Reading the AE curve:**

| AE pattern | Meaning |
|-----------|---------|
| `0, 0, 0, 0` | **Hold** — element is stationary. Count consecutive zeros × frame interval = hold duration |
| `0, 5K, 20K, 50K, 80K, 90K, 95K` | **Ease-in** — starts slow, accelerates |
| `95K, 90K, 80K, 50K, 20K, 5K, 0` | **Ease-out** — starts fast, decelerates |
| `5K, 50K, 90K, 90K, 50K, 5K` | **Ease-in-out** — slow start, fast middle, slow end |
| `90K, 85K, 80K, 75K, 70K` | **Linear** — consistent change rate |
| `0, 0, 80K, 0, 0` | **Instant/step** — single-frame change |

**Transition boundary detection:**
- **Start**: first frame where AE > threshold (e.g., 5000)
- **End**: last frame where AE > threshold before returning to 0
- **Duration**: (end_frame - start_frame) / fps

**Multi-transition separation:**
When AE goes `high → 0 → high`, the zero gap = hold between transitions.
Map each high-AE block to a separate animation phase.

**A/B timing comparison (implementation vs original):**
Run AE diff on BOTH videos, then align by matching the pattern:
1. Find the first significant AE spike in each → alignment anchor
2. Compare: does each subsequent spike occur at the same relative time?
3. Hold durations should match (same number of zero-AE frames)
4. Peak AE values indicate transition magnitude — similar peaks = similar visual change

**This replaces screenshot-based timing comparison**, which suffers from:
- agent-browser `wait` timing inaccuracy
- Video recording start offset
- Human visual estimation errors

AE diff is deterministic, frame-accurate, and costs zero tokens.

### CRITICAL: Bundle code is the spec, frames are verification

> **Never derive animation parameters from frame analysis alone.**
> Frames show THAT something moves. The bundle shows HOW (easing, duration, delay, position).
> When frames and bundle disagree, the bundle is correct — you may be looking at
> the wrong conditional branch, or the frame capture missed the start of the animation.
>
> Workflow:
> 1. Parse bundle → extract exact timeline structure (position params, durations, easings)
> 2. Implement from bundle spec
> 3. Capture both original + implementation at 120fps
> 4. Run AE diff on both → compare curves
> 5. If curves don't match → re-read bundle (probably misinterpreted a position parameter)

### CRITICAL: Conditional animation branches in bundles

> **A single JS bundle often contains MULTIPLE animation paths gated by conditions.**
> The most common pattern: `if (isHomePage) { introTimeline } else { heroAssembly }`.
> If you grep for "logo" and find an SVG assembly animation, it may NOT run on the
> page you're cloning. You MUST read the conditional structure around the animation code.

**Pattern to watch for:**
```js
if (n) {
  // Path A: runs when condition is true (e.g., homepage first visit)
  _.to(".introHome", { clipPath: "..." })
} else {
  // Path B: runs when condition is false (e.g., navigating to home from another page)
  Oe.timeline().fromTo(".hero .gsap:logo > *", { y: offset }, { y: 0 })
}

// OR: n || (Path B code) — equivalent to if (!n) { Path B }
```

**How to identify which path runs:**
1. Find the condition variable (`n`, `i`, `r`) — trace it back to where it's assigned
2. Common patterns: `const n = t.meta.templateName === "home"`, `const i = e.meta.templateName === "work"`
3. Check what the condition means for YOUR target page
4. Only implement the animation code from the CORRECT branch

**Failure mode this prevents:** You implement an elaborate SVG logo assembly animation
that looks cool but NEVER runs on the homepage first visit — because it's in the `else`
branch. Meanwhile the ACTUAL animation (GSAP FLIP from siteLoader to introHome) is in
the `if` branch and you never implemented it.

### Frame comparison requires cookie banner dismissal first

Before ANY A/B frame comparison between original and implementation:
1. Dismiss cookie banner on original site
2. Clear cookies + localStorage if needed to trigger intro replay
3. Verify banner is gone before recording

Without this, every frame comparison includes a ~400×300px opaque banner overlay that
corrupts AE diff values and makes visual comparison unreliable.

---

### Standard Tier 2 (no splash, or post-splash analysis)

**Method: agent-browser eval + `requestAnimationFrame`**

```bash
# Open fresh page
agent-browser --session <project> close
agent-browser --session <project> open <url>
agent-browser --session <project> set viewport 1440 900

# Inject 60fps rAF capture immediately after page opens
agent-browser --session <project> eval "(() => {
  window.__frames = [];
  const start = performance.now();
  const targets = [
    '[class*=load]', '[class*=intro]', '[class*=splash]', '[class*=overlay]',
    '[class*=logo]', '[class*=text]', '[class*=image]', '[class*=bg]',
    'section', 'header', 'nav', 'main'
  ];
  const capture = () => {
    const t = performance.now() - start;
    if (t > 8000) return;
    const els = [];
    for (const sel of targets) {
      document.querySelectorAll(sel).forEach(el => {
        const s = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        if (r.width < 10 && r.height < 10) return;
        els.push({
          sel: (el.className?.toString?.() || el.tagName).slice(0, 40),
          op: +s.opacity,
          tf: s.transform !== 'none' ? s.transform.slice(0, 50) : null,
          cp: s.clipPath !== 'none' ? s.clipPath.slice(0, 50) : null,
          y: Math.round(r.top), h: Math.round(r.height),
        });
      });
    }
    window.__frames.push({ t: Math.round(t), els });
    requestAnimationFrame(capture);
  };
  requestAnimationFrame(capture);
  return 'capturing 60fps for 8s...';
})()"

# Wait for capture to complete
agent-browser --session <project> wait 9000

# Retrieve the full 60fps data
agent-browser --session <project> eval "(() => JSON.stringify(window.__frames || []))()"
```

> **Note:** This standard method captures post-splash animations only. If Tier 1 detected
> a splash transition (AE spikes in first 3s), use the **Splash throttle protocol** above
> instead — it injects the capture script before the splash fires.

**Why 60fps matters for animation extraction:**

| Property | 200ms (5fps) | 16ms (60fps) |
|----------|-------------|-------------|
| clipPath direction | `inset(0% 0% 0%)` → `inset(0% 0% 3.7%)` — can't tell which axis is animating | `inset(0% 0% 0.03%)` → `inset(0% 0% 0.06%)` — clearly 3rd value (bottom) |
| easing curve | 4 samples — looks linear | 48 samples — distinguishes ease-in from ease-out from power5 |
| transform axis | `scale(1)` → `scale(0.5)` — can't see intermediate trajectory | `scale(0.85)` → `scale(0.63)` → shows deceleration curve |
| simultaneous properties | Both opacity and transform changed "between frames" | opacity started at t=1260, transform at t=1260 — confirms they're coupled |

Save the output to `tmp/ref/<component>/idle-dom-60fps.json`. This gives you:
- Per-frame values at true animation resolution
- Exact easing curve shape (not just start/end values)
- Which axis of clipPath/transform is actually animating
- Whether properties are coupled or staggered

**Tier 3: LLM Read — only for transition boundaries (minimal tokens)**

After Tier 1 and Tier 2, you know:
- WHEN changes happen (frame numbers from AE diff)
- WHAT elements change (DOM properties from polling)

Read images with LLM ONLY when:
1. Tier 1 shows a large AE spike but Tier 2 DOM log shows no property changes → visual change is from image content, not CSS properties. Read 1 frame to identify what's visible.
2. You need to classify the visual state at a specific transition boundary (e.g., "is the splash fully gone by frame 35?"). Read that 1 frame.
3. Final sanity check: read the first significant-change frame and the last-stable frame (2 frames total).

**Expected token usage:** 2-4 frame reads × ~2500 tokens = ~10K tokens (vs 260K for reading all frames).

**Build the idle animation timeline from all 3 tiers:**

```json
{
  "phase": "idle",
  "type": "splash | auto-timer | css-animation | video-autoplay",
  "frameRange": [1, 30],
  "description": "Built from: Tier 1 AE spike at frames 8-25, Tier 2 DOM shows .introHome opacity 0→1 at t=800ms, .gsap:text yPercent 100→0 at t=1200ms",
  "duration_ms": 3000,
  "domChanges": [
    { "selector": ".introHome", "property": "opacity", "from": "0", "to": "1", "at_ms": 800 },
    { "selector": ".gsap\\:text lines", "property": "transform", "from": "translateY(100%)", "to": "translateY(0%)", "at_ms": 1200 }
  ]
}
```

### Splash vs. actual site boundary

Find the frame where the site's actual content first appears:
- Splash = overlay/loading screen that covers the entire viewport
- Content = first frame where hero/navigation is visible underneath

**Use Tier 2 DOM log to find this boundary:** when the splash/overlay element's `opacity` drops to 0 or `display` changes to `none`, that's the boundary frame. Cross-reference with Tier 1 AE to confirm the frame number.

```bash
# Check overlay elements AFTER the splash has played (not during)
agent-browser --session <project> wait 8000
agent-browser --session <project> eval "(() => {
  const overlays = document.querySelectorAll('[class*=load], [class*=intro], [class*=splash], [class*=preload], [class*=curtain], [class*=overlay]');
  return JSON.stringify(Array.from(overlays).map(el => ({
    cls: el.className?.toString?.().slice(0, 60),
    display: getComputedStyle(el).display,
    opacity: getComputedStyle(el).opacity,
    visibility: getComputedStyle(el).visibility,
    zIndex: getComputedStyle(el).zIndex,
    position: getComputedStyle(el).position,
  })));
})()"
```

### Splash end-state verification (MANDATORY if splash detected)

After implementation, verify the splash sequence **terminates cleanly**:

1. Record impl splash (same as Phase A — open page, record 10s)
2. Extract frames at 10fps
3. **AE diff ref vs impl at matching timestamps** (zero tokens):

```bash
# Compare ref and impl frames at key timestamps
# Use the frame numbers identified by Tier 1 AE analysis
for FRAME in <last-splash-frame> <first-content-frame> <settled-frame>; do
  AE=$(compare -metric AE \
    tmp/ref/<component>/idle-frames/frame-${FRAME}.png \
    tmp/ref/<component>/idle-frames-impl/frame-${FRAME}.png \
    /dev/null 2>&1)
  echo "Frame $FRAME: AE=$AE"
done
# AE=0 → pass. AE>0 → check DOM log first, then Read 1 frame only if DOM can't explain it.
```

| Timestamp | Check | Verification method | Pass? |
|-----------|-------|---------------------|-------|
| Last splash frame | All animated elements fully hidden/removed | AE diff + DOM `opacity`/`display` check | ? |
| First content frame | Main content visible, no splash remnants | AE diff + DOM element count | ? |
| +2s after splash | No leftover elements | DOM query for splash nodes | ? |

**Common splash failures:**
- Animated elements (3D objects, logos) remain visible after splash ends — missing opacity/visibility transition to terminal state
- Overlay z-index not reset — splash overlay blocks interaction after animation completes
- Content scale/opacity animation not triggered — content stays at initial state (e.g., `scale(0.8)`)

```bash
# Post-splash DOM check — run after splash should have completed
agent-browser --session <project> wait 8000
agent-browser --session <project> eval "(() => {
  const remnants = document.querySelectorAll('[class*=intro], [class*=splash], [class*=overlay], [class*=preload]');
  return JSON.stringify(Array.from(remnants).map(el => ({
    cls: el.className?.toString?.().slice(0, 40),
    display: getComputedStyle(el).display,
    opacity: getComputedStyle(el).opacity,
    pointerEvents: getComputedStyle(el).pointerEvents,
    note: el.offsetHeight > 0 ? 'STILL VISIBLE — should be removed or hidden' : 'hidden/removed ✓',
  })));
})()"
```

---

## Phase B: Scroll Capture (Scroll-driven motion)

**Purpose:** Find everything that moves DURING scroll.

### B-1: Record full scroll video at native framerate

```bash
# Scroll to top first
agent-browser --session <project> eval "(() => {
  const lenis = document.querySelector('[class*=lenis], [class*=scroll]');
  if (lenis && lenis.scrollTop !== undefined) lenis.scrollTop = 0;
  window.scrollTo(0, 0);
})()"
agent-browser --session <project> wait 2000

# Start recording
agent-browser --session <project> record start tmp/ref/<component>/scroll-capture.webm

# Wait for recording to start
agent-browser --session <project> wait 500

# Scroll through entire page — SLOW and CONSISTENT
# Method 1: Lenis/custom scroll container
agent-browser --session <project> eval "(() => {
  const lenis = document.querySelector('[class*=lenis], [class*=scroll]');
  const container = lenis || document.documentElement;
  const maxScroll = container.scrollHeight - window.innerHeight;
  let pos = 0;
  const speed = 80; // px per step
  const interval = 50; // ms between steps
  const step = () => {
    pos = Math.min(pos + speed, maxScroll);
    if (lenis) lenis.scrollTop = pos;
    else window.scrollTo(0, pos);
    if (pos < maxScroll) setTimeout(step, interval);
  };
  step();
  return 'scrolling ' + maxScroll + 'px';
})()"

# Wait for scroll to complete (pageHeight / speed * interval + buffer)
agent-browser --session <project> wait 12000

agent-browser --session <project> wait 1000
agent-browser --session <project> record stop

# Extract at 60fps for precise motion analysis
ffmpeg -i tmp/ref/<component>/scroll-capture.webm -vf fps=60 tmp/ref/<component>/scroll-frames/frame-%06d.png -y
```

### B-2: Track elements across scroll positions

> **Token rule for scroll frames:** The 60fps extraction above is for AE/SSIM automated comparison (Phase 4 verification), NOT for LLM reading. Do NOT Read scroll frames with the LLM to "see what changed." Instead, use the DOM tracking eval below — it gives you exact property values at each scroll position without any vision tokens.

**Instead of just comparing frames visually**, track specific elements' computed styles at multiple scroll positions. This catches parallax, scale, sticky, clip-path that screenshots miss.

```bash
agent-browser --session <project> eval "(() => {
  const lenis = document.querySelector('[class*=lenis], [class*=scroll]');
  const container = lenis || document.documentElement;
  const maxScroll = container.scrollHeight - window.innerHeight;

  // Target elements: all sections + key visual elements
  const targets = [];
  document.querySelectorAll('section, [class*=banner], [class*=hero], [class*=asset], [class*=project], [class*=review], footer').forEach(el => {
    const cn = typeof el.className === 'string' ? el.className : '';
    targets.push({ el, selector: el.tagName.toLowerCase() + '.' + cn.trim().split(/\s+/)[0] });
  });

  // Also track images and videos inside sections
  document.querySelectorAll('section img, section video, [class*=background]').forEach(el => {
    const cn = typeof el.className === 'string' ? el.className : '';
    targets.push({ el, selector: el.tagName.toLowerCase() + '.' + cn.trim().split(/\s+/)[0] });
  });

  // Sample at 10 scroll positions (0%, 10%, 20%, ... 100%)
  const samples = [];
  const positions = Array.from({ length: 11 }, (_, i) => Math.round(maxScroll * i / 10));

  let posIndex = 0;
  const capture = () => {
    if (posIndex >= positions.length) {
      window.__elementTracking = samples;
      return;
    }

    const scrollPos = positions[posIndex];
    if (lenis) lenis.scrollTop = scrollPos;
    else window.scrollTo(0, scrollPos);

    // Wait a tick for paint, then measure
    requestAnimationFrame(() => {
      const snapshot = { scrollY: scrollPos, scrollPct: Math.round(scrollPos / maxScroll * 100), elements: [] };

      targets.forEach(({ el, selector }) => {
        const s = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        snapshot.elements.push({
          selector,
          inViewport: r.bottom > 0 && r.top < window.innerHeight,
          top: Math.round(r.top),
          transform: s.transform !== 'none' ? s.transform.slice(0, 80) : null,
          opacity: s.opacity !== '1' ? s.opacity : null,
          scale: s.scale !== 'none' ? s.scale : null,
          clipPath: s.clipPath !== 'none' ? s.clipPath : null,
          position: s.position === 'sticky' || s.position === 'fixed' ? s.position : null,
        });
      });

      samples.push(snapshot);
      posIndex++;
      setTimeout(capture, 200);
    });
  };

  capture();
  return 'tracking ' + targets.length + ' elements across ' + positions.length + ' scroll positions';
})()"

# Wait for tracking to complete
agent-browser --session <project> wait 5000

# Retrieve results
agent-browser --session <project> eval "(() => JSON.stringify(window.__elementTracking || [], null, 2))()"
```

**Save to** `tmp/ref/<component>/element-tracking.json`

### B-3: Classify detected animations

For each element in `element-tracking.json`, compare values across scroll positions:

| Pattern | Classification | What to look for |
|---------|---------------|-----------------|
| `transform` changes with scroll | **parallax** | translateY value changes but at different rate than scrollY |
| `transform: scale()` changes | **scroll-zoom** | scale increases as element enters viewport |
| `opacity` goes 0→1 | **scroll-reveal** | Element fades in when entering viewport |
| `clipPath` changes | **clip-reveal** | Clipping area expands on scroll |
| `position: sticky` at some positions | **sticky/pinned** | Element stays fixed during scroll range |
| `top` stays constant while scroll moves | **fixed-in-section** | Image fixed while container scrolls past |
| Element visible but `transform` has large translateY | **parallax offset** | Image moves slower than container |

---

## Phase C: Per-Element Deep Capture

For each animation detected in Phase B, capture a **targeted video** of just that element:

```bash
# 1. Scroll to just before the element triggers
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  const rect = el.getBoundingClientRect();
  const scrollPos = rect.top + window.scrollY - window.innerHeight;
  window.scrollTo(0, Math.max(0, scrollPos));
})()"
agent-browser --session <project> wait 500

# 2. Record while scrolling through the element
agent-browser --session <project> record start tmp/ref/<component>/element-<name>.webm

agent-browser --session <project> eval "(() => {
  // Scroll slowly through the element's range
  const el = document.querySelector('<selector>');
  const rect = el.getBoundingClientRect();
  const startPos = window.scrollY;
  const endPos = startPos + rect.height + window.innerHeight;
  let pos = startPos;
  const step = () => {
    pos += 40;
    window.scrollTo(0, pos);
    if (pos < endPos) setTimeout(step, 50);
  };
  step();
})()"

agent-browser --session <project> wait 5000
agent-browser --session <project> record stop

# 3. Extract at 60fps
ffmpeg -i tmp/ref/<component>/element-<name>.webm -vf fps=60 tmp/ref/<component>/element-<name>-frames/frame-%06d.png -y
```

### Extract exact values at key frames

For each element video, extract computed style at: before trigger, 25%, 50%, 75%, after trigger.

```bash
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  const s = getComputedStyle(el);
  return JSON.stringify({
    transform: s.transform,
    opacity: s.opacity,
    scale: s.scale,
    clipPath: s.clipPath,
    position: s.position,
    top: s.top,
    width: s.width,
    height: s.height,
  });
})()"
```

---

## Save: animations-detected.json

Combine all findings from Phase A, B, C:

```json
{
  "splash": {
    "type": "splash",
    "phases": [
      { "name": "loading", "duration_ms": 600, "description": "White screen + spinner/loader" },
      { "name": "logo", "duration_ms": 1400, "description": "Brand logo + wordmark reveal" },
      { "name": "reveal", "duration_ms": 800, "description": "Overlay fades out, main content visible" }
    ],
    "totalDuration_ms": 2800
  },
  "autoTimers": [
    { "selector": ".carousel", "interval_ms": 4000, "type": "slideshow" }
  ],
  "scrollAnimations": [
    {
      "selector": "section.product-collection .block",
      "type": "parallax",
      "scrollRange": { "start": 1200, "end": 2800 },
      "properties": {
        "translateY": { "from": 200, "to": 0 }
      },
      "ease": "linear (scroll-driven)"
    },
    {
      "selector": "section.banner-showroom .background",
      "type": "scroll-zoom",
      "scrollRange": { "start": 3000, "end": 4200 },
      "properties": {
        "scale": { "from": 0.55, "to": 1.0 }
      }
    },
    {
      "selector": ".border",
      "type": "scroll-reveal",
      "scrollRange": { "start": 3500, "end": 4000 },
      "properties": {
        "scaleX": { "from": 0, "to": 1 }
      }
    },
    {
      "selector": ".column",
      "type": "scroll-converge",
      "scrollRange": { "start": 3500, "end": 4500 },
      "properties": {
        "translateX": { "from": "±58.5px", "to": "0px" }
      }
    },
    {
      "selector": "section.assets-duo img",
      "type": "parallax",
      "scrollRange": { "start": 5000, "end": 6000 },
      "properties": {
        "translateY": { "speeds": ["slow", "fast"], "delta": [80, 120] }
      }
    }
  ],
  "textReveals": [
    {
      "selector": ".text-cta p",
      "type": "word-stagger",
      "triggerType": "intersection",
      "params": { "stagger_ms": 30, "duration_ms": 800, "ease": "power3.inOut", "translateY": "110%" }
    }
  ]
}
```

---

## Integration with Step 7 (Generation)

When generating components, for each animation in `animations-detected.json`:

| Animation type | Implementation |
|---------------|----------------|
| `splash` | `IntroOverlay` component with phased setTimeout |
| `auto-timer` | `setInterval` + state cycling |
| `parallax` | `useScroll` + `useTransform` from @beyond/react |
| `scroll-zoom` | `useScroll` + `useTransform` for scale |
| `scroll-reveal` | `ScrollReveal` or `LineReveal` component |
| `scroll-converge` | `useScroll` + `useTransform` for translateX |
| `word-stagger` | `WordReveal` component |
| `sticky/pinned` | CSS `position: sticky` with appropriate `top` value |
| `clip-reveal` | `useScroll` + `useTransform` for clipPath |

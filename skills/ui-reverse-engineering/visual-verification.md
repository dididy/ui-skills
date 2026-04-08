# Visual Verification — Step 8 + 9

> **Security note:** Screenshots and DOM snapshots may contain sensitive data visible on the page (auth tokens in DOM attributes, form inputs, user info). Clean up `tmp/ref/` after extraction: `rm -rf tmp/ref/<component>`

**Reference recordings are captured ONCE from the original site. Never re-visit the original site after initial capture.**

## Dependencies

```bash
ffmpeg -version   # required for frame extraction
# macOS: brew install ffmpeg
```

## Three Mandatory Captures

Every component verification requires these **three distinct captures**, both from the original site (Phase A) and from the implementation (Phase B):

| # | Capture Type | What | Why |
|---|---|---|---|
| **C1** | Full-page static screenshots | Screenshot at each scroll position (top, 25%, 50%, 75%, 100%) | Catches layout, spacing, color, typography mismatches |
| **C2** | Full-page scroll video | Continuous video recording while scrolling top to bottom | Catches scroll-triggered animations, parallax, sticky elements, reveal transitions |
| **C3** | Transition/interaction captures | Per-region capture by triggerType: clip screenshots (css-hover, js-class, intersection) or video (scroll-driven, mousemove, auto-timer) | Catches timing, easing, state changes, interaction behavior |

**All three are mandatory. C1 alone (static screenshots) is NOT sufficient.** C2 catches what C1 misses (scroll-triggered motion), and C3 catches what C2 misses (hover/click/scroll interactions).

## Frame Extraction: 60 fps

Video captures (scroll-driven, mousemove, auto-timer) are extracted at **60 fps** for frame-by-frame comparison.

```bash
# 60 fps extraction — use for VIDEO captures only
ffmpeg -i <input>.webm -vf fps=60 <output-dir>/frame-%06d.png -y
```

> **Why 60 fps:** At 2 fps, a 500ms transition produces 1 frame. At 60 fps, it produces 30 frames. Transition bugs (flicker, wrong easing, layout jump) are only visible at full frame rate.
> **css-hover / js-class / intersection:** no frame extraction needed — these use clip screenshots directly.

## Shared scroll sequence (use identically in Phase A and B)

```bash
agent-browser eval "
(() => {
  const h = document.body.scrollHeight;
  let pos = 0;
  const step = () => {
    pos += 120;
    window.scrollTo(0, pos);
    if (pos < h) setTimeout(step, 80);
  };
  step();
})()"
agent-browser wait 4000
```

## Phase A: Record Reference (ONCE)

### A-C1: Full-page static screenshots

```bash
mkdir -p tmp/ref/<component>/frames/{ref,impl,diff}
mkdir -p tmp/ref/<component>/static/{ref,impl,diff}
mkdir -p tmp/ref/<component>/transitions/{ref,impl}
mkdir -p tmp/ref/<component>/responsive

agent-browser open https://target-site.com
agent-browser set viewport 1440 900

# Static screenshots at each scroll position
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/ref/top.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight * 0.25))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/ref/25pct.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight * 0.5))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/ref/50pct.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight * 0.75))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/ref/75pct.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/ref/bottom.png
```

### A-C2: Full-page scroll video

```bash
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser wait 500
agent-browser record start tmp/ref/<component>/ref-scroll.webm

# Static pause at top
agent-browser wait 1000

# Scroll (use shared sequence above)

agent-browser wait 1000
agent-browser record stop

# Extract at 60 fps
ffmpeg -i tmp/ref/<component>/ref-scroll.webm -vf fps=60 tmp/ref/<component>/frames/ref/scroll-%06d.png -y
```

### A-C3: Transition/interaction captures (deferred to Step 5b)

> **This step requires `interactions-detected.json` from Step 5.** Execute A-C3 after Step 5 in Phase 2 (referenced as Step 5b in SKILL.md), not during the initial Phase A pass.

**Capture method depends on `triggerType`:**

| triggerType | Method |
|---|---|
| `css-hover`, `js-class` | eval + clip screenshot (idle + active states) |
| `intersection` | eval classList.add + clip screenshot (before + after states) |
| `scroll-driven` | video recording (continuous change) |
| `mousemove` | video recording (cursor-coordinate reaction) |
| `auto-timer` | video recording (time-based loop) |

**For css-hover / js-class / intersection regions:**

```bash
# 1. Measure element rect
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"
agent-browser wait 500

# 2. idle state
agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<component>/transitions/ref/<name>-idle.png

# 3. active state
# css-hover: CDP hover
agent-browser hover <selector>
# js-class: classList.add
# agent-browser eval "document.querySelector('<sel>').classList.add('<cls>')"
# intersection: classList.add('in-view')
agent-browser wait <transitionDuration + 100>
agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<component>/transitions/ref/<name>-active.png
```

**For scroll-driven / mousemove / auto-timer regions (video):**

```bash
# Example: carousel with auto-timer
agent-browser eval "(() => { document.querySelector('<carousel-selector>').scrollIntoView({ block: 'center' }); })()"
agent-browser wait 500
agent-browser record start tmp/ref/<component>/ref-transition-carousel.webm

agent-browser wait 12000  # 2 full cycles

agent-browser record stop

# Extract at 60 fps
ffmpeg -i tmp/ref/<component>/ref-transition-carousel.webm -vf fps=60 tmp/ref/<component>/transitions/ref/carousel-%06d.png -y
```

### A-R: Responsive screenshots

**Handled by `responsive-detection.md` Steps 4-D and A-R.** If Step 4 was already executed in Phase 2, ref screenshots already exist — do not re-capture. If Phase 1 runs before Phase 2 (as in the SKILL.md flow), defer A-R until Step 4 is complete.

### Phase A Gate

```
□ static/ref/ has 5 screenshots (top, 25%, 50%, 75%, bottom)
□ Spot-check: Read top.png ONCE — confirm it's the actual site (not blank, not bot-detection page). Do not re-read for comparison.
□ ref-scroll.webm exists and has frames extracted to frames/ref/ at 60 fps
□ C3 (transitions/) — deferred until Step 5b (needs interaction data from Step 5)
□ responsive/ — deferred until Step 4 (responsive-detection.md)
```

**If C1 or C2 is missing → go back and capture. C3 and responsive are captured later in Phase 2.**

---

## Phase B: Record Implementation (per iteration)

Execute the **identical** three captures on `localhost:<port>`:

### B-C1: Full-page static screenshots

```bash
agent-browser open http://localhost:<port>
agent-browser set viewport 1440 900

agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/impl/top.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight * 0.25))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/impl/25pct.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight * 0.5))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/impl/50pct.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight * 0.75))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/impl/75pct.png

agent-browser eval "(() => window.scrollTo(0, document.body.scrollHeight))()"
agent-browser wait 500
agent-browser screenshot tmp/ref/<component>/static/impl/bottom.png
```

### B-C2: Full-page scroll video

```bash
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser wait 500
agent-browser record start tmp/ref/<component>/impl-scroll.webm

agent-browser wait 1000

# Scroll (use shared sequence — identical to Phase A)

agent-browser wait 1000
agent-browser record stop

ffmpeg -i tmp/ref/<component>/impl-scroll.webm -vf fps=60 tmp/ref/<component>/frames/impl/scroll-%06d.png -y
```

### B-C3: Transition/interaction captures

**Same method as A-C3 — identical triggerType classification, identical selectors and timing.**

**For css-hover / js-class / intersection regions (clip screenshot):**

```bash
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"
agent-browser wait 500

agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<component>/transitions/impl/<name>-idle.png

agent-browser hover <selector>  # or classList.add for js-class/intersection
agent-browser wait <transitionDuration + 100>
agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<component>/transitions/impl/<name>-active.png
```

**For scroll-driven / mousemove / auto-timer regions (video — identical to A-C3):**

```bash
agent-browser eval "(() => { document.querySelector('<carousel-selector>').scrollIntoView({ block: 'center' }); })()"
agent-browser wait 500
agent-browser record start tmp/ref/<component>/impl-transition-carousel.webm

agent-browser wait 12000

agent-browser record stop

ffmpeg -i tmp/ref/<component>/impl-transition-carousel.webm -vf fps=60 tmp/ref/<component>/transitions/impl/carousel-%06d.png -y
```

### B-R: Responsive screenshots

**Read `responsive-detection.md`, execute the B-R section.** Captures impl screenshots at the same detected breakpoints used in A-R.

---

## Phase C: Compare & Fix

**Token budget rule:** All image comparisons use AE/SSIM (zero tokens). Only read images with the Read tool for: (1) one-time spot-checks (Phase A gate), (2) diagnosing AE/SSIM failures via diff images, (3) the final VLM sanity check (1 pair). Never read ref+impl image pairs side-by-side for comparison — use pixel diff instead.

**Three comparison tables — one per capture type.** All three must pass.

### C1: Static screenshot comparison (AE diff)

Run pixel diff for each position — do NOT read images with the Read tool for comparison (wastes tokens).

```bash
for POS in top 25pct 50pct 75pct bottom; do
  compare -metric AE \
    tmp/ref/<component>/static/ref/${POS}.png \
    tmp/ref/<component>/static/impl/${POS}.png \
    tmp/ref/<component>/static/diff/${POS}.png 2>&1
done
# → 0 = pass. Non-zero = fail (diff image shows mismatched pixels)
```

Only read the diff image (`static/diff/<pos>.png`) with the Read tool when AE > 0 and you need to diagnose which region differs.

| Position | AE | Status |
|----------|----|--------|
| Top      |    | ✅/❌  |
| 25%      |    | ✅/❌  |
| 50%      |    | ✅/❌  |
| 75%      |    | ✅/❌  |
| Bottom   |    | ✅/❌  |

**Responsive comparison:** see `responsive-detection.md` C-R table (covers all detected breakpoints).

### C2: Scroll video frame comparison (SSIM batch)

Compare all extracted 60fps frames using ffmpeg SSIM — no LLM image reading. Only inspect frames that fail SSIM threshold.

```bash
mkdir -p tmp/ref/<component>/frames/diff

# Batch SSIM comparison of all frame pairs
FRAME_COUNT=$(ls tmp/ref/<component>/frames/ref/scroll-*.png | wc -l)
for i in $(seq -f "%06g" 1 $FRAME_COUNT); do
  SSIM=$(ffmpeg -i tmp/ref/<component>/frames/ref/scroll-${i}.png \
                -i tmp/ref/<component>/frames/impl/scroll-${i}.png \
                -lavfi "ssim" -f null - 2>&1 | grep -oP 'All:\K[0-9.]+')
  if (( $(echo "$SSIM < 0.995" | bc -l) )); then
    echo "FAIL frame ${i}: SSIM=${SSIM}"
    compare -metric AE \
      tmp/ref/<component>/frames/ref/scroll-${i}.png \
      tmp/ref/<component>/frames/impl/scroll-${i}.png \
      tmp/ref/<component>/frames/diff/scroll-${i}.png 2>/dev/null
  fi
done
# → Only read diff images for FAIL frames when diagnosing root cause
```

If no frames fail → C2 passes. If frames fail, read **only the diff images** of failing frames to diagnose the mismatch region.

### C3: Transition comparison

**For css-hover / js-class / intersection — clip screenshot diff:**

```
| Region   | State  | Ref                                   | Impl                                   | Match? | Issue |
|----------|--------|---------------------------------------|----------------------------------------|--------|-------|
| <name>   | idle   | transitions/ref/<name>-idle.png       | transitions/impl/<name>-idle.png       | ✅/❌  |       |
| <name>   | active | transitions/ref/<name>-active.png     | transitions/impl/<name>-active.png     | ✅/❌  |       |
```

Run pixel diff for each pair:
```bash
compare -metric AE tmp/ref/<component>/transitions/ref/<name>-idle.png tmp/ref/<component>/transitions/impl/<name>-idle.png /dev/null 2>&1
compare -metric AE tmp/ref/<component>/transitions/ref/<name>-active.png tmp/ref/<component>/transitions/impl/<name>-active.png /dev/null 2>&1
# → 0 = pass
```

**For scroll-driven / mousemove / auto-timer — frame comparison (SSIM batch):**

Same SSIM batch approach as C2 — compare all extracted frames automatically, only inspect failures.

```bash
# Per-transition SSIM batch (example: carousel)
FRAME_COUNT=$(ls tmp/ref/<component>/transitions/ref/carousel-*.png | wc -l)
for i in $(seq -f "%06g" 1 $FRAME_COUNT); do
  SSIM=$(ffmpeg -i tmp/ref/<component>/transitions/ref/carousel-${i}.png \
                -i tmp/ref/<component>/transitions/impl/carousel-${i}.png \
                -lavfi "ssim" -f null - 2>&1 | grep -oP 'All:\K[0-9.]+')
  if (( $(echo "$SSIM < 0.995" | bc -l) )); then
    echo "FAIL frame ${i}: SSIM=${SSIM}"
  fi
done
# → Only read diff images for FAIL frames when diagnosing root cause
```

### Fix protocol

**For each ❌:**
1. **Run 10-point score first** (see `style-audit.md` scoring section). This tells you what category to fix.
2. Write one sentence naming the root cause before touching any code: _"The gap exists because X"_
3. Check if the property belongs to a design bundle (`design-bundles.json`). If yes, verify all sibling properties in the bundle (see `component-generation.md` covariance rules).
4. If you cannot name the cause, run `agent-browser eval` to inspect computed styles at that moment
5. Targeted fix → re-run scoring → re-run the specific capture that failed → compare
6. **Score regression → rollback:** If the 10-point score drops after a fix, `git checkout` the component and try a different approach
7. If the same fix has been tried twice without result, the diagnosis was wrong — re-instrument

### Phase D: Pixel-Perfect Visual Gate (MANDATORY)

> **Read and execute `../pixel-perfect-diff.md` Phase 1 (Visual Gate) AND Phase 2 (Numerical Diagnosis) before declaring any section done — both always run.**

C1–C3 use pixel-level diff (AE/SSIM) to catch visual mismatches. Phase D goes deeper with per-element clip screenshots and getComputedStyle to catch sub-pixel numerical differences that full-page AE/SSIM may miss:
- `font-size: 15px` vs `16px` (passes full-page SSIM, caught by per-element clip + getComputedStyle)
- `letter-spacing` micro-differences
- `font-weight: 400` vs `600` at small sizes

Phase D runs **in parallel with C1** (both use the static loaded page). Phase 1 and Phase 2 always both run.

**For each major section of the component:**

1. Follow `../pixel-perfect-diff.md` Phase 1 — clip screenshot per element per state (idle / active / before / mid / after — by triggerType), AE/SSIM diff
2. Follow `../pixel-perfect-diff.md` Phase 2 — getComputedStyle all properties, build diff table
3. Produce `tmp/ref/<component>/pixel-perfect-diff.json`

Phase D gate:
```
□ pixel-perfect-diff.json exists for this component
□ all elements Visual Gate status = "pass" (idle / active / before / mid / after — by triggerType)
□ mismatches = 0
```

### Completion gate

```
COMPLETION = 10-point score ≥ 9
             AND C1 all ✅ AND C2 all ✅ AND C3 all ✅
             AND Phase D Visual Gate all pass
             AND Phase D mismatches = 0

Fix iteration loop:
  1. Run 10-point score (style-audit.md)
  2. Score < previous iteration? → rollback, retry differently
  3. Score < 9? → fix lowest category → re-run from 1
  4. Score ≥ 9 → run Phase D pixel-perfect-diff
  5. Phase D fail? → fix specific element → re-run from 1
  6. Phase D pass → run VLM sanity check
  7. VLM flags issue? → fix → re-run from 1
  8. VLM clean → DONE

Any single ❌ = NOT DONE.
Max 3 full iterations before escalating to user with score breakdown.
```

### Phase E: VLM Sanity Check (final, 1 pair only)

After all automated gates pass, read **one pair** of screenshots (ref top + impl top) with the Read tool to catch issues that pixel diff and getComputedStyle cannot:
- Missing visual elements that exist outside the measured selectors
- z-index stacking order problems
- Overflow clipping that hides content
- Overall "feel" mismatch (wrong visual weight, wrong hierarchy)

```bash
# Read exactly 2 images — one ref, one impl
# Read tmp/ref/<component>/static/ref/top.png
# Read tmp/ref/<component>/static/impl/top.png
```

If everything looks correct → DONE.
If an issue is visible → name it, fix it, re-run from Step 1 of the fix iteration loop.

> **Token budget:** This is the ONLY place in the verification pipeline where ref+impl images are read side-by-side by the LLM. All other comparisons use AE/SSIM. One pair = ~4000 tokens. Do not read additional pairs unless the first pair reveals an issue in a specific scroll region.

**Before declaring done — entry point check:**
```bash
# Confirm global CSS is actually imported in the app entry file
grep -r "import.*\.css\|import.*global" src/main.tsx src/index.tsx src/pages/_app.tsx src/app/layout.tsx 2>/dev/null \
  || grep -r "stylesheet" index.html 2>/dev/null \
  || echo "WARNING: no CSS entry point import found — check your framework's entry file"
```
Missing this is a silent failure: styles exist but have no effect.

**Post-completion cleanup:**
```bash
# Remove extracted data — may contain sensitive info from the target site
rm -rf tmp/ref/<component>
```
> Screenshots, DOM snapshots, and video frames may contain auth tokens, PII, or session data visible on the target page. Always clean up after verification is complete.

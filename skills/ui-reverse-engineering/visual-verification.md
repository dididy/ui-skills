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
mkdir -p tmp/ref/<component>/frames/{ref,impl}
mkdir -p tmp/ref/<component>/static/{ref,impl}
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
□ Spot-check: Read top.png — is it the actual site? (not blank, not bot-detection page)
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

**Three comparison tables — one per capture type.** All three must pass.

### C1: Static screenshot comparison

Read ref and impl screenshots side-by-side using the Read tool.

| Position | Ref                      | Impl                      | Match? | Issue |
|----------|--------------------------|---------------------------|--------|-------|
| Top      | static/ref/top.png       | static/impl/top.png       | ✅/❌  |       |
| 25%      | static/ref/25pct.png     | static/impl/25pct.png     | ✅/❌  |       |
| 50%      | static/ref/50pct.png     | static/impl/50pct.png     | ✅/❌  |       |
| 75%      | static/ref/75pct.png     | static/impl/75pct.png     | ✅/❌  |       |
| Bottom   | static/ref/bottom.png    | static/impl/bottom.png    | ✅/❌  |       |

**Responsive comparison:** see `responsive-detection.md` C-R table (covers all detected breakpoints).

### C2: Scroll video frame comparison (60 fps)

Compare ref and impl scroll frames at matching frame numbers. Check at minimum every 60th frame (= 1 second intervals) plus any frame where a scroll-triggered transition is visible in the ref.

```
| Frame  | Moment                      | Ref                          | Impl                          | Match? | Issue |
|--------|-----------------------------|------------------------------|-------------------------------|--------|-------|
| 000001 | Top (static)                | frames/ref/scroll-000001.png | frames/impl/scroll-000001.png | ✅/❌  |       |
| 000060 | ~1s into scroll             | frames/ref/scroll-000060.png | frames/impl/scroll-000060.png | ✅/❌  |       |
| 000XXX | Scroll-reveal trigger point | ...                          | ...                           | ✅/❌  |       |
| ...    | ...                         | ...                          | ...                           | ✅/❌  |       |
```

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

**For scroll-driven / mousemove / auto-timer — frame comparison (60 fps):**

Compare at minimum: start frame, every 6th frame during transition (= 100ms at 60fps), end frame.

```
| Frame  | Moment                  | Ref                                | Impl                                | Match? | Issue |
|--------|-------------------------|------------------------------------|-------------------------------------|--------|-------|
| 000001 | Before interaction      | transitions/ref/carousel-000001    | transitions/impl/carousel-000001    | ✅/❌  |       |
| 000006 | +100ms                  | transitions/ref/carousel-000006    | transitions/impl/carousel-000006    | ✅/❌  |       |
| 000012 | +200ms                  | transitions/ref/carousel-000012    | transitions/impl/carousel-000012    | ✅/❌  |       |
| ...    | (every 6 frames)        | ...                                | ...                                 | ✅/❌  |       |
| 000030 | Transition end (~500ms) | transitions/ref/carousel-000030    | transitions/impl/carousel-000030    | ✅/❌  |       |
| 000360 | Auto-timer fires        | transitions/ref/carousel-000360    | transitions/impl/carousel-000360    | ✅/❌  |       |
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

C1–C3 catches layout and motion mismatches but cannot catch subtle numerical differences:
- `font-size: 16px` vs `24px` (looks similar in full-page screenshot)
- `font-weight: 400` vs `600` (subtle at small sizes)
- `padding: 2rem` vs `3rem` (hard to judge without a ruler)

Phase D runs **in parallel with C1** (both use the static loaded page). Phase 1 and Phase 2 always both run — Phase 2 catches sub-pixel mismatches (`font-size: 15px vs 16px`, `letter-spacing` micro-differences) that pass the Visual Gate.

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
  6. Phase D pass → DONE

Any single ❌ = NOT DONE.
Max 3 full iterations before escalating to user with score breakdown.
```

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

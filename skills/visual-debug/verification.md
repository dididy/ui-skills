# Visual Verification — Full Procedure

> Part of the `visual-debug` skill. Can be invoked standalone or as Step 8+9 of `ui-reverse-engineering`.
>
> **Quick comparison?** Use `batch-scroll.sh` + `batch-compare.sh` from the parent SKILL.md instead. This document is the **full multi-phase verification procedure** with capture, comparison, self-healing, and completion gate.

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

## Frame Extraction: 60 fps (MANDATORY — DO NOT CHANGE)

> **THIS IS A HARD REQUIREMENT. DO NOT reduce to 10fps, 30fps, or any other value.**
> **DO NOT skip frame extraction. DO NOT use screenshots as a substitute.**
> **Every video capture MUST be extracted at exactly 60fps.**

Video captures are extracted at **60 fps** for AE diff curve analysis and frame-by-frame comparison.

```bash
# 60 fps extraction — MANDATORY for ALL video captures. DO NOT change this value.
ffmpeg -i <input>.webm -vf fps=60 <output-dir>/frame-%06d.png -y
```

> **Why 60 fps:** AE diff at 60fps gives 16.7ms resolution — sufficient to detect easing curves,
> holds, and transition boundaries. AE diff costs zero tokens (pure CLI).
> Disk usage: ~300KB/frame × 60fps × duration. Clean up frames after analysis.
>
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

## Content-Anchored Screenshot Alignment (MANDATORY)

**Never compare screenshots by raw y-coordinate.** Original and implementation have different total page heights (pinned/sticky sections, different padding, etc.). A screenshot at y=5000 in the original shows completely different content than y=5000 in the implementation.

**Instead, use text anchors:**

1. Identify a unique heading or text string visible in the section (e.g., "Clothing to claim every shred")
2. In BOTH original and implementation, find that text element and scroll it to the same viewport position
3. Screenshot at that aligned position

```bash
# Content-anchored scroll helper
ANCHOR="Clothing to claim"
agent-browser eval "(() => {
  for (const h of document.querySelectorAll('h1,h2,h3')) {
    if (h.textContent.includes('${ANCHOR}')) {
      window.scrollTo(0, h.getBoundingClientRect().top + window.scrollY - 350);
      return 'found';
    }
  }
  return 'not found';
})()"
```

**For pinned/scroll-triggered sections** (e.g., GSAP ScrollTrigger pin):

The same section may appear at different scroll positions because the pin extends the scroll range. Compare at **scroll progress**, not scroll position:

```bash
# Read ScrollTrigger progress in original
agent-browser eval "(() => {
  if (typeof ScrollTrigger !== 'undefined') {
    const triggers = ScrollTrigger.getAll();
    return JSON.stringify(triggers.map(t => ({
      trigger: t.trigger?.className?.substring(0,40),
      progress: t.progress,
      start: t.start, end: t.end
    })));
  }
  return 'no ScrollTrigger';
})()"

# In implementation, scroll to equivalent progress
# progress = (scrollY - sectionTop) / (sectionHeight - viewportHeight)
```

## Anti-pattern: "looks close enough" (HARD RULE)

> **See "No Judgment — Data Only" in `ui-reverse-engineering/SKILL.md` for the full table of judgment traps.**

**Never declare a section "done" or "almost matching" based on your own visual judgment.** Your judgment is unreliable — you consistently overestimate similarity. Instead:

1. Run `auto-verify.sh` — it runs layout-health-check, batch-scroll+AE comparison, and post-implement gate automatically
2. Run `computed-diff.sh` on key elements (font-size, padding, margin, color)
3. If ANY AE > 500 or ANY computed value differs by more than 1px → it's NOT done
4. Only `auto-verify.sh exit 0` + user confirmation = done

**Phrases that indicate this anti-pattern (ALL are FORBIDDEN):**
- "almost matches" / "very close" / "close enough"
- "nearly identical to the original"
- "structure is almost the same"
- "this FAIL is just a content difference"
- "this is a structural difference, not visual"
- "the remaining differences are minor"

**Replace with:** Specific `auto-verify.sh` exit code, AE numbers, or `computed-diff.sh` output.

---

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

> **Use the `visual-debug` skill for automated comparison.** Instead of manually running `compare` commands below, invoke `/visual-debug` which provides `batch-scroll.sh` (captures both sites at identical scroll positions) and `batch-compare.sh` (outputs a markdown pass/fail table). This is faster and uses zero vision tokens.

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

### Phase D0: Layout Health Check (MANDATORY before Phase D)

Before pixel-level comparison, verify the implementation's layout structure matches the original:

```bash
bash "$SCRIPTS_DIR/layout-health-check.sh" <session> <orig-url> <impl-url> tmp/ref/<component>
```

**Gate:** Exit code 0 (no critical issues). If exit 1:
- Fix height mismatches first (wrong padding, missing sections, collapsed elements)
- Re-run layout health check
- Only proceed to Phase D when D0 passes

**Why D0 before D1/D2:** Pixel comparison on structurally different pages produces noise, not signal. A page with 3000px of blank space will FAIL every position comparison, but the root cause is a layout bug, not a style bug. D0 catches this in 2 seconds.

### Phase D: Pixel-Perfect Visual Gate (MANDATORY)

> **Read and execute the Phase D section below Phase 1 (Visual Gate) AND Phase 2 (Numerical Diagnosis) before declaring any section done — both always run.**

C1–C3 use pixel-level diff (AE/SSIM) to catch visual mismatches. Phase D goes deeper with per-element clip screenshots and getComputedStyle to catch sub-pixel numerical differences that full-page AE/SSIM may miss:
- `font-size: 15px` vs `16px` (passes full-page SSIM, caught by per-element clip + getComputedStyle)
- `letter-spacing` micro-differences
- `font-weight: 400` vs `600` at small sizes

Phase D runs **in parallel with C1** (both use the static loaded page). Phase D1 and Phase D2 always both run.

**For each major section of the component:**

1. Follow the Phase D section below Phase 1 — clip screenshot per element per state (idle / active / before / mid / after — by triggerType; for click-toggle: idle + active; for click-cycle: state-0, state-1, ..., state-N), AE/SSIM diff
2. Follow the Phase D section below Phase 2 — getComputedStyle all properties, build diff table
3. Produce `tmp/ref/<component>/pixel-perfect-diff.json`

Phase D gate:
```
□ pixel-perfect-diff.json exists for this component
□ all elements Visual Gate status = "pass" (idle / active / before / mid / after — by triggerType)
□ mismatches = 0
```

### Phase H: Self-Healing Loop

> Runs automatically when Phase D fails. Classifies defects, applies targeted fixes, re-verifies. Max 3 iterations.

**Prerequisite:** `compare-sections.sh` must have been run with JSON output (v0.2.0+). The defect list is in `<dir>/clips/comparison-output.json` under the `defects` array.

#### H1: Defect Classification

Read `comparison-output.json` and sort defects:

```bash
python3 -c "
import json
data = json.load(open('<dir>/clips/comparison-output.json'))
defects = data.get('defects', [])
severity_order = {'CRITICAL': 0, 'MAJOR': 1, 'MINOR': 2}
defects.sort(key=lambda d: (severity_order.get(d.get('severity','MINOR'), 3), d.get('category','')))
for d in defects:
    print(f\"{d.get('severity','?'):8s} {d.get('category','?'):12s} {d.get('selector','?')} → {d.get('property','?')}: expected={d.get('expected','?')} actual={d.get('actual','?')}\")
"
```

**Priority order:** CRITICAL → MAJOR → MINOR. Within same severity: LAYOUT → TYPOGRAPHY → COLOR → ANIMATION → CONTENT.

#### H2: Targeted Fix

For each defect, in priority order:

1. **Locate the file.** The `selector` maps to a component — find it via grep:
   ```bash
   grep -rn "<selector-class>" src/components/
   ```

2. **Determine the fix.** Based on category:
   - **LAYOUT:** Adjust spacing/sizing. Use extracted `expected` value directly.
   - **TYPOGRAPHY:** Fix font-size/weight/family. Use exact computed value, not Tailwind approximation.
   - **COLOR:** Fix color/background values. Match extracted hex/rgb exactly.
   - **ANIMATION:** Re-read `transition-spec.json` for correct timing/easing values.
   - **CONTENT:** Check for missing text/images. Re-extract from DOM if needed.

3. **Apply minimal Edit.** Change only the specific property — do not regenerate the entire component.

4. **If defect is in a design bundle** (`design-bundles.json`): check all sibling properties in the bundle. Fixing one property without its co-varying partners will create new mismatches.

#### H3: Re-verify

After fixing all defects in the current batch:

1. Re-capture implementation screenshots (Phase B)
2. Re-run `compare-sections.sh` for fresh `comparison-output.json`
3. Re-run Phase D (Visual Gate + Numerical Diagnosis)

**Outcomes:**
- All pass → exit healing loop, proceed to completion gate
- New defects found → loop back to H1 (iteration count += 1)
- Same defects persist after fix → diagnosis was wrong. Re-instrument:
  ```bash
  agent-browser eval "(() => {
    const el = document.querySelector('<selector>');
    const s = getComputedStyle(el);
    return JSON.stringify({ /* all relevant properties */ });
  })()"
  ```
  Compare with extracted values to find the actual discrepancy.

**Max iterations: 3.** After 3 healing iterations, escalate to user with:
- Remaining defect list (category + severity + selector + property + expected vs actual)
- What was attempted in each iteration
- Suggested manual investigation areas

#### Healing Loop Integration

The completion gate (below) is unchanged. Phase H runs BEFORE the gate check:

```
Phase D fails → Phase H (up to 3 iterations) → Phase D passes → completion gate
Phase H exhausted → escalate with defect report
```

---

### Completion gate

> **Phase H runs first.** If Phase D fails, the healing loop (Phase H above) runs automatically before checking the completion gate. The gate below is checked only after Phase H passes or exhausts its iterations.

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

### Phase E: LLM Structural Review (MANDATORY, ALL positions)

After AE + DSSIM complete, the LLM reads **every position's** ref+impl pair. This is NOT a sanity check — it is a **mandatory verification axis** that catches what AE and DSSIM cannot.

**Why this changed from "1 pair only":** We discovered that AE can report PASS on completely wrong content (scientific notation parsing bug: `1.27e+06` → `1`), and DSSIM can report PASS when content is missing on a same-color background (`empty yellow bg` vs `yellow bg + card` → DSSIM=0.19). Neither automated metric reliably answers "is this the same page?"

#### Procedure

For each scroll position (0%, 10%, ..., 100%):

```
Read tmp/ref/<component>/static/ref/<pos>pct.png
Read tmp/ref/<component>/static/impl/<pos>pct.png
```

Judge each pair:

| Verdict | Meaning | Action |
|---------|---------|--------|
| **PASS** | Same sections, same content, same visual weight | None |
| **PARTIAL** | Same structure, minor differences (Lottie frame, icon style, animation state) | Document the difference, acceptable if known |
| **FAIL** | Different content, missing sections, wrong layout | Must fix before declaring done |

#### Output format

```markdown
| Position | AE | DSSIM | LLM | Verdict | Issue |
|----------|-----|-------|-----|---------|-------|
| 0% | 418K ❌ | 0.38 ✅ | ✅ | PARTIAL | Lottie frame diff |
| 10% | 1.2M ❌ | 0.19 ✅ | ❌ | FAIL | ServiceCards not visible — scroll trigger not fired |
| ... | | | | | |
```

**Final gate:** Every position must be PASS or PARTIAL (with documented reason). Any FAIL blocks completion.

#### What LLM catches that metrics miss

- Empty background where content should be (DSSIM=0.19 on same-color bg)
- Wrong program/carousel state (AE=1 between two captures of the same wrong page)
- Missing sections that don't affect pixel count (small element on large background)
- Structural ordering errors (sections in wrong sequence but similar colors)

> **Token budget:** ~4000 tokens per pair × 11 positions = ~44K tokens. This is expensive but mandatory. The cost of shipping a wrong implementation and re-doing the entire pipeline is higher.

**Before declaring done — entry point check:**
```bash
# Confirm global CSS is actually imported in the app entry file
grep -r "import.*\.css\|import.*global" src/main.tsx src/index.tsx src/pages/_app.tsx src/app/layout.tsx 2>/dev/null \
  || grep -r "stylesheet" index.html 2>/dev/null \
  || echo "WARNING: no CSS entry point import found — check your framework's entry file"
```
Missing this is a silent failure: styles exist but have no effect.

---

## Phase D: Pixel-Perfect Diff

> **This step separates "looks similar" from "pixel-perfect".** Both phases always run.

### Phase D1: Visual Gate

1. **Select elements**: layout containers, typography carriers, visually distinct elements from each section
2. **Define states per triggerType**: static → idle; css-hover/js-class → idle + active; intersection → before + after; scroll-driven → before + mid + after
3. **Measure rect** via `getBoundingClientRect()` on both ref and impl, activating each state first (hover, classList.add, scrollTo)
4. **Clip screenshot** each element per state: `agent-browser screenshot --clip <x>,<y>,<w>,<h> <path>`
5. **Diff**: `compare -metric AE ref.png impl.png diff.png` (ImageMagick) or `ffmpeg -lavfi "ssim"` — AE = 0 or SSIM >= 0.995 = PASS

### Phase D2: Numerical Diagnosis

> Always runs regardless of Phase D1 result — catches sub-pixel mismatches AE/SSIM misses.

Measure `getComputedStyle` on both ref and impl for all Phase D1 elements:

**Properties**: `fontSize`, `fontWeight`, `lineHeight`, `letterSpacing`, `fontFamily`, `color`, `backgroundColor`, `padding*`, `margin*`, `gap`, `width`, `height`, `display`, `flexDirection`, `alignItems`, `justifyContent`, `gridTemplateColumns`, `borderRadius`, `boxShadow`, `opacity`, `transform`

Build diff table: any property mismatch > 2px = FAIL. Fix and re-run both phases.

### Gate

```
Phase D1 Visual Gate: all elements all states = PASS
Phase D2 Numerical: mismatches = 0
Both must pass. "Approximately identical" = FAIL.
```

---

**Post-completion cleanup:**
```bash
# Remove extracted data — may contain sensitive info from the target site
rm -rf tmp/ref/<component>
```
> Screenshots, DOM snapshots, and video frames may contain auth tokens, PII, or session data visible on the target page. Always clean up after verification is complete.

## Section-Aligned Comparison (MANDATORY)

**After content-anchored comparison, verify scroll position alignment:**

Extract section top offsets from BOTH original and implementation:

```bash
# Original
agent-browser --session <ref-session> eval "(() => {
  const main = document.querySelector('main, .page-main, [role=main]') || document.body;
  return JSON.stringify([...main.children].filter(c => c.offsetHeight > 0 && c.tagName !== 'SCRIPT').map(s => ({
    class: (typeof s.className === 'string' ? s.className : '').slice(0, 60),
    top: Math.round(s.getBoundingClientRect().top + scrollY),
    height: Math.round(s.offsetHeight),
  })));
})()"

# Implementation
agent-browser --session <impl-session> eval "(() => {
  const main = document.querySelector('main, .page-main, [role=main]') || document.body;
  return JSON.stringify([...main.children].filter(c => c.offsetHeight > 0 && c.tagName !== 'SCRIPT').map(s => ({
    class: (typeof s.className === 'string' ? s.className : '').slice(0, 60),
    top: Math.round(s.getBoundingClientRect().top + scrollY),
    height: Math.round(s.offsetHeight),
  })));
})()"
```

Compare the results. If any section's top offset differs by more than 50px, there's a spacing bug. Common causes:
- Missing gap/padding on a flex container
- Section heights not matching (fixed vs auto)
- Missing spacer elements

## Original SVG/Asset Extraction (MANDATORY)

**Never create placeholder SVGs when the original has custom artwork.** If a logo, monogram, icon, or decorative element uses a custom SVG:

1. Extract the exact SVG from the DOM:
```bash
agent-browser eval "(() => {
  const svg = document.querySelector('<selector>');
  return svg ? svg.outerHTML : 'not found';
})()"
```

2. Save the SVG as a component or public asset
3. Use `fill="currentColor"` for theming

**WHY:** In a real session, a footer logo (sparkles + bird + OR monogram = one SVG with viewBox 0 0 460 171) was replaced with a placeholder ellipse+text. It took 3 iterations to discover and extract the actual SVG. Always extract originals first.

## Tailwind Arbitrary Value Compatibility Check

Before using arbitrary values like `px-[19px]`, verify they work in the target Tailwind version:

```bash
# Quick test after first component renders
agent-browser eval "(() => {
  const el = document.querySelector('[class*=\"px-[\"]');
  return el ? getComputedStyle(el).paddingLeft : 'no match or not rendered';
})()"
```

If the value is `0px`, Tailwind is not processing the arbitrary value. Use inline `style` props instead:
```tsx
style={{ paddingLeft: 19, paddingRight: 19 }}
```

**WHY:** Tailwind v4 with certain configs silently ignores arbitrary px values. This caused all padding to be 0px across an entire site, requiring a global find-and-replace to inline styles.

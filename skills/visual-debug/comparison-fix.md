# Phase C: Compare & Fix

> Split from `verification.md` for readability. This phase runs after Phase A (reference capture) and Phase B (implementation capture).
> **After this phase:** proceed to Phase D (Pixel-Perfect Diff) in `verification.md`.


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

## Element-Scope Verification (transition extraction)

> For single-element animation verification. Runs after ui-reverse-engineering Step T3 (implement). Frames live in `tmp/ref/<effect-name>/frames/{ref,impl}/`.

### Frame Comparison — element scope (AE)

Cropped to element bounds. Compare using AE diff — do not read image pairs with the LLM.

```bash
FRAME_COUNT=$(ls tmp/ref/<effect-name>/frames/ref/frame-*.png | wc -l)
for i in $(seq -f "%02g" 1 $FRAME_COUNT); do
  AE=$(compare -metric AE \
    tmp/ref/<effect-name>/frames/ref/frame-${i}.png \
    tmp/ref/<effect-name>/frames/impl/frame-${i}.png \
    tmp/ref/<effect-name>/frames/diff/frame-${i}.png 2>&1)
  if [ "$AE" -gt 0 ]; then
    echo "FAIL frame ${i}: AE=${AE}"
  fi
done
```

For each FAIL frame: read the diff image to identify which region differs → targeted fix → re-capture impl only → compare.

### Frame Comparison — fullpage scope (SSIM batch)

Full-page screenshot comparison across the entire transition window.

```bash
FRAME_COUNT=$(ls tmp/ref/<effect-name>/frames/ref/frame-*.png | wc -l)
for i in $(seq -f "%02g" 1 $FRAME_COUNT); do
  SSIM=$(ffmpeg -i tmp/ref/<effect-name>/frames/ref/frame-${i}.png \
                -i tmp/ref/<effect-name>/frames/impl/frame-${i}.png \
                -lavfi "ssim" -f null - 2>&1 | grep -oP 'All:\K[0-9.]+')
  if (( $(echo "$SSIM < 0.995" | bc -l) )); then
    echo "FAIL frame ${i}: SSIM=${SSIM}"
  fi
done
```

**Automated failure detection:**
- SSIM < 0.5 on any frame where ref has content → likely blank/loading/white impl frame
- SSIM drop > 0.3 between consecutive impl frames where ref is smooth → likely layout jump

### Bug Diagnosis Protocol

When a visual bug is reported (white flash, wrong timing, layout jump):

**Before writing any fix:**
1. Name the root cause in one sentence: _"The white flash happens because X"_
2. If you cannot name it, instrument:
   ```bash
   agent-browser eval "
   (() => {
     const panes = document.querySelectorAll('[class*=pane], [class*=slot]');
     return JSON.stringify([...panes].map(el => {
       const s = getComputedStyle(el);
       return { cls: (typeof el.className === 'string' ? el.className : el.className?.baseVal || ''), opacity: s.opacity, visibility: s.visibility, zIndex: s.zIndex, position: s.position, height: el.offsetHeight };
     }));
   })()"
   ```
3. Only after root cause is confirmed → write the fix
4. After fix → re-capture impl frames → verify the specific bug frame is gone

**Do not iterate on the same approach more than twice.** If two fixes in the same direction don't work, the diagnosis was wrong — re-instrument and re-diagnose.

### Pixel-Perfect Static State Diff (element scope)

Frame comparison verifies timing and motion but CANNOT verify numerical correctness of resting states (font-size, weight, color, spacing, border-radius).

Run Phase D (above) for the element's resting states. States by triggerType:

| triggerType | States |
|---|---|
| css-hover / js-class | `idle`, `active` |
| intersection | `before`, `after` |
| scroll-driven | `before` (trigger_y − 50), `mid` (mid_y), `after` (settled_y + 50) |

Save clips under `tmp/ref/<effect-name>/frames/{ref,impl}/<state>.png`.

Gate: `pixel-perfect-diff.json` exists with all elements `"status": "pass"` AND `mismatches = 0`.

### Bundle-Based Verification (untriggerable animations)

Use `bundle-verification.md` (in ui-reverse-engineering) when:
- Animation auto-starts (carousel, page-load, timer-based)
- T=0 synchronization between ref and impl is impossible

Gate: `bundle-verification.json` all checks `"match": true`.

### Transition-RE "Is This Done?" Checklist

- [ ] `measurements.json` saved (11-point multi-property measurement)
- [ ] Non-linear curves / phase boundaries identified
- [ ] `extracted.json` saved
- [ ] Implementation uses measured values (NOT guessed)
- [ ] **Triggerable:** impl frames captured, comparison all ✅, no white flash/blank
- [ ] **Untriggerable:** `transition-spec.json` + `bundle-verification.json` all match + resting screenshot OK
- [ ] **`pixel-perfect-diff.json`** all pass AND mismatches = 0
- [ ] Entry points verified (CSS imports loaded)
- [ ] **Scroll transitions:** reverse direction verified
- [ ] **Post-implementation full-page capture** (top → bottom → top, SSIM batch)

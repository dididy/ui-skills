---
name: visual-debug
description: Compare original site vs implementation with automated AE/SSIM diff — near-zero vision tokens. Triggers on "it looks different", "doesn't match", "compare with original", "what's wrong". Uses auto-diagnose to find mismatched elements from diff images without vision tokens. Falls back to reading diff images only when auto-diagnose finds nothing.
metadata:
  filePattern:
    - "**/tmp/ref/**/static/**"
    - "**/tmp/ref/**/frames/**"
    - "**/tmp/ref/**/diff/**"
    - "**/side-by-side/**"
  bashPattern:
    - "compare.*metric"
    - "ffmpeg.*ssim"
    - "ae-compare"
    - "batch-compare"
    - "batch-scroll"
    - "computed-diff"
    - "auto-diagnose"
  priority: 90
---

# Visual Debug

Automated visual comparison — original vs implementation. **Zero vision tokens** via AE/SSIM CLI tools.

## When to use

- After implementing a section, before declaring "done"
- When user says "it's different", "doesn't match"
- During ui-reverse-engineering Phase C
- **Instead of** `Read`-ing screenshots for comparison

**HARD RULE:** Never `Read` ref/impl images for comparison. For FAIL positions, use `auto-diagnose.sh` first (zero vision tokens). Only `Read` diff images as fallback if auto-diagnose finds nothing. Exception: Phase E reads ref+impl pairs.

## Token rule

Pipe large `eval` output to a file, then `Read` only what you need:
```bash
agent-browser --session <s> eval "<script>" > tmp/ref/<name>.json
```
Never let large JSON print to stdout — it wastes tokens.

## Dependencies

```bash
brew install imagemagick ffmpeg dssim
which agent-browser
```

## Scripts

```bash
SCRIPTS_DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/visual-debug/scripts}"
# -L follows symlinks (~/.claude/skills/visual-debug is often a symlink to a real path).
SCRIPTS_DIR="${SCRIPTS_DIR:-$(find -L ~/.claude/skills -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)}"
```

| Script | Purpose |
|---|---|
| `computed-diff.sh <session> <orig> <impl> <sel...>` | **Run first** — getComputedStyle comparison. Catches fontWeight/display/height root causes before pixel diff |
| `batch-scroll.sh <orig> <impl> <session> [dir]` | Captures both at 0–100% scroll positions |
| `ae-compare.sh <ref.png> <impl.png> [diff.png]` | AE comparison → `AE=<n> STATUS=PASS|FAIL` |
| `batch-compare.sh <dir> [threshold]` | Compare all pairs. Supports dynamic thresholds |
| `dssim-compare.sh <dir> [threshold]` | Structural similarity (catches what AE misses) |
| `layout-diff.sh <session> <orig> <impl>` | Section bounding box comparison |
| `section-compare.sh <orig> <impl> <session> <dir>` | **Section-level comparison** — crops each section, AE + structure diff. Catches SVG-as-text, layout mismatches. **`<dir>` is required** — pass `"$(pwd)/tmp/ref/<component>"` |
| `auto-diagnose.sh <session> <orig> <impl> <diff.png>` | **Auto-find mismatched elements** from AE diff image → elementFromPoint → computed-diff with severity |
| `layout-health-check.sh <session> <orig> <impl> <dir>` | Section height/total height structural check before pixel diff |
| `stray-absolute-check.sh <session> <impl-url> [w] [h]` | **Catches the "footer disappeared" bug class** — flags `position: absolute` elements with no positioned ancestor (offset resolves against `<body>`). Single URL, no ref needed. See `diagnosis.md` → Root Cause H. |
| `reveal-trigger-check.sh <session> <impl-url> [w] [h]` | **Catches the "stuck reveal" bug class** — enumerates initially-hidden elements (opacity 0 / non-identity transform), scrolls each into view, fails any whose style never advances. Reports parent-chain with `overflow: hidden` ancestors so the IO+overflow:hidden bug class (took 12 iterations to find on 375.studio) is named on first run. See `ui-reverse-engineering/transition-implementation.md` → IntersectionObserver placement for masked reveals. |
| `transition-spec-coverage.sh <component-dir> <impl-src-dir>` | **Static gate: every spec entry has an impl artifact.** Parses `transition-spec.json`, greps the impl source for each entry's id / selector / type-derived hooks (RevealRise, useScrollTrigger, useScroll, etc.), FAILs if any entry has zero hits. Catches the "hover transitions matched while intersection entries were never wired" failure class. |
| `transition-compare.sh <orig> <impl> <session> [dir]` | **Transition comparison** — idle/hover screenshots + computedStyle + timing diff per element |
| `tree-diff.sh <session> <orig> <impl> [dir]` | **Exhaustive per-element CSS diff** — walks every visible impl element (≥ MIN_SIZE px), pairs with ref via `elementFromPoint`, runs computed-style diff per pair. Catches mismatches AE misses (wrong font that renders identically, same-box different-style). |
| `layout-tree-diff.sh <session> <orig> <impl> [dir]` | **Geometry diff via signature-based pairing** — pairs impl ↔ ref by stable signature (text + tag + class hash + size class), reports geometry deltas (top/left/w/h) regardless of where elements moved. Catches what tree-diff misses (right element, wrong position). |
| `hover-tree-diff.sh <session> <orig> <impl> [dir]` | **Per-element hover/transition diff** — for each hover-capable element pair, captures idle → CDP `:hover` → settled style. Diffs timing (property/duration/easing/delay) + idle→hover delta. Catches missing hover rules, wrong easing, different deltas. |
| `keyframes-diff.sh <session> <orig> <impl> [dir]` | **`@keyframes` declaration diff** — extracts all keyframe rules from both pages, reports keyframes only on one side and same-name rules with different steps. Catches missing entrance animations, wrong timing curves baked into keyframes. |

**Reference selectors:** `common-selectors.md` — ready-to-use selector sets (typography, CSS reset canaries, Tailwind preflight issues, Naver.com specific, general e-commerce)

## Pick the right diff tool

Five computed-style/geometry diff tools exist; each answers a different question. Run the targeted tool first, then escalate if the answer is "nothing wrong" but AE still fails.

| Question | Tool | Scope | Cost |
|---|---|---|---|
| Are CSS resets / structural canaries OK? (entry-point sanity) | `computed-diff.sh` | Selector list you provide | Cheap — first call always |
| Did every transition-spec entry get wired into impl code at all? | `transition-spec-coverage.sh` | All entries in `transition-spec.json` vs grep of impl source | Cheap — first call when verifying transitions |
| Hidden-init elements (opacity 0, transform offset) — do they ever trigger? | `reveal-trigger-check.sh` | Every initially-hidden element on the impl page | Cheap — second call when verifying transitions |
| AE failed; which element on the diff image is wrong? | `auto-diagnose.sh` | Hotspots in the AE diff image | Cheap — second call |
| AE keeps failing but auto-diagnose found nothing — wrong style on visually-similar render | `tree-diff.sh` | Every visible element (≥ MIN_SIZE), paired by `elementFromPoint` | Med |
| Element is in the right place style-wise but at the wrong position | `layout-tree-diff.sh` | Every element, paired by signature (text+tag+class hash+size class) — robust to reflow | Med |
| Hover / transition feels off (wrong easing, missing rule, different delta) | `hover-tree-diff.sh` | Every hover-capable pair, idle → CDP `:hover` → settled | High — many state captures |
| Entrance / scroll animation timing is subtly off | `keyframes-diff.sh` | All `@keyframes` declarations from both pages | Low — declarations only |

**Heuristics:**
- `tree-diff` and `layout-tree-diff` are siblings, not redundant — first asks "is the style right on this element?", second asks "is this element in the right place?". Run `tree-diff` first; if it's clean and AE still fails, run `layout-tree-diff`.
- `transition-compare.sh` is the predefined-set hover gate (Step 8c of `ui-reverse-engineering`); `hover-tree-diff.sh` is the exhaustive escalation. Use `hover-tree-diff` only when `transition-compare` reports PASS but the impl still feels wrong.
- `transition-spec-coverage.sh` and `reveal-trigger-check.sh` are the **first two** transition gates, not escalations — run them before `transition-compare.sh`. Coverage catches "entry never wired", reveal-trigger catches "wired but stuck". `transition-compare.sh` only verifies idle→hover diffs, so it can pass while intersection/scroll-driven entries are completely broken.
- Don't run all five by default — they are slower and noisier than the standard `auto-diagnose` workflow.

## Workflow

### Step 0: structural checks FIRST (before AE)

**Always run structural checks before pixel comparison.** AE catches *that* something is wrong; structural checks catch *why* — and fix the root cause immediately without hunting through diff images.

```bash
SCRIPTS="$SCRIPTS_DIR"

# 0a. Stray absolute positioning — catches the "footer disappeared" bug class.
#     Run on EVERY viewport you care about; the bug often only manifests on shorter pages.
bash "$SCRIPTS/stray-absolute-check.sh" <session>-stray <impl> 375 812
bash "$SCRIPTS/stray-absolute-check.sh" <session>-stray <impl> 1280 800

# 0a-bis. Stuck reveals — catches the IO+overflow:hidden bug class. Mandatory if
#         the spec has any `intersection`/`inview` trigger entries.
bash "$SCRIPTS/reveal-trigger-check.sh" <session>-reveal <impl> 1280 800

# 0a-ter. Spec coverage — every transition-spec entry must have an impl artifact.
#         Mandatory before per-trigger verification (transition-compare etc.) so
#         entirely-missing entries are caught BEFORE you waste a hover sweep.
bash "$SCRIPTS/transition-spec-coverage.sh" tmp/ref/<component> <impl-src-dir>

# 0b. Broad sweep: CSS reset canaries + page structure
bash "$SCRIPTS/computed-diff.sh" <session> <orig> <impl> \
  "h1" "h2" "h3" "h4" \
  "img" "button" "a" \
  "body" "header" "main" "footer"

# 0c. Domain-specific selectors from common-selectors.md
# IGNORE_FONT_SIZE=1 to skip OS text-scaling false positives
IGNORE_FONT_SIZE=1 bash "$SCRIPTS/computed-diff.sh" <session> <orig> <impl> \
  "[class*=title]" "[class*=logo]" "[class*=search]" "[class*=nav]"
```

See `common-selectors.md` for ready-to-use selector sets by domain.

### Full-page comparison (broad sweep)
```
0. Structural    stray-absolute-check.sh + computed-diff.sh (CSS reset canaries + page structure)
1. Capture        batch-scroll.sh <orig> <impl> <session>
2. AE diff        batch-compare.sh <dir>
3. DSSIM          dssim-compare.sh <dir>
4. Diagnose       auto-diagnose.sh <session> <orig> <impl> <diff.png>
                  → auto-finds mismatched elements, runs computed-diff with severity
                  → zero vision tokens. Only Read diff image if auto-diagnose finds nothing.
5. Fix            Targeted code change (critical severity first)
6. Re-compare     Repeat 0–3
7. LLM review     Read ref+impl pairs for ALL positions (Phase E)
8. Gate           All axes PASS → DONE
```

### Section-level comparison (precise — preferred for post-gen verification)
```
0. Structural    stray-absolute-check.sh + computed-diff.sh (CSS reset + section selectors)
1. Section compare  section-compare.sh <orig> <impl> <session> "$(pwd)/tmp/ref/<component>"
   → Per-section AE + severity (critical/major/minor) + structure diff
   ⚠️  The 4th argument (ref dir path) is MANDATORY — the Stop gate reads result.txt from that
       exact path. Omitting it writes result.txt to the wrong location and the gate never clears.
2. Transition compare  transition-compare.sh <orig> <impl> <session>
   → Per-element idle/hover style + timing diff
3. Diagnose     For FAIL sections: auto-diagnose.sh <session> <orig> <impl> <diff.png>
                → auto-finds mismatched elements within that section (zero vision tokens)
4. Fix          Targeted code change (critical severity first, then major, skip minor until Phase E)
5. Re-compare   Repeat 0–2
6. Gate         All sections PASS + all transitions PASS → DONE
```

**Use section-level for ui-reverse-engineering Step 8b/8c.** Use full-page for standalone `/visual-debug` invocations.

## Escalation diagnostics (when the standard workflow misses the bug)

The standard workflow (AE + DSSIM + `auto-diagnose.sh` + `computed-diff.sh`) catches most mismatches. When AE keeps reporting failures but `auto-diagnose` returns clean — escalate to the **tree-diff family**. These walk *every* element on the page rather than a fixed selector list, so they catch what targeted diagnostics miss.

| Symptom | Escalate to | Why |
|---|---|---|
| AE fails repeatedly but `auto-diagnose` finds nothing | `tree-diff.sh` | Exhaustive computed-style diff — pairs every visible impl element with ref via `elementFromPoint`. Catches wrong fonts that render identically, same-box different-style overrides. |
| Element appears at wrong position but `tree-diff` says style matches | `layout-tree-diff.sh` | Geometry diff via signature-based pairing — pairs by stable signature (text + tag + class hash + size class), reports `top/left/w/h` deltas regardless of where the element moved on screen. |
| Hover/transition feels off but `transition-compare.sh` reports PASS | `hover-tree-diff.sh` | Per-element CDP `:hover` capture for *every* hover-capable pair (not just the predefined set). Diffs idle→hover delta + timing. |
| Entrance/scroll animation runs but timing or curve is subtly different | `keyframes-diff.sh` | Diffs `@keyframes` declarations directly. Catches missing rules, wrong steps, wrong easing baked into the keyframe definition rather than the animation shorthand. |

```bash
bash "$SCRIPTS/tree-diff.sh"        <session> <orig> <impl>   # full-element style diff
bash "$SCRIPTS/layout-tree-diff.sh" <session> <orig> <impl>   # geometry deltas
bash "$SCRIPTS/hover-tree-diff.sh"  <session> <orig> <impl>   # hover style + timing
bash "$SCRIPTS/keyframes-diff.sh"   <session> <orig> <impl>   # @keyframes declarations
```

These are diagnostic, not gate-blocking. Use them when `section-compare` / `transition-compare` keep failing without a clear cause — they produce a markdown report (severity-sorted) that names the culprit elements and properties. **Do not run all four by default** — they are slower and more expensive than the standard workflow.

## Three-axis verification (ALL required)

| Axis | Tool | Catches | Blind spot |
|------|------|---------|------------|
| **Pixel** | AE | Exact rendering diff | Lottie frame differences (false positive) |
| **Perceptual** | DSSIM | Color/tone mismatch | Missing content on same-color bg |
| **Semantic** | LLM (Phase E) | Missing sections, wrong content | Slow, costs tokens |

A position is PASS only when **all three agree** (or LLM explicitly approves a known difference).

### Phase E: LLM Review (MANDATORY)

NOTE: Quick comparison (Phases A-D) uses zero vision tokens via AE/SSIM diff. Phase E (LLM verification) is mandatory for full verification workflow and DOES use vision tokens for the final review.

After AE + DSSIM, read every position's ref+impl pair. Judge PASS / PARTIAL / FAIL. Not optional — automated metrics can silently pass wrong results. ~44K tokens.

## Thresholds

| Metric | Pass | Fail |
|---|---|---|
| AE per image | ≤ 500 | > 500 |
| SSIM per frame | ≥ 0.995 | < 0.995 |
| Computed style diff | 0 mismatches | > 0 |

AE=500 allows anti-aliasing variance. Bump to 2000 for dynamic content.

## Full verification

- `verification.md` — Phase A/B (capture) + D (pixel-perfect gate) + auxiliary checks
- `comparison-fix.md` — Phase C (AE+DSSIM comparison, computed-style diagnosis, Phase E LLM review, Phase H self-healing loop)

## Browser cleanup (MANDATORY)

**Every skill run MUST end with browser cleanup — success, failure, or interruption.**

```bash
# Always close your own session(s) by name
agent-browser --session <session-name> close
```

- Close every `--session <name>` you opened during the comparison
- Run cleanup **before returning control to the user**, even on error/early exit
- Unclosed sessions spawn Chrome Helper processes (GPU + Renderer) that persist indefinitely
- **Never use `close --all`** — other Claude sessions may have active browsers. Only close sessions you own.

## Integration

| Skill | Where |
|---|---|
| `ui-reverse-engineering` Step 8+9 | Full verification procedure |
| `ui-reverse-engineering` Step T4 | Phase D for transition resting states |
| `ui-capture` Phase 4A | Phase D before compare.html |
| Standalone | batch-scroll + batch-compare on any two URLs |

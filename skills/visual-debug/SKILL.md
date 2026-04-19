---
name: visual-debug
description: Compare original site vs implementation with automated AE/SSIM diff — zero LLM vision tokens. Triggers on "it looks different", "doesn't match", "compare with original", "what's wrong". Only reads diff images when AE/SSIM reports a failure.
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
  priority: 90
---

# Visual Debug

Automated visual comparison between original site and implementation. **Zero vision tokens** — uses AE/SSIM CLI tools, not LLM image reading.

## When to use

- After implementing a section, before declaring "done"
- When user says "it's different", "doesn't match", "still wrong"
- During ui-reverse-engineering Phase C (Compare & Fix)
- Any time you're tempted to `Read` a screenshot for visual comparison

**Standalone**: works on any two URLs — no dependency on other skills.

## Anti-patterns this replaces

| Token-wasting pattern | Replacement |
|---|---|
| `Read` screenshot → "looks close" → repeat | `ae-compare.sh` → numeric score → targeted fix |
| Side-by-side Read of ref+impl images | `batch-compare.sh` → markdown table |
| "Almost matches" / "very close" judgment | AE=0 or FAIL — no ambiguity |
| Scroll through page, screenshot each section | `batch-scroll.sh` → captures both automatically |

**HARD RULE:** never `Read` ref or impl images for AE/DSSIM comparison. Only read DIFF images for FAIL positions. **Exception: Phase E (LLM review) reads ref+impl pairs for structural judgment.**

## Dependencies

```bash
brew install imagemagick ffmpeg   # AE compare + SSIM
brew install dssim                # structural visual similarity (DSSIM)
which agent-browser               # must be installed
```

## Script path resolution

```bash
SCRIPTS_DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/visual-debug/scripts}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(find ~/.claude/skills -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)}"
```

## Scripts

| Script | Purpose |
|---|---|
| `batch-scroll.sh <orig> <impl> <session> [dir]` | Captures both URLs at 0%, 10%, ..., 100% scroll positions. Content-anchored when possible. |
| `ae-compare.sh <ref.png> <impl.png> [diff.png]` | Compare two images. Outputs `AE=<n> STATUS=<PASS\|FAIL> REGION=<top\|middle\|bottom\|full>` |
| `batch-compare.sh <dir> [threshold] [dynamic-regions.json]` | Compare all captured pairs. Supports per-position dynamic thresholds for auto-timer/Lottie sites |
| `dssim-compare.sh <dir> [threshold]` | Structural similarity comparison using DSSIM. Catches layout/composition issues AE misses |
| `layout-diff.sh <session> <orig> <impl>` | Compare section bounding boxes. Catches missing/extra sections, collapsed elements |
| `computed-diff.sh <session> <orig> <impl> <sel1> <sel2> ...` | Compare `getComputedStyle` for specified selectors. Catches sub-pixel mismatches AE misses |

## Quick workflow

```
1. Capture      bash "$SCRIPTS_DIR/batch-scroll.sh" <orig-url> <impl-url> <session>
2. AE diff      bash "$SCRIPTS_DIR/batch-compare.sh" <dir>
3. DSSIM diff   bash "$SCRIPTS_DIR/dssim-compare.sh" <dir>
4. Diagnose     Read ONLY diff images for AE FAIL positions
5. Fix          Targeted code change
6. Re-compare   Repeat steps 2-3
7. LLM review   Read ref+impl pairs for ALL positions (Phase E)
8. Gate         All three axes PASS → DONE
```

### Three-axis verification (ALL required)

Each tool catches what the others miss. **No single axis is sufficient alone.**

| Axis | Tool | Catches | Misses | Example blind spot |
|------|------|---------|--------|--------------------|
| **Pixel** | AE (batch-compare) | Exact rendering diff | Lottie frame differences (false positive) | AE=1M on identical layout with different animation frame |
| **Perceptual** | DSSIM (dssim-compare) | Color/tone mismatch | Missing content on same-color background | Empty yellow bg vs yellow bg+card → DSSIM=0.19 PASS |
| **Semantic** | LLM (Phase E) | Missing sections, wrong content, structural errors | Slow, costs tokens | Catches everything above misses |

**Why all three:**
- AE PASS + DSSIM PASS + LLM FAIL = element missing on same-color background
- AE FAIL + DSSIM PASS + LLM PASS = Lottie animation frame difference (acceptable)
- AE FAIL + DSSIM FAIL + LLM FAIL = real structural problem

A position is truly PASS only when **all three agree** (or LLM explicitly approves a known difference).

### Phase E: LLM Structural Review (MANDATORY)

After AE + DSSIM complete, read **every position's** ref+impl pair:

```
For each position (0%, 10%, ..., 100%):
  Read ref/<pos>.png and impl/<pos>.png
  Judge: PASS / PARTIAL / FAIL
  PASS    = same sections, same content, same visual weight
  PARTIAL = same structure, minor differences (Lottie frame, icon style)
  FAIL    = different content, missing sections, wrong layout
```

**This is NOT optional.** AE=1 with the scientific notation bug taught us that automated metrics can silently pass completely wrong results. LLM review is the final safety net.

Token budget: ~4000 tokens per pair × 11 positions = ~44K tokens. Expensive but necessary.

## Thresholds

| Metric | Pass | Fail |
|---|---|---|
| AE per image | ≤ 500 | > 500 |
| SSIM per frame | ≥ 0.995 | < 0.995 |
| Computed style diff | 0 mismatches | > 0 mismatches |

AE=500 allows for anti-aliasing and sub-pixel rendering. Bump to 2000 for sites with dynamic content (timestamps, random images).

## Full verification procedure

For the complete multi-phase flow (capture → comparison → pixel-perfect gate → self-healing → VLM sanity), **Read `verification.md`**. Covers:

- **Phase A/B** — reference + impl capture (C1 static, C2 scroll, C3 transitions)
- **Phase C** — comparison tables (AE + DSSIM, automated)
- **Phase D** — pixel-perfect gate (D1 Visual Gate + D2 Numerical Diagnosis — both always run)
- **Phase E** — LLM structural review (ALL positions, ref+impl pairs — MANDATORY)
- **Phase H** — self-healing loop (classify defects by category/severity, max 3 cycles)
- **Completion gate** — AE + DSSIM + LLM all agree

## Integration

This skill is the **single source of truth** for visual comparison across the suite:

| Skill | Where |
|---|---|
| `ui-reverse-engineering` Step 8+9 | Full `verification.md` procedure |
| `transition-reverse-engineering` Step 4 | Phase D for resting states (idle + active) |
| `ui-capture` Phase 4A | Phase D for pixel-perfect diff before `compare.html` |
| Standalone | `batch-scroll.sh` + `batch-compare.sh` on any two URLs |

## Example

```bash
SCRIPTS_DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/visual-debug/scripts}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(find ~/.claude/skills -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)}"

bash "$SCRIPTS_DIR/batch-scroll.sh" https://example.com http://localhost:3000 myproject tmp/ref/myproject
bash "$SCRIPTS_DIR/batch-compare.sh" tmp/ref/myproject
# | Position | AE    | Status |
# | 0%       | 0     | ✅     |
# | 10%      | 12450 | ❌     |  ← read tmp/ref/myproject/static/diff/10pct.png
# | 20%      | 0     | ✅     |

# Fix, then re-compare only the failing position:
bash "$SCRIPTS_DIR/ae-compare.sh" \
  tmp/ref/myproject/static/ref/10pct.png \
  tmp/ref/myproject/static/impl/10pct.png
```

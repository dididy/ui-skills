---
name: visual-debug
description: Use when comparing original site vs implementation to find visual differences. Replaces manual screenshot-by-screenshot comparison with automated AE/SSIM diff. Triggers on "it looks different", "doesn't match", "compare with original", "what's wrong", or any visual QA during ui-reverse-engineering. Key benefit — zero LLM vision tokens for comparison. Only reads diff images when AE/SSIM reports a failure.
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

**Standalone usage:** This skill works independently — no dependency on `ui-reverse-engineering` or other skills. Takes any two URLs (original + implementation) as input. Can be used for any visual comparison task, not just UI cloning.

## Anti-patterns this skill prevents

| Token-wasting pattern | Replacement |
|---|---|
| `Read` screenshot → "looks close" → repeat | `ae-compare.sh` → numeric score → targeted fix |
| Side-by-side Read of ref+impl images | `batch-compare.sh` → markdown table of scores |
| "Almost matches" / "very close" judgment | AE=0 or FAIL — no ambiguity |
| Scroll through page, screenshot each section | `batch-scroll.sh` → captures both sites automatically |

## Dependencies

```bash
# ImageMagick (for `compare` command)
brew install imagemagick   # macOS
# ffmpeg (for SSIM)
brew install ffmpeg
# agent-browser
which agent-browser
```

## Process

```
1. Batch capture    — batch-scroll.sh <orig-url> <impl-url> <session>
   ↓                  Captures both at identical scroll positions
2. AE diff          — batch-compare.sh <dir>
   ↓                  Outputs markdown table: position | AE | status
3. Diagnose FAILs   — Only read diff images for FAIL positions
   ↓                  Identify root cause (color, layout, missing element)
4. Fix              — Targeted code change
5. Re-compare       — batch-compare.sh again (only FAIL positions)
   ↓
6. Gate             — ALL positions AE ≤ threshold → PASS
```

**HARD RULE: Never `Read` ref or impl images for comparison. Only read DIFF images, and only for FAIL positions.**

## Scripts

### Script paths

Scripts live in `skills/visual-debug/scripts/`. Resolve via `CLAUDE_PLUGIN_ROOT`:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(find ~/.claude/skills -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)}"
```

### `batch-scroll.sh` — Capture both sites at identical scroll positions

```bash
bash "$PLUGIN_ROOT/batch-scroll.sh" <original-url> <impl-url> <session> [output-dir]
```

Captures screenshots at 0%, 10%, 20%, ..., 100% scroll positions from both URLs. Uses content-anchored alignment when possible.

### `ae-compare.sh` — Compare two images, output AE score + fail regions

```bash
bash "$PLUGIN_ROOT/ae-compare.sh" <ref.png> <impl.png> [diff-output.png]
```

Outputs: `AE=<number> STATUS=<PASS|FAIL> REGION=<top|middle|bottom|full>`

### `batch-compare.sh` — Compare all captured pairs, output markdown table

```bash
bash "$PLUGIN_ROOT/batch-compare.sh" <output-dir>
```

Outputs markdown table of all positions with AE scores. Only FAIL rows need attention.

### `computed-diff.sh` — Compare getComputedStyle values for key elements

```bash
bash "$PLUGIN_ROOT/computed-diff.sh" <session> <orig-url> <impl-url> <selector1> <selector2> ...
```

Compares CSS values between original and impl for specified selectors. Catches sub-pixel mismatches that AE misses.

## Thresholds

| Metric | Pass | Fail |
|--------|------|------|
| AE (per image) | ≤ 500 | > 500 |
| SSIM (per frame) | ≥ 0.995 | < 0.995 |
| Computed style diff | 0 mismatches | > 0 mismatches |

AE threshold of 500 allows for anti-aliasing and sub-pixel rendering differences. Increase to 2000 for sites with dynamic content (timestamps, random images).

## Full Verification Procedure

For the complete multi-phase verification (Phase A/B/C/D/H/E) with capture, self-healing loop, and completion gate:

> **Read `verification.md`** — this is the full procedure document, moved here from `ui-reverse-engineering/visual-verification.md`.

Includes: Three Mandatory Captures (C1/C2/C3), Content-Anchored Alignment, Phase D Pixel-Perfect Gate, Phase H Self-Healing Loop, Phase E VLM Sanity Check, Completion Gate.

## Integration with other skills

This skill is the **single source of truth** for all visual comparison and verification:
- **`ui-reverse-engineering` Step 8+9**: Invokes `verification.md` for full procedure
- **`transition-reverse-engineering` Step 4**: Uses Phase D (Pixel-Perfect Gate) for resting states
- **`ui-capture` Phase 4A**: Uses Phase D for pixel-perfect diff before compare.html
- **Standalone**: Use `batch-scroll.sh` + `batch-compare.sh` for quick comparison of any two URLs

## Reference Files

- **`verification.md`** — Full verification procedure (Phase A/B/C/D/H/E). Formerly `ui-reverse-engineering/visual-verification.md`.

## Example workflow

```bash
# Resolve script path
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(find ~/.claude/skills -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)}"

# 1. Capture both
bash "$PLUGIN_ROOT/batch-scroll.sh" https://example.com http://localhost:3000 myproject tmp/ref/myproject

# 2. Compare
bash "$PLUGIN_ROOT/batch-compare.sh" tmp/ref/myproject
# Output:
# | Position | AE    | Status |
# |----------|-------|--------|
# | 0%       | 0     | ✅     |
# | 10%      | 12450 | ❌     |  ← only investigate this one
# | 20%      | 0     | ✅     |

# 3. Diagnose FAIL at 10%
# Read ONLY the diff image:
# Read tmp/ref/myproject/static/diff/10pct.png

# 4. Fix the issue, re-run only the failing position
bash "$PLUGIN_ROOT/ae-compare.sh" tmp/ref/myproject/static/ref/10pct.png tmp/ref/myproject/static/impl/10pct.png

# 5. Repeat until all PASS
```

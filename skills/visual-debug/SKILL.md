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

**HARD RULE:** never `Read` ref or impl images for comparison. Only read DIFF images, and only for FAIL positions.

## Dependencies

```bash
brew install imagemagick ffmpeg   # AE compare + SSIM
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
| `batch-compare.sh <dir>` | Compare all captured pairs. Outputs markdown table — only FAIL rows need attention |
| `computed-diff.sh <session> <orig> <impl> <sel1> <sel2> ...` | Compare `getComputedStyle` for specified selectors. Catches sub-pixel mismatches AE misses |

## Quick workflow

```
1. Capture      bash "$SCRIPTS_DIR/batch-scroll.sh" <orig-url> <impl-url> <session>
2. AE diff      bash "$SCRIPTS_DIR/batch-compare.sh" <dir>
3. Diagnose     Read ONLY diff images for FAIL positions
4. Fix          Targeted code change
5. Re-compare   Same batch-compare (only FAIL positions)
6. Gate         All positions AE ≤ threshold → PASS
```

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
- **Phase C** — comparison tables (AE/SSIM, zero vision tokens)
- **Phase D** — pixel-perfect gate (D1 Visual Gate + D2 Numerical Diagnosis — both always run)
- **Phase H** — self-healing loop (classify defects by category/severity, max 3 cycles)
- **Phase E** — VLM sanity check (1 pair read after all automated gates pass)
- **Completion gate** — 10-point score ≥ 9 AND D1 all pass AND D2 mismatches = 0

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

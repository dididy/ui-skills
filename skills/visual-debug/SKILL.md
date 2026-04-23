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

Automated visual comparison — original vs implementation. **Zero vision tokens** via AE/SSIM CLI tools.

## When to use

- After implementing a section, before declaring "done"
- When user says "it's different", "doesn't match"
- During ui-reverse-engineering Phase C
- **Instead of** `Read`-ing screenshots for comparison

**HARD RULE:** Never `Read` ref/impl images for comparison. Only read DIFF images for FAIL positions. Exception: Phase E reads ref+impl pairs.

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
SCRIPTS_DIR="${SCRIPTS_DIR:-$(find ~/.claude/skills -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)}"
```

| Script | Purpose |
|---|---|
| `batch-scroll.sh <orig> <impl> <session> [dir]` | Captures both at 0–100% scroll positions |
| `ae-compare.sh <ref.png> <impl.png> [diff.png]` | AE comparison → `AE=<n> STATUS=PASS|FAIL` |
| `batch-compare.sh <dir> [threshold]` | Compare all pairs. Supports dynamic thresholds |
| `dssim-compare.sh <dir> [threshold]` | Structural similarity (catches what AE misses) |
| `layout-diff.sh <session> <orig> <impl>` | Section bounding box comparison |
| `computed-diff.sh <session> <orig> <impl> <sel...>` | getComputedStyle comparison |
| `section-compare.sh <orig> <impl> <session> [dir]` | **Section-level comparison** — crops each section, AE + structure diff. Catches SVG-as-text, layout mismatches |
| `transition-compare.sh <orig> <impl> <session> [dir]` | **Transition comparison** — idle/hover screenshots + computedStyle + timing diff per element |

## Workflow

### Full-page comparison (broad sweep)
```
1. Capture    batch-scroll.sh <orig> <impl> <session>
2. AE diff    batch-compare.sh <dir>
3. DSSIM      dssim-compare.sh <dir>
4. Diagnose   Read ONLY diff images for FAIL positions
5. Fix        Targeted code change
6. Re-compare Repeat 2–3
7. LLM review Read ref+impl pairs for ALL positions (Phase E)
8. Gate       All three axes PASS → DONE
```

### Section-level comparison (precise — preferred for post-gen verification)
```
1. Section compare  section-compare.sh <orig> <impl> <session>
   → Per-section AE + structure diff (SVG-as-text, layout type, height)
2. Transition compare  transition-compare.sh <orig> <impl> <session>
   → Per-element idle/hover style + timing diff
3. Fix          Targeted code change per failing section/element
4. Re-compare   Repeat 1–2
5. Gate         All sections PASS + all transitions PASS → DONE
```

**Use section-level for ui-reverse-engineering Step 8b/8c.** Use full-page for standalone `/visual-debug` invocations.

## Three-axis verification (ALL required)

| Axis | Tool | Catches | Blind spot |
|------|------|---------|------------|
| **Pixel** | AE | Exact rendering diff | Lottie frame differences (false positive) |
| **Perceptual** | DSSIM | Color/tone mismatch | Missing content on same-color bg |
| **Semantic** | LLM (Phase E) | Missing sections, wrong content | Slow, costs tokens |

A position is PASS only when **all three agree** (or LLM explicitly approves a known difference).

### Phase E: LLM Review (MANDATORY)

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

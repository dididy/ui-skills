# ui-skills — Clone any website into React + Tailwind

A [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) plugin that reverse-engineers any live website into a production-ready React + Tailwind component.

- **Uses the original CSS directly** — downloads stylesheets, keeps original class names. No re-implementing from extracted values.
- **Zero vision tokens for verification** — AE/SSIM image diff instead of reading screenshots with the LLM.
- **Extracts real values from JS bundles** — GSAP timelines, Framer Motion springs, Lenis scroll params, scroll-driven keyframes. No guessing.
- **Falls back to `getComputedStyle`** when CSS is obfuscated (Tailwind, CSS-in-JS). Auto-detects site type.

> **vs. screenshot-to-code tools:** Those copy what's visible. `ui-skills` downloads the actual CSS, greps JS bundles for animation parameters, and uses the original class names — so the output matches the original's styles, transitions, and responsive behavior.

## Design principles

These are the decisions that shape how the plugin is structured. They aim to keep agent sessions focused and bounded.

- **Real values, not guesses.** Every number — font-size, easing curve, scroll offset, stagger delay — comes from `getComputedStyle`, raw CSS, or a JS bundle grep. The plugin refuses to ship approximations.
- **Zero vision tokens for comparison.** The LLM never reads reference vs implementation screenshots side-by-side. AE and SSIM CLI tools do the diff; the LLM only reads a single diff image when something fails.
- **Progressive-disclosure sub-docs.** Each SKILL.md contains only the pipeline and core rules (~6.3K tokens total across 3 skills). Detailed procedures live in 32 focused sub-docs loaded only when that step runs. Common paths stay lean; specialized paths expand on demand.
- **Single source of truth for transitions.** `transition-spec.json` is produced once from bundle analysis. Implementation reads the spec, never re-greps the bundle — avoiding wasted work and the risk of picking the wrong conditional branch.
- **Automation over introspection.** Script-driven gates (`validate-gate.sh`, `run-pipeline.sh`, `auto-verify.sh`) decide whether a step is complete. Agents don't self-certify "looks good enough."
- **No judgment, data only.** Every decision must be backed by extracted data, captured screenshots, or script output. "Probably", "close enough", and "just a content difference" are forbidden — each has a documented failure case.

## Skills

| Skill | Purpose |
|---|---|
| **`ui-reverse-engineering`** | Full pipeline: URL → DOM/CSS/JS extraction → React + Tailwind component. Includes Webflow IX2 detection (Step W), transition coverage audit (Step 6d), WAAPI/canvas/WebGL/Three.js extraction. |
| **`ui-capture`** | Baseline screenshots + transition capture + comparison page. Auto-detects custom scroll (Lenis, Locomotive). Classifies effects by trigger type. |
| **`visual-debug`** | All visual comparison in one skill. Quick mode (AE/SSIM batch), full verification (Phase A→E with self-healing loop), section-level comparison, and transition behavior diff. |

## Requirements

```bash
npm i -g agent-browser       # browser automation for AI agents (github.com/anthropics/agent-browser)
brew install imagemagick     # AE pixel comparison (apt: imagemagick, choco: imagemagick)
brew install dssim           # structural visual similarity (cargo install dssim)
brew install ffmpeg          # video capture + frame extraction (apt: ffmpeg, choco: ffmpeg)

# verify
agent-browser --version
magick --version             # ImageMagick 7 (or: convert --version for v6)
dssim --help
ffmpeg -version
```

## Installation

```bash
# npx skills (recommended)
npx skills add dididy/ui-skills

# Or clone directly
mkdir -p ~/.claude/skills
git clone https://github.com/dididy/ui-skills.git ~/.claude/skills/ui-skills
```

### Pipeline hooks (automatic)

Hooks register automatically via `hooks/hooks.json` on plugin install — no manual setup needed.

| Hook | Event | Purpose |
|------|-------|---------|
| `ui-re-pre-generate-check.sh` | `PreToolUse` (Write/Edit) | Blocks component writes until extraction completes |
| `ui-re-post-verify-check.sh` | `PostToolUse` (Bash) | Warns on completion signals if verification hasn't run |
| `ui-re-section-compare-gate.sh` | `Stop` | Blocks finishing if `section-compare.sh` hasn't passed |

Hooks skip automatically when no `tmp/ref/` directory exists, so they won't interfere with non-ui-re projects.

---

## Quickstart

After installing (see [Installation](#installation)), give Claude a URL and a target:

```
Clone the hero section from https://stripe.com/payments into React + Tailwind. Output to ./out/
```

The pipeline runs automatically. `scripts/run-pipeline.sh` detects the current phase and prints the next action; you don't invoke phases manually.

**What happens:**

1. Reference capture → `tmp/ref/payments-hero/{full,desktop,tablet,mobile}.png` + scroll video
2. DOM/CSS/JS extraction → `tmp/ref/payments-hero/{structure,styles,assets}.json` + `transition-spec.json`
3. Component generation → `./out/PaymentsHero.tsx` (CSS-first, original class names)
4. Visual verification → `scripts/auto-verify.sh` → D0 layout health + AE/SSIM diff

If verification fails, the pipeline iterates up to 3 rounds (Phase H self-healing loop) before asking for human review.

**Hooks are already registered** on install via `hooks/hooks.json` — they block premature writes and warn on unverified completion signals automatically.

---

## `ui-reverse-engineering` — Website → React Component

Turns any live website into a React + Tailwind component. For URL input, extracts real values. Screenshot and video inputs fall back to Claude Vision approximation.

**Usage:**

```
Clone this site: https://example.com
Copy the hero section from https://example.com
Replicate this UI (attach screenshot)
Turn this screen recording into a working component
```

**Pipeline:**

```
0.   Load existing analysis     — re-invoked? load transition-spec.json + bundle-map.json
R.   Capture reference         — static screenshots + scroll video (60 fps)
1.   Open & snapshot           — DOM tree, full-page screenshot. Session reuse for splash sites
W.   Webflow IX2 detection     — MANDATORY if <meta name=generator> contains "Webflow".
                                 Extract hide-rule selector list + IX2 timeline JSON.
                                 ⛔ gate: webflow-detection.json, webflow-hide-rule.json, webflow-ix2.json
2.   Extract structure         — HTML hierarchy, component boundaries, hidden elements
2.5  Extract assets            — CSS files, fonts, images, SVGs, videos, head metadata
2.5b SVG-as-text detection     — find headings rendered as SVG <path> not fonts → svg-text-elements.json
2.6p Dual-snapshot (splash)    — pre/post-splash DOM state → dom-state-diff.json.
                                 Auto-detects splash completion (no hardcoded waits)
2.6  Catalog init styles       — GSAP-baked inline styles, state coupling
3.   Extract styles            — computed CSS, design tokens, em-conversion (viewport-scaled).
                                 Merge runtime-injected transitions from dual-snapshot diff
4.   Detect responsive         — 2-pass viewport sweep + multi-viewport sizing → sizing-expressions.json
5.   Detect interactions       — hover/click/scroll. Extract ALL :hover CSS from live stylesheets
                                 (incl. inline <style>). data-text attribute scan. Hover video recording.
                                 JS hover timing + child cascade
5b.  Capture C3 (deferred)     — interaction/transition videos using selectors from Step 5
5c.  Bundle analysis           — ALL loaded chunks, scroll engine, hover event listeners. ⛔ gate: bundle
5d.  Transition spec           — transition-spec.json + bundle-map.json. ⛔ gate: spec
5e.  Capture verification      — record original, extract frames, verify spec spatial values
6.   Detect animations         — Phase A idle / B scroll (wheel events for smooth scroll) / C per-element
6b.  Assemble extracted.json
6c.  Pre-generation audit      — 6-stage design audit
6d.  Transition coverage       — multi-position scroll measurement → transition-coverage.json.
                                 Samples 10 scroll positions, decodes every transform matrix,
                                 classifies scroll-driven vs enter-reveal vs static. ⛔ gate: pre-generate
                                 (requires transition-coverage.json with animatedElements.length > 0)
7.   Generate component        — CSS-First + body scoping + CSS value diff verification.
                                 SVG-as-text verbatim, RAF parallax for smooth scroll
8.   Visual verification       — auto-verify.sh. ⛔ gate: post-implement
                                 (checks hover rule count, px fontSize leaks, scroll listeners)
8b.  Section comparison        — section-compare.sh crops each section independently → AE + structure diff.
                                 MANDATORY — replaces noisy full-page scroll comparison
8c.  Transition comparison     — transition-compare.sh idle/hover state + timing + computedStyle diff
9.   Interaction verification  — dispatch mouseenter for JS hovers, verify hover-css-rules match
```

**Automation scripts** (`scripts/`):

| Script | Purpose |
|---|---|
| `run-pipeline.sh` | State machine orchestrator — detects current phase, prints next action |
| `validate-gate.sh` | Enforces gates (bundle, spec, pre-generate, post-implement). Exits 1 on failure |
| `auto-verify.sh` | Single-command verification: D0 layout health → Phase C scroll AE → post-implement gate |
| `extract-assets.sh` | Downloads video backgrounds, Typekit fonts, CDN fonts. Extracts video poster frames |
| `extract-section-html.sh` | Per-section HTML + computed CSS + media element extraction |
| `compare-sections.sh` | 3-layer comparison: section SSIM + element RMSE + getComputedStyle diff |
| `download-chunks.sh` | Downloads ALL loaded chunks, detects animation libs, produces skeleton bundle-map.json |
| `gsap-to-css.sh` | GSAP easing → CSS cubic-bezier (lookup, full table, or bundle scan) |
| `extract-dynamic-styles.sh` | Classifies GSAP inline styles: layout (keep) vs animation (remove) |
| `freeze-animations.sh` | Freeze CSS animations, JS timers, canvas, Lottie before screenshot capture |

**Visual comparison scripts** (`skills/visual-debug/scripts/`):

| Script | Purpose |
|---|---|
| `computed-diff.sh` | **Run first** — per-selector `getComputedStyle` diff. Finds fontWeight/display/height root causes before pixel diff. `IGNORE_FONT_SIZE=1` skips fontSize/lineHeight/width/height (use on macOS with 105% system text scaling) |
| `layout-health-check.sh` | D0: section height/total height comparison before pixel-level diff |
| `layout-diff.sh` | Structural section bounding-box comparison between two URLs |
| `batch-compare.sh` | Batch AE comparison with dynamic-region threshold support |
| `dssim-compare.sh` | Structural visual similarity (DSSIM) — catches layout issues AE misses |
| `section-compare.sh` | Section-level visual + structural comparison (lazy pre-scroll for IntersectionObserver content, text fingerprint matching, per-section AE diff, DOM structure diff) |
| `transition-compare.sh` | Hover/transition behavior comparison (idle/hover state capture, computedStyle diff, timing validation) |

All visual-debug scripts support `VIEW_W`/`VIEW_H` env vars (default 1440×900) for custom viewport sizes. All scripts that open `agent-browser` sessions have `trap EXIT` cleanup.

**Input modes:**

| Mode | Quality | When to use |
|---|---|---|
| URL (primary) | Exact values | Live site — `getComputedStyle`, real DOM, JS bundle |
| Screenshot | Approximation (Claude Vision) | Design mockup, inaccessible site |
| Video / recording | Approximation (Claude Vision) | Interactions visible in recording |
| Multiple screenshots | Approximation (Claude Vision) | Different pages or breakpoints |

---

## `ui-capture` — Visual Capture & Comparison

Captures baseline screenshots and transition videos. Standalone mode generates an overlay-based analysis report. Comparison mode generates a side-by-side page (original vs clone).

Classifies each effect by trigger type before recording — prevents blank videos from wrong activation methods.

**Usage:**

```
Capture the transitions from https://example.com
Record the hover effects on https://example.com
Compare https://example.com vs http://localhost:3000
Take a baseline of https://example.com before I start cloning
```

**Pipeline:**

```
Phase 1:  Full page capture        — section screenshots + full scroll video
                                     auto-detects custom scroll (Lenis, Locomotive)
Phase 2:  Transition detection     — classify all effects by trigger type → regions.json
Phase 2B–2E: Capture per trigger type:
  2B scroll-driven   — exploration video → clip screenshot before/mid/after
  2C css-hover       — eval + clip screenshot: idle + active
     js-class        — eval classList.add + clip screenshot: idle + active
     intersection    — eval classList.add + clip screenshot: before + after
  2D mousemove       — raster-path sweep video
  2E auto-timer      — passive recording for 2–3 cycles

local-url provided?
├── YES → Phase 3: Implementation capture
│         Phase 4A: Pixel-perfect gate (AE/SSIM + getComputedStyle)
│         Phase 4B: compare.html (side-by-side)
│         Phase 5:  User review
└── NO  → Phase R:  report.html (overlay-based analysis report)
          Phase 5:  User review
```

**Trigger type classification:**

| Trigger type | Detection | Activation |
|---|---|---|
| `css-hover` | `:hover` rule in stylesheet | eval + clip screenshot (idle + active) |
| `js-class` | JS adds/removes a class | eval classList.add + clip screenshot (idle + active) |
| `intersection` | `data-in-view`, IntersectionObserver | eval classList.add + clip screenshot (before + after) |
| `scroll-driven` | `animation-timeline: scroll()`, sticky, willChange | exploration video → clips (before/mid/after) |
| `mousemove` | `mousemove` listener, parallax/tilt/magnetic | raster-path sweep (video) |
| `auto-timer` | setInterval, CSS animation, carousel/swiper | passive wait (video) |

---

## `visual-debug` — All Visual Verification in One Skill

The single source of truth for "is it done?" — covers automated AE/SSIM diff, pixel-perfect gating, self-healing fix loops, and VLM sanity checks in one place.

**Two modes:**

- **Quick comparison** — `auto-verify.sh` runs D0 layout health check → batch-scroll capture → AE comparison → post-implement gate in one command. Zero vision tokens (AE/SSIM only, no LLM screenshot reads).
- **Full verification** — `verification.md` with Phase A/B capture → Phase C comparison → Phase D0 layout health → Phase D pixel-perfect gate → Phase H self-healing loop → Phase E LLM review. Phase E reads a single diff image when something fails, so full verification does use vision tokens.

**Phase D — pixel-perfect gate:**

```
Phase D1: Visual Gate (always runs)
  V1: Define elements + states  — idle for all; active for css-hover/js-class/intersection;
                                  before/mid/after for scroll-driven
  V2: Measure rect + activate   — scrollIntoView, eval to apply state, re-measure rect
  V3: Clip screenshot           — ref and impl, per element per state
  V4: Pixel diff                — ImageMagick AE or ffmpeg SSIM
  V5: Pass/fail                 — AE=0 or SSIM≥0.995 = pass

Phase D2: Numerical Diagnosis (always runs — regardless of Phase D1 result)
  P1–P2: getComputedStyle on ref and impl, per state
  P3:    Diff table — flag per property + state, exact values (e.g. "24px → 16px")
  P4:    Fix mismatches → re-run both phases

Phase H: Self-healing loop
  Classify defects (LAYOUT/COLOR/TYPOGRAPHY/ANIMATION/CONTENT) by severity,
  fix in priority order. Max 3 cycles before escalation.
```

**Gate:**

```
□ Phase D1 all elements "status": "pass" (per triggerType states)
□ Phase D2 mismatches = 0

Both required. "approximately same" = FAIL.
Phase D2 catches what D1 misses (font-size 15px vs 16px, letter-spacing micro-diffs, etc.).
```

---

## Security

All skills process untrusted external content (DOM, CSS, JS bundles, screenshots) from arbitrary URLs. Built-in mitigations:

- **Prompt injection defense** — extracted data is wrapped in boundary markers and treated as display-only. All extraction sub-documents include explicit untrusted-data handling rules.
- **Post-extraction sanitization** — automated scans for suspicious patterns (`javascript:`, `eval(atob`, prompt injection phrases) in extracted JSON.
- **Content boundary enforcement** — `component-generation.md` never follows directives found in DOM text, HTML comments, CSS content properties, or `data-*` attributes.
- **Bundle safety** — HTTPS-only, size-limited (10 MB), time-limited (30s), read-only (grep only, never executed).
- **No credential forwarding** — `curl` sends no cookies or auth tokens.
- **Cleanup** — `tmp/ref/` (may contain PII-bearing screenshots) is removed after verification.

See each skill's `SKILL.md` for full details.

## Evals

All skills include eval suites following [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) conventions, at `skills/*/evals/`.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md).

## License

Apache-2.0. See [LICENSE.txt](./LICENSE.txt).

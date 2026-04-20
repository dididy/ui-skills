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
- **Progressive-disclosure sub-docs.** Each SKILL.md contains only the pipeline and core rules. Detailed procedures (splash extraction, CSS-First generation, verification loops, pitfall tables) live in separate sub-docs loaded only when that step runs. Common paths stay lean; specialized paths expand on demand.
- **Single source of truth for transitions.** `transition-spec.json` is produced once from bundle analysis. Implementation reads the spec, never re-greps the bundle — avoiding wasted work and the risk of picking the wrong conditional branch.
- **Automation over introspection.** Script-driven gates (`validate-gate.sh`, `run-pipeline.sh`, `auto-verify.sh`) decide whether a step is complete. Agents don't self-certify "looks good enough."
- **No judgment, data only.** Every decision must be backed by extracted data, captured screenshots, or script output. "Probably", "close enough", and "just a content difference" are forbidden — each has a documented failure case.

## Skills

| Skill | Purpose |
|---|---|
| **`ui-reverse-engineering`** | Full pipeline: URL → DOM/CSS/JS extraction → React + Tailwind component |
| **`transition-reverse-engineering`** | Frame-precise animation extraction (WAAPI, canvas/WebGL, Three.js, character stagger, scroll-driven JS) |
| **`ui-capture`** | Baseline screenshots + transition capture + comparison page. Auto-detects custom scroll (Lenis, Locomotive). Classifies effects by trigger type. |
| **`visual-debug`** | All visual comparison in one skill. Quick mode (AE/SSIM batch) and full verification (Phase A→E with self-healing loop). |

## Requirements

```bash
npm i -g agent-browser       # browser automation for AI agents
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

### Optional: pipeline hooks

Three hooks enforce the extraction-before-generation discipline. They skip automatically when no `tmp/ref/` directory or active session marker exists, so they won't interfere with non-ui-re projects.

| Hook | Event | Purpose |
|------|-------|---------|
| `hooks/ui-re-start-session.sh` | Pipeline start | Creates `tmp/.ui-re-active` marker so the pre-generate hook can block writes before `tmp/ref/` exists |
| `hooks/ui-re-pre-generate-check.sh` | `PreToolUse` (Write/Edit) | Blocks component file writes until extraction pipeline completes. Only enforces on `src/components/`, `src/app/*/page.*`, and `src/projects/*/components/` |
| `hooks/ui-re-post-verify-check.sh` | `PostToolUse` (Bash) | Warns on completion signals (`commit`, `done`, etc.) if verification hasn't run, has failing positions, or is missing multi-state coverage |

Add to `.claude/settings.json` in your project root. Replace `<PLUGIN_PATH>` with the plugin root directory (e.g. `~/.claude/skills/ui-skills` for git clone, or the parent of the skill paths shown by `npx skills ls`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash <PLUGIN_PATH>/hooks/ui-re-pre-generate-check.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash <PLUGIN_PATH>/hooks/ui-re-post-verify-check.sh"
          }
        ]
      }
    ]
  }
}
```

**Session marker (optional):** Before starting the pipeline, run `bash <PLUGIN_PATH>/hooks/ui-re-start-session.sh tmp/ref/<name>` to create a `tmp/.ui-re-active` marker. This lets the pre-generate hook block component writes even before any extraction files exist in `tmp/ref/`. Without the marker, the hook only activates once `tmp/ref/` has pipeline artifacts.

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
0.  Load existing analysis     — re-invoked? load transition-spec.json + bundle-map.json, skip re-extraction
R.  Capture reference          — static screenshots + scroll video (60 fps)
1.  Open & snapshot            — DOM tree, full-page screenshot
2.  Extract structure          — HTML hierarchy, component boundaries
2.5 Extract head + assets      — title, favicon, images, original CSS files, fonts (incl. Typekit),
                                 video backgrounds, CSS variables → css/variables.txt
2.6 Catalog init styles        — GSAP-baked inline styles → animation-init-styles.json,
                                 state-coupled elements → state-coupling.json
3.  Extract styles             — computed CSS, colors, typography, spacing, design tokens
4.  Detect responsive          — 2-pass viewport sweep (coarse 40px → fine 5px) for real breakpoints
5.  Detect interactions        — hover/click/scroll, mouse-follow, stroke animations
5b. Capture C3 (deferred)      — interaction/transition videos using selectors from Step 5
5c. JS bundle download         — ALL loaded chunks via performance API. ⛔ gate: bundle
5d. Transition spec            — transition-spec.json: trigger, target, easing, duration, bundle branch.
                                 gsap-to-css.sh auto-converts easing. ⛔ gate: spec
    Bundle analysis patterns   — Canvas renderer detection, disc/carousel structure detection,
                                 Lottie asset mapping, state machine extraction, auto-timer extraction
6.  Detect animations          — Phase A idle / B scroll / C per-element (all mandatory)
                                 → transition-reverse-engineering when scroll-driven/canvas/WebGL
6b. Assemble extracted.json    — combine all extraction artifacts
6c. Pre-generation audit       — 6-stage design audit
7.  Generate component         — CSS-First: download original CSS, use original class names.
                                 Transitions implemented inline. ⛔ gate: pre-generate
8.  Visual verification        — Run `auto-verify.sh` (D0 layout + Phase C scroll AE + post-implement gate).
                                 Phase D pixel-perfect gate runs separately after auto-verify passes.
                                 + Phase E VLM sanity check. ⛔ gate: post-implement
9.  Interaction verification   — test each hover/click/scroll/timer on localhost
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
| `layout-health-check.sh` | D0: section height/total height comparison before pixel-level diff |
| `layout-diff.sh` | Structural section bounding-box comparison between two URLs |
| `batch-compare.sh` | Batch AE comparison with dynamic-region threshold support |
| `dssim-compare.sh` | Structural visual similarity (DSSIM) — catches layout issues AE misses |

**Input modes:**

| Mode | Quality | When to use |
|---|---|---|
| URL (primary) | Exact values | Live site — `getComputedStyle`, real DOM, JS bundle |
| Screenshot | Approximation (Claude Vision) | Design mockup, inaccessible site |
| Video / recording | Approximation (Claude Vision) | Interactions visible in recording |
| Multiple screenshots | Approximation (Claude Vision) | Different pages or breakpoints |

---

## `transition-reverse-engineering` — Exact Animation Extraction

Extracts animations with frame-level precision. Called automatically by `ui-reverse-engineering` when complex motion is detected, or used standalone.

Measures ALL animated properties at 11 progress points (0%–100%) before writing code — catches multi-phase timing, non-linear curves, and property-specific phase boundaries that start/end extraction misses.

**Usage:**

```
Copy this transition: https://example.com
Replicate this animation exactly
Clone this canvas effect
Extract the page-load animation from https://example.com
```

**Pipeline:**

```
-1. Multi-point measurement    — 11 progress points, ALL animated properties
 0. Capture reference frames   — screenshots or video
 1. Classify effect            — CSS transition, JS animation, or canvas/WebGL
2a. Extract CSS                — for CSS transitions/animations
2b. Extract JS bundle          — for scroll-driven/Motion/GSAP/rAF
2c. Extract Canvas/WebGL       — for canvas/WebGL
 3. Implement                  — measured values only, never guessed
 4. Verify                     — triggerable: frame comparison + Visual Gate + Numerical Diagnosis.
                                 untriggerable: bundle-verification.md (carousel, auto-rotate, page-load).
                                 Both D1 + D2 always run.
```

**Supported animation types:**

| Type | Method |
|---|---|
| CSS transitions (hover/click) | computedStyle delta before/after |
| CSS keyframe animations | CSSKeyframesRule extraction |
| Page-load WAAPI | waapi-scrub-inject.js + capture-frames.sh |
| Character stagger | Per-char selector + delay configs |
| Three.js / custom WebGL | Bundle download + grep patterns |
| Spline / Rive / Lottie | Engine detection → scene URL reference |
| Scroll-driven (Motion/GSAP/rAF) | JS bundle analysis — `useTransform`/`useScroll` keyframes, interpolation ranges, scroll offsets |
| Scroll behavior (snap/smooth/overscroll) | CSS detection + JS library extraction (Lenis, ScrollSmoother, Locomotive) |
| Auto-timer (carousel/slideshow) | Timed screenshot comparison + `setInterval`/`setTimeout` bundle grep |
| Framer Motion springs | Bundle grep — `stiffness`/`damping`/`mass` → cubic-bezier mapping |
| GSAP tweens | Bundle grep — `gsap.to`/`fromTo`/`timeline`, `ScrollTrigger`, ease/duration/stagger |
| CSS-in-JS responsive layout | Raw stylesheet extraction — `calc()`, `cqw`, `%`, custom properties |
| Mouse-follow / parallax tilt | DOM detection — absolutely-positioned `pointer-events: none` children |
| Stroke-based SVG hover | Stroke delta — idle/active `stroke-dasharray` + `stroke-dashoffset` |

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

- **Quick comparison** — `auto-verify.sh` runs D0 layout health check → batch-scroll capture → AE comparison → post-implement gate in one command. Zero vision tokens.
- **Full verification** — `verification.md` with Phase A/B capture → Phase C comparison → Phase D0 layout health → Phase D pixel-perfect gate → Phase H self-healing loop → Phase E VLM sanity check.

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

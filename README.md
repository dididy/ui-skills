# ui-skills — Clone any website into React + Tailwind

A [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) plugin that reverse-engineers any live website into a production-ready React + Tailwind component — from the actual source, not a screenshot.

Give it a live URL and it extracts computed CSS, DOM structure, JS interactions, responsive breakpoints, animations, visual assets (favicon, title, images), and inline SVGs verbatim — actual values from `getComputedStyle`, not pixel guesses. Detects custom scroll engines, portal-escaped fixed elements, mouse-follow interactions, and stroke-based SVG hover animations. Screenshots and screen recordings are also accepted as fallback inputs (analyzed via Claude Vision), but only URL input gives exact values.

> **vs. screenshot-to-code tools:** Those tools copy what's visible. For URL input, `ui-skills` reads `getComputedStyle`, greps JS bundles, and scrubs WAAPI animations frame-by-frame — so hover states, easing curves, and stagger timing are extracted, not approximated.

Three skills included, plus one shared verification document:

1. **`ui-reverse-engineering`** — full pipeline: URL → DOM/CSS/JS extraction → React + Tailwind component
2. **`transition-reverse-engineering`** — precise animation extraction (WAAPI, canvas/WebGL, Three.js, character stagger, **scroll-driven JS animations**)
3. **`ui-capture`** — baseline screenshot + transition capture from reference URLs, with web-based comparison page for verifying UI clone fidelity. Standalone analysis generates an overlay-based report: fullpage screenshot as base layer with interactive transition overlays (videos/images) pinned at exact page coordinates (`bounds.x/y`), sidebar region index, and IntersectionObserver-driven auto-play. Auto-detects custom scroll containers (Lenis, Locomotive, `overflow: hidden`) and uses real mouse-wheel events for accurate scroll recording. Captures section-by-section viewport-resized screenshots. Classifies each effect by trigger type before capturing: `css-hover`/`js-class` → eval + clip screenshot (idle + active); `intersection` → eval + clip screenshot (before + after); `scroll-driven` → exploration video then clip screenshots at before/mid/after; `mousemove`/`auto-timer` → video.
4. **`pixel-perfect-diff`** *(shared verification document)* — mandatory visual verification gate invoked by all three skills. Phase 1 captures DOM clip screenshots per element per state (idle / active / before / mid / after by triggerType) and diffs with AE/SSIM — this is the pass/fail criterion. Phase 2 runs `getComputedStyle` always (regardless of Phase 1 result) to catch sub-pixel mismatches like `font-size: 15px vs 16px` that AE/SSIM passes. Both must pass. "Looks the same" is not a valid completion criterion.

## Requirements

```bash
brew install agent-browser   # macOS
npm install -g agent-browser # any platform

agent-browser --version      # verify

brew install ffmpeg           # macOS — required for visual verification (frame extraction)
# Linux: sudo apt install ffmpeg  |  Windows: https://ffmpeg.org/download.html
```

## Installation

```bash
# npx skills (recommended)
npx skills install dididy/ui-skills

# Claude Code plugin marketplace
/plugin marketplace add dididy/ui-skills
/plugin install ui-skills@dididy

# Clone directly (CLAUDE_SKILLS_DIR defaults to ~/.claude/skills)
mkdir -p ~/.claude/skills
git clone https://github.com/dididy/ui-skills.git ~/.claude/skills/ui-skills
```

---

## Skill 1: `ui-reverse-engineering` — Website to React Component

Reverse-engineers any live website into a React + Tailwind component. For URL input, extracts real values — never guesses. Screenshot and screen recording inputs are also accepted as fallback (Claude Vision approximation).

### When to Use

- You want to clone a UI component or page layout from a live site
- You have a design mockup or screenshot to turn into code
- You need responsive behavior extracted (mobile/tablet/desktop)
- You have a screen recording of interactions to replicate

### Usage

```
Clone this site: https://example.com
Copy the hero section from https://example.com
Replicate this UI (attach screenshot)
Turn this screen recording into a working component
```

### How It Works

Steps R–9 apply to URL input. For screenshot/video input, steps 1–6 are replaced by Claude Vision analysis.

```
Input URL
  ↓
0.  Load Existing Analysis — if re-invoked, load transition-spec.json + bundle-map.json
                             immediately. Skip re-extraction of known transitions.
  ↓
R.  Capture Reference     — static screenshots + scroll video (60 fps). C3 deferred to 5b
  ↓
1.  Open & Snapshot        — DOM tree, full-page screenshot
  ↓
2.  Extract Structure      — HTML hierarchy, component boundaries
  ↓
2.5 Extract Head + Assets  — title, favicon, visible images downloaded to assets/
  ↓
3.  Extract Styles         — computed CSS, colors, typography, spacing, design tokens
  ↓
4.  Detect Responsive      — 2-pass viewport sweep (coarse 40px → fine 5px) to find real breakpoints
  ↓
5.  Detect Interactions    — hover/click/scroll transitions, mouse-follow, stroke animations
      ↓ (complex animation detected)
      → transition-reverse-engineering — 11-point measurement + frame comparison
  ↓
5b. Capture C3 (deferred)  — interaction/transition videos using selectors from Step 5
  ↓
5c. JS Bundle Download     — MANDATORY. download-chunks.sh downloads ALL loaded chunks
                             (lazy chunks via performance API, not just main.js).
                             Produces bundle-analysis.json + skeleton bundle-map.json.
                             ⛔ GATE: validate-gate.sh <dir> bundle
  ↓
5d. Transition Spec        — produce transition-spec.json (per-transition spec with trigger,
                             target, easing, duration, bundle branch, reference frames).
                             Single source of truth for implementation. gsap-to-css.sh
                             converts easing values automatically.
                             ⛔ GATE: validate-gate.sh <dir> spec
  ↓
6.  Detect Animations      — ALL 3 phases MANDATORY:
                             Phase A: idle capture (10s video) — splash/intro detection
                             Phase B: scroll capture — scroll-driven motion
                             Phase C: per-element tracking — targeted animation capture
      ↓ (scroll-driven/canvas/WebGL found)
      → transition-reverse-engineering for JS extraction
  ↓
6b. Assemble extracted.json — combine all extraction artifacts
  ↓
6c. Pre-generation audit   — 6-stage design audit
  ↓
7.  Generate Component     — React + Tailwind, exact values from transition-spec.json.
                             ⛔ GATE: validate-gate.sh <dir> pre-generate
  ↓
8.  Visual Verification    — AE/SSIM comparison (zero tokens) + 10-point scoring
                             + Phase D (pixel-perfect gate) + Phase E (VLM sanity check)
                             ⛔ GATE: validate-gate.sh <dir> post-implement (after each transition)
  ↓
9.  Interaction Verification — test each hover/click/scroll/timer on localhost
```

### Automation Scripts

| Script | Purpose |
|---|---|
| `validate-gate.sh` | Enforces extraction gates (bundle, spec, pre-generate, post-implement). Exits 1 on failure — hard blocks. |
| `download-chunks.sh` | Downloads ALL loaded JS chunks, detects animation libraries, produces skeleton bundle-map.json. |
| `gsap-to-css.sh` | Converts GSAP easing names to CSS cubic-bezier. Single lookup, full table, or bundle scan. |

### Input Modes

| Mode | Quality | When to use |
|------|---------|-------------|
| **URL** (primary) | Exact values | Live site — `getComputedStyle`, real DOM, JS bundle |
| **Screenshot** | Approximation (Claude Vision) | Design mockup, inaccessible site |
| **Video / screen recording** | Approximation (Claude Vision) | Interactions visible in recording |
| **Multiple screenshots** | Approximation (Claude Vision) | Different pages or breakpoints |

---

## Skill 2: `transition-reverse-engineering` — Exact Animation Extraction

Extracts animations and transitions with frame-level precision. Called automatically by `ui-reverse-engineering` when complex motion is detected, or used standalone.

Measures ALL animated properties at 11 progress points (0%–100%) before writing any code — catches multi-phase timing, non-linear curves, and property-specific phase boundaries that start/end extraction misses.

### When to Use

- You need frame-perfect replication of a page-load animation
- The target uses character stagger, WAAPI, or canvas/WebGL
- The target uses scroll-driven animations (Motion `useTransform`/`useScroll`, GSAP `ScrollTrigger`, rAF)
- You want exact easing curves, durations, and delays
- CSS computed values alone aren't enough (JS bundle analysis needed)

### Usage

```
Copy this transition: https://example.com
Replicate this animation exactly
Clone this canvas effect
Extract the page-load animation from https://example.com
```

### How It Works

```
Step -1: Multi-point measurement  — 11 progress points, ALL animated properties
  ↓
Step  0: Capture reference frames — screenshots or video from original site
  ↓
Step  1: Classify effect          — CSS transition, JS-driven animation, or canvas/WebGL
  ↓
Step 2a: Extract CSS              — css-extraction.md (for CSS transitions/animations)
Step 2b: Extract JS bundle        — js-animation-extraction.md (for scroll-driven/Motion/GSAP/rAF)
Step 2c: Extract Canvas/WebGL     — canvas-webgl-extraction.md (for canvas/WebGL)
  ↓
Step  3: Implement                — using measured values only, never guessed
  ↓
Step  4: Verify                   — frame comparison + Phase 1 Visual Gate (clip AE/SSIM) + Phase 2 Numerical Diagnosis (getComputedStyle), both always run
```

### Supported Animation Types

| Type | Method |
|------|--------|
| CSS transitions (hover/click) | computedStyle delta before/after |
| CSS keyframe animations | CSSKeyframesRule extraction |
| Page-load WAAPI | waapi-scrub-inject.js + capture-frames.sh |
| Character stagger | Per-char selector + delay configs |
| Three.js / custom WebGL | Bundle download + grep patterns |
| Spline / Rive / Lottie | Engine detection → scene URL reference |
| Scroll-driven (Motion/GSAP/rAF) | **JS bundle analysis** — extracts `useTransform`/`useScroll` keyframes, interpolation ranges, scroll offsets |
| Scroll behavior (snap/smooth/overscroll) | **CSS detection** (`scroll-snap-*`, `scroll-behavior`, `overscroll-behavior`) + **JS library extraction** (Lenis, GSAP ScrollSmoother, Locomotive) when detected in bundles |
| Auto-timer (carousel/slideshow) | **Timed screenshot comparison** (4s interval) + `setInterval`/`setTimeout` bundle grep |
| Framer Motion springs | **Bundle grep** — `stiffness`/`damping`/`mass`, `AnimatePresence` mode, motion props → cubic-bezier mapping |
| GSAP tweens | **Bundle grep** — `gsap.to`/`fromTo`/`timeline`, `ScrollTrigger`, ease/duration/stagger |
| CSS-in-JS responsive layout | **Raw stylesheet extraction** — `calc()`, `cqw`, `%`, custom properties |
| Mouse-follow / parallax tilt | **DOM detection** — absolutely-positioned `pointer-events: none` children of interactive rows |
| Stroke-based SVG hover | **Stroke delta** — idle/active `stroke-dasharray` + `stroke-dashoffset` on SVG children |

---

## Skill 3: `ui-capture` — Visual Capture & Comparison

Captures baseline screenshots and transition videos from any reference URL. Standalone mode generates an overlay-based analysis report (fullpage screenshot with interactive transition overlays). Comparison mode generates a side-by-side page for verifying UI clone fidelity.

Classifies each interactive effect by trigger type before recording — preventing blank videos caused by wrong activation method.

### When to Use

- You want a reference baseline before starting a UI clone
- You need to record how a site's scroll, hover, or cursor effects look
- You want to compare your implementation against the original side-by-side
- You're verifying visual fidelity after implementation

### Usage

```
Capture the transitions from https://example.com
Record the hover effects on https://example.com
Compare https://example.com vs http://localhost:3000
Take a baseline screenshot of https://example.com before I start cloning
```

### How It Works

```
Phase 1: Full Page Capture      — section screenshots + full scroll video
  ↓                               auto-detects custom scroll containers (Lenis, Locomotive, etc.)
Phase 2: Transition Detection   — classify all effects by trigger type, save regions.json
  ↓
Phase 2B–2E: Capture Transitions — per trigger type:
  2B scroll-driven  — exploration video → clip screenshot before/mid/after
  2C css-hover      — eval + clip screenshot: idle + active
     js-class       — eval classList.add + clip screenshot: idle + active
     intersection   — eval classList.add + clip screenshot: before + after
  2D mousemove      — raster-path sweep video
  2E auto-timer     — passive recording for 2–3 cycles
  ↓
  ├── local-url provided? ─── YES ──→ Phase 3: Implementation Capture
  │                                      ↓
  │                                    Phase 4A: Pixel-Perfect Gate (AE/SSIM + getComputedStyle)
  │                                      ↓
  │                                    Phase 4B: compare.html (side-by-side original vs clone)
  │                                      ↓
  │                                    Phase 5: User Review
  │
  └── NO (standalone) ──────────────→ Phase R: report.html (overlay-based analysis report)
                                        ↓
                                      Phase 5: User Review
```

### Trigger Type Classification

| Trigger type | Detection | Activation |
|---|---|---|
| `css-hover` | `:hover` rule in stylesheet | eval + clip screenshot (idle + active) |
| `js-class` | JS adds/removes a class | eval classList.add + clip screenshot (idle + active) |
| `intersection` | `data-in-view`, IntersectionObserver | eval classList.add + clip screenshot (before + after) |
| `scroll-driven` | `animation-timeline: scroll()`, sticky, willChange | exploration video → clip screenshots (before / mid / after) |
| `mousemove` | `mousemove` listener, parallax/tilt/magnetic patterns | raster-path sweep (video) |
| `auto-timer` | setInterval, CSS animation, carousel/swiper | passive wait (video) |

---

## Shared Document: `pixel-perfect-diff` — Mandatory Visual Verification Gate

Compares reference and implementation at element level using DOM clip screenshots — not eyeball comparison. The Visual Gate (Phase 1) is the objective pass/fail criterion. Numerical Diagnosis (Phase 2) always runs in parallel regardless of Phase 1 result — catches sub-pixel mismatches like `font-size: 15px vs 16px` that pixel diff passes.

Screenshot comparison misses 2px font-size differences, 10px spacing errors, and wrong font-weight. Clip screenshot diff catches them all — across all states: idle, active (hover/animated), and before/mid/after (scroll-driven).

### When to Use

- Automatically invoked as Phase D in `ui-reverse-engineering` Step 8
- Automatically invoked as Phase 4A in `ui-capture`
- Automatically invoked in `transition-reverse-engineering` Step 4 for resting states (before + after)
- Standalone: any time you need to verify exact visual fidelity

### How It Works

```
Phase 1: Visual Gate (always runs)
  V1: Define elements + states  — idle for all; active for css-hover/js-class/intersection;
                                  before/mid/after for scroll-driven
  V2: Measure rect + activate   — scrollIntoView, then eval to apply state; re-measure rect
  V3: Clip screenshot           — ref and impl, per element per state
  V4: Pixel diff                — ImageMagick AE or ffmpeg SSIM
  V5: Pass/fail judgment        — AE=0 or SSIM≥0.995 = pass
  V6: Save Visual Gate results

Phase 2: Numerical Diagnosis (always runs — regardless of Phase 1 result)
  P1: getComputedStyle ref      — all states, save ref-styles-<state>.json
  P2: getComputedStyle impl     — same, save impl-styles-<state>.json
  P3: Diff table                — flag ❌ per property + state, exact value reported (e.g. "24px → 16px")
  P4: Fix mismatches            — edit CSS, re-measure
  P5: Re-run Phase 1 + Phase 2

→ Both pass: done
→ Either fails: fix → re-run both
```

### Gate

```
□ Phase 1 all elements "status": "pass" (idle / active / before / mid / after — by triggerType)
□ Phase 2 mismatches = 0

Both required. "approximately same" = FAIL.
Phase 2 catches what Phase 1 misses (font-size: 15px vs 16px, letter-spacing micro-differences, etc.).
```

---

## Security

All three skills (`ui-reverse-engineering`, `transition-reverse-engineering`, `ui-capture`) process untrusted external content (DOM, CSS, JS bundles, and screenshots) from arbitrary URLs. Built-in mitigations:

- **Prompt injection defense** — extracted data is wrapped in boundary markers and treated as display-only content, never as instructions. All extraction sub-documents include explicit untrusted-data handling rules.
- **Post-extraction sanitization** — automated scans for suspicious patterns (`javascript:`, `eval(atob`, prompt injection phrases) in extracted JSON. `interaction-detection.md` runs a grep check after saving `interactions-detected.json`.
- **Content boundary enforcement** — `component-generation.md` treats all extracted text as untrusted data (never follows directives found in DOM text, HTML comments, CSS content properties, or `data-*` attributes)
- **Bundle safety** — downloads are HTTPS-only, size-limited (10 MB), time-limited (30s), and read-only (grep analysis only, never executed locally)
- **No credential forwarding** — `curl` invocations send no cookies or auth tokens
- **Sensitive data cleanup** — `tmp/ref/` directories (which may contain screenshots with PII/auth tokens) are cleaned up after verification

See the Security section in each skill's `SKILL.md` and sub-documents for full details.

## Evals

All three skills include eval suites following [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) conventions. Located at `skills/*/evals/`. (`pixel-perfect-diff` is a shared document, not a registered skill, and does not have its own eval suite — its scenarios are covered by the three skills' evals.)

---

## License

Apache-2.0 — same as [anthropics/skills](https://github.com/anthropics/skills).

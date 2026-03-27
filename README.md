# ui-skills — Clone any website into React + Tailwind

A [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) plugin that reverse-engineers any live website into a production-ready React + Tailwind component — from the actual source, not a screenshot.

Give it a live URL and it extracts computed CSS, DOM structure, JS interactions, responsive breakpoints, and animations — actual values from `getComputedStyle`, not pixel guesses. Screenshots and screen recordings are also accepted as fallback inputs (analyzed via Claude Vision), but only URL input gives exact values.

> **vs. screenshot-to-code tools:** Those tools copy what's visible. For URL input, `ui-skills` reads `getComputedStyle`, greps JS bundles, and scrubs WAAPI animations frame-by-frame — so hover states, easing curves, and stagger timing are extracted, not approximated.

Three skills included, plus one shared verification document:

1. **`ui-reverse-engineering`** — full pipeline: URL → DOM/CSS/JS extraction → React + Tailwind component
2. **`transition-reverse-engineering`** — precise animation extraction (WAAPI, canvas/WebGL, Three.js, character stagger, **scroll-driven JS animations**)
3. **`ui-capture`** — baseline screenshot + transition video capture from reference URLs, with web-based comparison page for verifying UI clone fidelity. Classifies each effect by trigger type (`css-hover`, `js-class`, `intersection`, `scroll-driven`, `mousemove`, `auto-timer`) before recording. Handles scroll/hover/cursor-reactive/auto-timer transitions with synchronized side-by-side video comparison.
4. **`pixel-perfect-diff`** *(shared verification document)* — mandatory numerical verification gate invoked by all three skills. Measures every key element with `getComputedStyle` on both reference and implementation, diffs all typography/spacing/sizing/layout properties, and requires `mismatches: 0` before any verification step can declare PASS. "Looks the same" is not a valid completion criterion.

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
R.  Capture Reference     — static screenshots + scroll video (60 fps). C3 deferred to 5b
  ↓
1.  Open & Snapshot        — DOM tree, full-page screenshot
  ↓
2.  Extract Structure      — HTML hierarchy, component boundaries
  ↓
3.  Extract Styles         — computed CSS, colors, typography, spacing, design tokens
  ↓
4.  Detect Responsive      — 2-pass viewport sweep (coarse 40px → fine 5px) to find real breakpoints
  ↓
5.  Detect Interactions    — hover/click/scroll transitions and animations
      ↓ (complex animation detected)
      → transition-reverse-engineering — 11-point measurement + frame comparison
  ↓
5b. Capture C3 (deferred)  — interaction/transition videos using selectors from Step 5
  ↓
6.  Analyze JS (if needed) — bundle grep for complex interactions
  ↓
6b. Assemble extracted.json — combine structure + styles + breakpoints + interactions
  ↓
7.  Generate Component     — React + Tailwind, exact values, functional JS
  ↓
8.  Visual Verification    — Phase A/B/C (frame comparison) + Phase D (pixel-perfect numerical diff)
  ↓
9.  Interaction Verification — test each hover/click/scroll/timer on localhost
```

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
Step  4: Verify                   — frame comparison tables + pixel-perfect numerical diff (mismatches: 0 required)
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
| CSS-in-JS responsive layout | **Raw stylesheet extraction** — `calc()`, `cqw`, `%`, custom properties |

---

## Skill 3: `ui-capture` — Visual Capture & Comparison

Captures baseline screenshots and transition videos from any reference URL, then generates a web-based side-by-side comparison page for verifying UI clone fidelity.

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
Phase 1: Full Page Capture   — static screenshot + full scroll video
  ↓
Phase 2: Transition Detection — classify all effects by trigger type, save regions.json
  ↓
Phase 2B–2E: Capture Transitions — per trigger type:
  2B scroll-driven  — scroll through transition range
  2C css-hover      — CDP hover in/hold/out
     js-class       — eval class toggle add/remove
     intersection   — smooth scroll into viewport
  2D mousemove      — raster-path sweep video (10×10 grid, single video)
  2E auto-timer     — passive recording for 2–3 cycles
  ↓
Phase 3: Implementation Capture — identical sequences on local-url
  ↓
Phase 4A: Pixel-Perfect Diff — getComputedStyle numerical diff, mismatches: 0 required
  ↓
Phase 4B: Comparison Page    — pixel-perfect diff table + side-by-side paired videos
  ↓
Phase 5: User Review         — present URL, wait for feedback
```

### Trigger Type Classification

| Trigger type | Detection | Activation |
|---|---|---|
| `css-hover` | `:hover` rule in stylesheet | `agent-browser hover` |
| `js-class` | JS adds/removes a class | eval class toggle |
| `intersection` | `data-in-view`, IntersectionObserver | smooth scroll into viewport |
| `scroll-driven` | `animation-timeline: scroll()`, sticky, willChange | scroll through range |
| `mousemove` | `mousemove` listener, parallax/tilt/magnetic patterns | raster-path sweep |
| `auto-timer` | setInterval, CSS animation, carousel/swiper | passive wait |

---

## Shared Document: `pixel-perfect-diff` — Mandatory Numerical Verification Gate

Measures every key element on the reference site and implementation using `getComputedStyle`, diffs all typography, spacing, sizing, layout, visual, and position properties, and requires `mismatches: 0` before any verification step can declare PASS.

Screenshot comparison misses 2px font-size differences, 10px spacing errors, and wrong font-weight. This skill provides the numerical ground truth.

### When to Use

- Automatically invoked as Phase D in `ui-reverse-engineering` Step 8
- Automatically invoked as Phase 4A in `ui-capture`
- Automatically invoked in `transition-reverse-engineering` Step 4 for resting states (before + after)
- Standalone: any time you need to verify exact CSS fidelity

### How It Works

```
P1: Define key elements     — layout containers, typography carriers, visible at first render
  ↓
P2: Measure reference       — getComputedStyle for all properties, save ref-styles.json
  ↓
P3: Measure implementation  — same elements locally, save impl-styles.json
  ↓
P4: Build diff table        — element × property, flag ❌ MISMATCH for any difference
  ↓
P5: Fix all mismatches      — edit CSS, re-measure, update table to ✅
  ↓
P6: Write pixel-perfect-diff.json — "result": "pass", "mismatches": 0 required
```

### Gate

```
□ ref-styles.json exists
□ impl-styles.json exists
□ pixel-perfect-diff.json → "result": "pass"
□ pixel-perfect-diff.json → "mismatches": 0

"거의 동일" (approximately same) = FAIL. Only mismatches: 0 = PASS.
```

---

## Security

All three skills (`ui-reverse-engineering`, `transition-reverse-engineering`, `ui-capture`) process untrusted external content (DOM, CSS, JS bundles, and screenshots) from arbitrary URLs. Built-in mitigations:

- **Prompt injection defense** — extracted data is wrapped in boundary markers and treated as display-only content, never as instructions
- **Post-extraction sanitization** — automated scans for suspicious patterns (`javascript:`, `eval(atob`, prompt injection phrases) in extracted JSON
- **Bundle safety** — downloads are HTTPS-only, size-limited (10 MB), time-limited (30s), and read-only (grep analysis only, never executed locally)
- **No credential forwarding** — `curl` invocations send no cookies or auth tokens
- **Sensitive data cleanup** — `tmp/ref/` directories (which may contain screenshots with PII/auth tokens) are cleaned up after verification

See the Security section in each skill's `SKILL.md` for full details.

## Evals

All three skills include eval suites following [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) conventions. Located at `skills/*/evals/`. (`pixel-perfect-diff` is a shared document, not a registered skill, and does not have its own eval suite — its scenarios are covered by the three skills' evals.)

---

## License

Apache-2.0 — same as [anthropics/skills](https://github.com/anthropics/skills).

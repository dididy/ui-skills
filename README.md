# ui-skills — Clone any website into React + Tailwind

A [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) plugin that reverse-engineers any live website into a production-ready React + Tailwind component — from the actual source, not a screenshot.

Give it a live URL and it extracts computed CSS, DOM structure, JS interactions, responsive breakpoints, and animations — actual values from `getComputedStyle`, not pixel guesses. Screenshots and screen recordings are also accepted as fallback inputs (analyzed via Claude Vision), but only URL input gives exact values.

> **vs. screenshot-to-code tools:** Those tools copy what's visible. For URL input, `ui-skills` reads `getComputedStyle`, greps JS bundles, and scrubs WAAPI animations frame-by-frame — so hover states, easing curves, and stagger timing are extracted, not approximated.

Two skills included:

1. **`ui-reverse-engineering`** — full pipeline: URL → DOM/CSS/JS extraction → React + Tailwind component
2. **`transition-reverse-engineering`** — precise animation extraction (WAAPI, canvas/WebGL, Three.js, character stagger, **scroll-driven JS animations**)

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
8.  Visual Verification    — C1 (static) + C2 (scroll) + C3 (transitions) comparison
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
Step  4: Verify                   — frame-by-frame comparison (element or fullpage scope)
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

## Security

Both skills process untrusted external content (DOM, CSS, JS bundles) from arbitrary URLs. Built-in mitigations:

- **Prompt injection defense** — extracted data is wrapped in boundary markers and treated as display-only content, never as instructions
- **Post-extraction sanitization** — automated scans for suspicious patterns (`javascript:`, `eval(atob`, prompt injection phrases) in extracted JSON
- **Bundle safety** — downloads are HTTPS-only, size-limited (10 MB), time-limited (30s), and read-only (grep analysis only, never executed locally)
- **No credential forwarding** — `curl` invocations send no cookies or auth tokens
- **Sensitive data cleanup** — `tmp/ref/` directories (which may contain screenshots with PII/auth tokens) are cleaned up after verification

See the Security section in each skill's `SKILL.md` for full details.

## Evals

Both skills include eval suites following [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) conventions. Located at `skills/*/evals/`.

---

## License

Apache-2.0 — same as [anthropics/skills](https://github.com/anthropics/skills).

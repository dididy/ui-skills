# ui-skills — Clone any website into React + Tailwind

A [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) plugin that reverse-engineers any live website into a production-ready React + Tailwind component — from the actual source, not a screenshot.

Give it a live URL and it extracts computed CSS, DOM structure, JS interactions, responsive breakpoints, and animations — actual values from `getComputedStyle`, not pixel guesses. Screenshots and screen recordings are also accepted as fallback inputs (analyzed via Claude Vision), but only URL input gives exact values.

> **vs. screenshot-to-code tools:** Those tools copy what's visible. For URL input, `ui-skills` reads `getComputedStyle`, greps JS bundles, and scrubs WAAPI animations frame-by-frame — so hover states, easing curves, and stagger timing are extracted, not approximated.

Two skills included:

1. **`ui-reverse-engineering`** — full pipeline: URL → DOM/CSS/JS extraction → React + Tailwind component
2. **`transition-reverse-engineering`** — precise animation extraction (WAAPI, canvas/WebGL, Three.js, character stagger)

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
R. Capture Reference    — static screenshots + scroll video + interaction videos (60 fps)
  ↓
1. Open & Snapshot       — DOM tree, full-page screenshot
  ↓
2. Extract Structure     — HTML hierarchy, component boundaries
  ↓
3. Extract Styles        — computed CSS, colors, typography, spacing, design tokens
  ↓
4. Extract Responsive    — styles at actual CSS breakpoints (default: 375 / 768 / 1440px)
  ↓
5. Detect Interactions   — hover/click/scroll transitions and animations
     ↓ (complex animation detected)
     → transition-reverse-engineering — precise extraction + frame comparison
  ↓
6. Analyze JS (if needed)— bundle grep for complex interactions
  ↓
7. Generate Component    — React + Tailwind, exact values, functional JS
  ↓
8. Visual Verification   — static screenshot + scroll video + interaction video comparison
  ↓
9. Iterate               — fix mismatches, re-verify until all three capture types match
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

### When to Use

- You need frame-perfect replication of a page-load animation
- The target uses character stagger, WAAPI, or canvas/WebGL
- You want exact easing curves, durations, and delays
- CSS computed values alone aren't enough

### Usage

```
Copy this transition: https://example.com
Replicate this animation exactly
Clone this canvas effect
Extract the page-load animation from https://example.com
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
| Scroll-triggered | IntersectionObserver frame recording |

---

## License

Apache-2.0 — same as [anthropics/skills](https://github.com/anthropics/skills).

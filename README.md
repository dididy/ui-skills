# ui-skills

A [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) plugin with two UI reverse-engineering skills:

1. **`ui-reverse-engineering`** — full pipeline: URL → DOM/CSS/JS extraction → React + Tailwind component
2. **`transition-reverse-engineering`** — animation extraction sub-skill (WAAPI, canvas/WebGL, Three.js)

Screenshot-to-code tools capture what they can see. `ui-skills` reads the actual source — computed CSS, DOM structure, JS interactions, responsive breakpoints, and animations — from the live site.

## Installation

```bash
# npx skills (recommended)
npx skills install dididy/ui-skills

# Claude Code plugin marketplace
/plugin marketplace add dididy/ui-skills
/plugin install ui-skills@dididy

# Clone directly
mkdir -p ~/.claude/skills
git clone https://github.com/dididy/ui-skills.git ~/.claude/skills/ui-skills
```

## Requirements

```bash
brew install agent-browser   # macOS
npm install -g agent-browser # any platform

agent-browser --version      # verify
```

---

## Skill 1: `ui-reverse-engineering` — Full Pipeline

Reverse-engineers a live website into a React + Tailwind component. Extracts real values — never guesses.

### When to Use

- You want to clone a UI component or page layout from a live site
- You have a Figma screenshot or design mockup to turn into code
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

```
Input (URL / screenshot / video)
  ↓
1. Open & Snapshot       — DOM tree, full-page screenshot
  ↓
2. Extract Structure     — HTML hierarchy, component boundaries
  ↓
3. Extract Styles        — computed CSS, colors, typography, spacing, design tokens
  ↓
4. Extract Responsive    — styles at 375px / 768px / 1440px breakpoints
  ↓
5. Detect Interactions   — hover/click/scroll transitions and animations
     ↓ (complex animation detected)
     → transition-reverse-engineering — precise extraction + frame comparison
  ↓
6. Analyze JS (if needed)— bundle grep for complex interactions
  ↓
7. Generate Component    — React + Tailwind, exact values, functional JS
  ↓
8. Visual Verification   — screenshot comparison, iterate until matched
```

### Input Modes

| Mode | When to use |
|------|-------------|
| **URL** (primary) | Live site — gets actual CSS/DOM/JS |
| **Screenshot** | Design mockup, Figma export, inaccessible site |
| **Video / screen recording** | Captures interactions and state changes |
| **Multiple screenshots** | Different pages or breakpoints |

---

## Skill 2: `transition-reverse-engineering` — Animation Extraction

Extracts animations and transitions precisely. Called automatically by `ui-reverse-engineering` when complex motion is detected, or used standalone.

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

## Why not just screenshot?

Screenshots miss timing, easing, and anything that requires interaction to see. `ui-skills` scrubs WAAPI animations frame-by-frame and greps JS bundles directly — so the output matches structurally, not just visually.

## License

Apache-2.0 — same as [anthropics/skills](https://github.com/anthropics/skills).

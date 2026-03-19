---
name: ui-reverse-engineering
description: Reverse-engineer any website into production-ready React + Tailwind code. Triggers on "clone this site", "copy this UI", "replicate this page", "turn this into code", "reverse-engineer this", "make it look like X". Extracts DOM structure, computed CSS, JS interactions, responsive breakpoints, and animations from a live URL — then generates a working component. Use transition-reverse-engineering sub-skill for precise animation extraction.
---

# UI Reverse Engineering

Reverse-engineer a live website into a **React + Tailwind** component.

**Core principles:**
- **URL input:** Extract actual values via `getComputedStyle`, DOM inspection, and JS bundle analysis. Never guess.
- **Screenshot/video input (fallback):** Analyzed via Claude Vision — values are approximations, not computed properties.
- **Extraction ≠ completion.** Extraction ends when `extracted.json` is saved. Completion requires Phase B + Phase C visual verification against the running implementation.
- **Diagnose before fixing.** When a bug appears, name the root cause in one sentence before touching code. If you cannot name it, instrument the browser to find it first.
- **Verify entry points.** Before declaring done, confirm CSS resets and global styles are imported in the app's entry file (`main.tsx`, `index.tsx`, etc.). Missing imports are silent — `body { margin: 0 }` in a file that isn't imported does nothing.

## Dependencies

```bash
brew install agent-browser        # macOS
npm install -g agent-browser      # any platform

agent-browser --version           # verify
```

## Process

```
Input (URL / screenshot / video)
  ↓
1. Open & Snapshot        — DOM tree, screenshots          → dom-extraction.md
  ↓
2. Extract Structure      — HTML hierarchy, component boundaries → dom-extraction.md
  ↓
3. Extract Styles         — computed CSS, colors, typography, spacing
  ↓                                                         → style-extraction.md
4. Extract Responsive     — breakpoint-by-breakpoint styles
  ↓
5. Detect Interactions    — hover/click/scroll, transitions, animations
  ↓                                                         → interaction-detection.md
6. Analyze JS (if needed) — bundle grep for complex interactions
     ↓ complex animation?
     → invoke transition-reverse-engineering skill, then resume at Step 7
  ↓
7. Generate Component     — React + Tailwind               → component-generation.md
  ↓
8. Visual Verification    — screenshot comparison, iterate → visual-verification.md
```

## Input Modes

| Mode | When to use | How |
|------|-------------|-----|
| **URL** (primary) | Live site — gets actual CSS/DOM/JS | `agent-browser open <url>` |
| **Screenshot** | Design mockup, inaccessible site | Pass image to Claude Vision for layout analysis |
| **Video / screen recording** | Interactions visible in recording | Pass to Claude Vision; describe state changes per visible frame |
| **Multiple screenshots** | Different pages or breakpoints | Treat as separate views; link or scaffold together |

**Screenshot / Video fallback prompt:**
> "Analyze this [screenshot/video] and extract: layout structure, colors (approximate hex from visual), typography (size/weight/family), spacing, and any visible interactions or state changes. Output as structured JSON matching the `extracted.json` format."

## Output

Save extracted data summary to `tmp/ref/<component>/extracted.json`:

```json
{
  "url": "https://target-site.com",
  "component": "HeroSection",
  "breakpoints": { "mobile": 375, "tablet": 768, "desktop": 1440 },  // fill with actual extracted values
  "tokens": { "colors": {}, "spacing": {}, "typography": {} },
  "interactions": { "hover": {}, "scroll": [], "animations": [] }
}
```

## Quick Reference

```bash
agent-browser open <url>                    # Navigate
agent-browser snapshot                      # Accessibility tree
agent-browser screenshot [path]             # Capture
agent-browser set viewport <w> <h>          # Resize viewport
agent-browser hover <selector>              # Trigger hover
agent-browser click <selector>              # Trigger click
agent-browser scroll <dir> [px]             # Scroll
agent-browser eval "<iife>"                 # Execute JS — must be IIFE: (() => { ... })()
agent-browser wait <sel|ms>                 # Wait for element or time
agent-browser record start <path.webm>      # Start screen recording
agent-browser record stop                   # Stop recording
agent-browser close                         # Kill session
```

## Reference Files

- **dom-extraction.md** — Steps 1–2: open, snapshot, DOM hierarchy
- **style-extraction.md** — Steps 3–4: computed styles, design tokens, responsive breakpoints
- **interaction-detection.md** — Steps 5–6: hover/scroll/keyframes, JS bundle analysis
- **component-generation.md** — Step 7: generation prompt, iteration rules
- **visual-verification.md** — Step 8: Phase A/B/C recording, frame comparison

## Sub-skills

- **`transition-reverse-engineering`** — precise animation/transition extraction (WAAPI scrubbing, canvas/WebGL, character stagger, frame-by-frame comparison)

## When called from a ralph worker

If this skill is invoked as part of a ralph task (e.g. task description contains `/ui-reverse-engineering`):

1. **Dismiss any modals or overlays before capturing** — cookie banners, signup prompts, etc. must be closed first or they will appear in reference frames
2. **"Already implemented" is not grounds for skipping** — always capture reference frames from the original site and compare against the current implementation, even if the feature appears to be done
3. **Capture reference frames once, save to `tmp/frames-original/`** — never re-capture from the original site mid-iteration
4. **Capture implementation frames to `tmp/frames-ours/`** after each change
5. **Repeat until 100% visual match** — do not converge while any frame shows a discrepancy
6. All timing/easing/spacing values must come from extracted measurements — no guessing

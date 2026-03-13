# Changelog

## [1.0.0] - 2026-03-12

### Added
- **`ui-reverse-engineering`** — full pipeline skill: URL → DOM/CSS/JS extraction → responsive breakpoints → React + Tailwind component → visual verification
  - Step-by-step extraction: DOM structure, computed styles, CSS custom properties, responsive breakpoints, hover/click interactions, CSS keyframes, JS bundle analysis
  - Input modes: URL (primary), screenshot, video/screen recording, multiple screenshots
  - Generation prompt template with rules for exact text, colors, functional JS, image placeholders
  - Visual verification checklist with screenshot comparison loop
- **`transition-reverse-engineering`** — precise animation extraction sub-skill
  - CSS path (transitions, keyframes) and Canvas/WebGL path
  - WAAPI scrubbing for page-load animations that complete before capture
  - Frame-by-frame visual comparison workflow
  - Key pitfalls table (fill:forwards, CSS class GC, stagger flash, bot detection, etc.)
  - Supporting files: `css-extraction.md`, `canvas-webgl-extraction.md`, `patterns.md`, `waapi-scrub-inject.js`, `capture-frames.sh`

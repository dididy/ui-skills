# Changelog

## [0.0.2] - 2026-03-20

### Added
- **`transition-reverse-engineering`**: Step 0 — mandatory reference frame capture before classification (SKILL.md)
- **`transition-reverse-engineering`**: stagger with hidden parent — correct reveal order recipe; DOM restore, parent opacity, React effect cleanup troubleshooting entries (patterns.md)
- **`ui-reverse-engineering`**: three mandatory capture types (C1 static screenshots, C2 scroll video, C3 transition/interaction video) at 60 fps (visual-verification.md)
- **`ui-reverse-engineering`**: interaction detection results must be saved to `interactions-detected.json` (interaction-detection.md)
- **`ui-reverse-engineering`**: Phase A / Phase B gates — validation checks before proceeding to extraction or comparison (visual-verification.md, SKILL.md)

### Changed
- **`ui-reverse-engineering`**: SKILL.md pipeline diagram now includes Phase 1 (reference capture) with gate checks; sub-document references changed from "see X" to "Read X, execute"
- **`ui-reverse-engineering`**: visual-verification.md restructured — separate C1/C2/C3 comparison tables replace single frame table; 60 fps replaces 2 fps
- **`ui-reverse-engineering`**: component-generation.md prerequisites now block generation if artifacts are missing

### Fixed
- README.md: typo fix (`no치t` → `not`)
- **`transition-reverse-engineering`**: css-extraction.md — added missing HTTPS validation for stylesheet download (consistent with other download commands)
- **`transition-reverse-engineering`**: SKILL.md — added selector validation guidance for `window.__scrub.setup()`

## [0.0.1] - 2026-03-19

### Added
- **`ui-reverse-engineering`** — full pipeline skill: URL → DOM/CSS/JS extraction → responsive breakpoints → React + Tailwind component → visual verification
  - URL input: exact values via `getComputedStyle`, DOM inspection, JS bundle analysis
  - Screenshot/video input: accepted as fallback, analyzed via Claude Vision (approximation)
- **`transition-reverse-engineering`** — precise animation extraction sub-skill
  - CSS path (transitions, keyframes) and Canvas/WebGL path (engine detection, bundle grep)
  - WAAPI scrubbing (`waapi-scrub-inject.js` + `capture-frames.sh`) for page-load animations that complete before capture
  - Frame-by-frame visual comparison workflow with named scopes: `element` (cropped to target) and `fullpage` (entire transition window)

### Changed
- `ui-reverse-engineering`: split into focused reference files — `dom-extraction.md`, `style-extraction.md`, `interaction-detection.md`, `component-generation.md`, `visual-verification.md`; `SKILL.md` is now a slim index
- Responsive breakpoints now extracted from actual CSS `@media` rules; fixed values (375/768/1440) are fallback only

### Fixed
- `waapi-scrub-inject.js`: `cancelAll()` now uses `document.getAnimations()` (Chrome 84+/FF 75+/Safari 14+) instead of full DOM walk; `seek()` calls `pause()` before `currentTime` assignment to avoid `InvalidStateError` on finished animations; selector warns when 0 elements matched; default easing changed `ease` → `linear` with extraction note; `onComplete` → `onfinish` in comments
- `capture-frames.sh`: last frame clamped to `TOTAL_MS` to avoid integer-division drift; `seek` eval now an IIFE that checks `__scrub` presence and surfaces JS errors (exit code alone is unreliable); warning added when `frames=1`
- `css-extraction.md`: division-by-zero fixed in easing curve extraction when sampled array has 1 element
- `canvas-webgl-extraction.md`: Lottie detection narrowed from all `.json` to `lottie`/`bodymovin` only; `md5sum || md5` fallback pipes through `awk '{print $1}'` to strip filename suffix on Linux; framework-agnostic chunk patterns added (Nuxt/Vite/Remix)
- `interaction-detection.md`: HTTPS validation added before bundle download; `className` sanitized before storing in `__scrollTransitions`; retrieve eval falls back to `|| []`
- `visual-verification.md`: bare `agent-browser eval "window.scrollTo(0,0)"` → IIFE form; Phase A/B responsive blocks now re-open in a fresh session before viewport change
- `component-generation.md`: `@keyframes` placement covers Next.js App Router, Vite/CRA, Tailwind v3, and Tailwind v4
- `style-extraction.md`: removed over-filtering of `normal`/`auto` values that silently dropped `fontWeight: normal`, `margin: auto`, etc.
- `dom-extraction.md`: depth limit comment added (increase to 6–8 for deep component trees like shadcn/MUI)
- `patterns.md`: `to()` library example replaced with plain WAAPI; troubleshooting updated to `onfinish` + `anim.cancel()`
- `SKILL.md` (transition): install path uses `CLAUDE_SKILLS_DIR` env var; Bug Diagnosis snippet uses proper IIFE with semicolons

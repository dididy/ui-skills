# Changelog

## [0.0.10] - 2026-03-30

### Security
- **`ui-reverse-engineering`**: `component-generation.md` — "Use the EXACT text" rule replaced with untrusted data handling: all extracted text treated as data, not instructions. Prompt-like language rendered as literal display text only. New "Security: Extracted Content Handling" section added with explicit rules for DOM text, HTML comments, CSS content properties, `data-*` attributes, and prompt boundary markers.
- **`ui-reverse-engineering`**: `interaction-detection.md` — post-detection sanitization check added after `interactions-detected.json` save. Grep scan for prompt injection patterns (`ignore previous`, `system prompt`, `<script>`, `javascript:`, `data:text`); suspicious content logged and redacted.
- **`ui-capture`**: `SKILL.md` — Security section expanded from 3-line summary to full "Content Sanitization" section with 5 rules (untrusted data, directive rejection, eval output sanitization, no credential forwarding, cleanup) and explicit "What to ignore" checklist for captured content.
- **`ui-capture`**: `detection.md` — security note added: detection eval results (selectors, class names, attribute values) are classification data only, never instructions. Suspicious directive-like text in attributes redacted before saving to `regions.json`.
- **`transition-reverse-engineering`**: `css-extraction.md` — security note added: extracted CSS values treated as display values only. `javascript:` URIs and encoded payloads in custom property values logged and skipped.
- **`transition-reverse-engineering`**: `js-animation-extraction.md` — security note added: bundle analysis is read-only, never execute downloaded code. Directive-like text and suspicious encoded strings skipped.

### Changed
- `plugin.json`, `marketplace.json` — version bumped to 0.0.10.

## [0.0.9] - 2026-03-29

### Changed
- **`pixel-perfect-diff`** — restructured from "getComputedStyle-first" to "Visual Gate first, always-run-both" approach. Phase 1 (Visual Gate) is the primary pass/fail criterion using DOM clip screenshots + pixel diff (AE/SSIM). Phase 2 (Numerical Diagnosis via getComputedStyle) now always runs regardless of Phase 1 result — catches sub-pixel mismatches like `font-size: 15px vs 16px` and `letter-spacing` micro-differences that AE/SSIM passes. Gate: Phase 1 all pass AND Phase 2 mismatches = 0 (both required).
- **`pixel-perfect-diff`** — Visual Gate (Phase 1) captures per-element state: idle (all elements) + active (css-hover / js-class / intersection) + before/mid/after (scroll-driven). Active rect re-measured after state activation to handle `transform: scale()` and geometry-changing transitions. `mid` state catches easing curve mismatches (linear vs ease-in-out) that before/after alone would miss.
- **`pixel-perfect-diff`** — `scroll-driven` transitions now follow a two-phase approach: (1) exploration video to identify trigger_y / mid_y / settled_y, then (2) clip screenshot verification at those exact y positions. V3 clip commands, V4 diff loops, V6 JSON schema, and P2/P3 (Numerical Diagnosis) all updated for scroll-driven 3-state capture.
- **`pixel-perfect-diff`** — Phase 2 Numerical Diagnosis measures both idle and active states separately (`ref-styles-idle.json`, `ref-styles-active.json`). P3 Diff Table includes State column. Active measurement targets visual-change props (`color`, `backgroundColor`, `boxShadow`, `transform`, `opacity`, `filter`).
- **`pixel-perfect-diff`** — Visual Gate JSON schema: each element entry now includes `"state"` field (`"idle"`, `"active"`, `"before"`, `"mid"`, `"after"`).
- **`ui-capture`**: `capture-transitions.md` Step 2C — hover/js-class/intersection capture changed from video recording to eval + clip screenshot (idle + active states as static PNGs). CDP hover documented for CSS `:hover` cases.
- **`ui-capture`**: `capture-transitions.md` Step 2B — split into 2B-1 (exploration video, identifies trigger_y/mid_y/settled_y) and 2B-2 (clip screenshot verification at before/mid/after). Clip paths: `tmp/ref/capture/clip/{ref,impl}/`. Mid rect re-measured at each scroll position (scroll transforms change element bounds).
- **`ui-capture`**: `comparison-page.md` — Phase 4A renamed to "Pixel-Perfect Visual Gate". Gate requires both Visual Gate pass and mismatches = 0. Hover section: videos → paired idle/active clip screenshots. Scroll-driven section: paired before/mid/after clip screenshots added. Image paths updated to `clip/{ref,impl}/`. diff table columns: element, state, ae, ssim, status.
- **`ui-capture`**: `SKILL.md` — Phase 2C updated to eval + clip screenshot (no video). Phase 2B updated to 2-phase (exploration + clip). `--session` flag added to all Phase 1 commands. `clip/{ref,impl,diff}` directory added to setup block. Phase 4A gate updated.
- **`ui-reverse-engineering`**: `visual-verification.md` — A-C3 and B-C3 rewritten with triggerType dispatch: css-hover/js-class/intersection use eval + clip screenshot (idle + active), scroll-driven/mousemove/auto-timer retain video. C3 comparison table split into clip-diff and frame-comparison tracks. Phase D gate updated: Visual Gate all pass AND mismatches = 0.
- **`ui-reverse-engineering`**: `SKILL.md` — Phase D gate box and Principle 6 updated to Visual Gate framing. Step R GATE: "transition videos" → "transition captures (png or webm)". Reference Files updated.
- **`transition-reverse-engineering`**: `verification.md` — Pixel-Perfect Static State Diff updated to Visual Gate (clip screenshot + AE diff) with before/after capture commands. Both phases always run.
- **`transition-reverse-engineering`**: `SKILL.md` — Step 0 Option B scroll-driven updated to 2-phase (exploration video → clip at before/mid/after). Hover capture: full screenshot → clip screenshot (idle + active, CDP hover, rect re-measure). Step 4 GATE: Visual Gate all pass AND mismatches = 0.
- **`README.md`** — Shared Document section, trigger type table, and skill flow diagrams updated to reflect clip-screenshot approach and always-run-both behavior.
- **`mousemove` and `auto-timer` remain video-only** — no capture method change; only css-hover/js-class/intersection (eval + clip) and scroll-driven (2-phase) changed.
- **`plugin.json`**, **`marketplace.json`** — version 0.0.9; description updated to reflect always-run-both and scroll-driven 2-phase; keywords updated.
- **Consistency fixes** — `capture-transitions.md` Step 2B-2 "4개 상태" corrected to "3개 상태" (before/mid/after); all clip screenshot paths in Step 2C unified to `clip/{ref,impl}/` (was incorrectly `transitions/{ref,impl}/`); `compare` command paths in `visual-verification.md` and `verification.md` prefixed with correct `tmp/ref/<component>/`; Phase D and Step 4 gate wording updated to cover all state variants (idle / active / before / mid / after).

## [0.0.8] - 2026-03-28

### Added
- **`ui-capture`**: `SKILL.md` — `agent-browser` session rule added. Named `--session <project-name>` is now required on every `agent-browser` command. The default session is global and shared; without a name, commands from other projects overwrite browser state mid-capture.
- **`transition-reverse-engineering`**: `SKILL.md` — same session rule added as a top-of-file callout.
- **`ui-reverse-engineering`**: `SKILL.md` — same session rule added as a top-of-file callout.

### Changed
- **`ui-capture`**: `evals/evals.json` — evals 17–18 added: timestamp-based crop for deep sections (hero footage bleed case), and named session requirement across all agent-browser commands. eval 11 expectation updated to reference timestamp crop method (stdev-only reference removed).

### Fixed
- **`ui-capture`**: `capture-transitions.md` — scroll crop logic rewritten. The previous stdev > 8 method only stripped blank frames but left hero footage at the start of deep-section clips. Correct approach is timestamp-based: record start at t=0, wait for page load (~3 s), note wall-clock offset before scroll command, then use that timestamp as the ffmpeg crop point. Old stdev Python snippet removed and replaced with explicit SCROLL_T variable pattern.

## [0.0.7] - 2026-03-27

### Added
- **`pixel-perfect-diff`** — new shared verification document (not a registered skill). Mandatory numerical gate invoked by all three skills. Measures every key element with `getComputedStyle` on both reference and implementation across typography, spacing, sizing, layout, visual, and position properties. Produces `pixel-perfect-diff.json` with `"result": "pass"` and `"mismatches": 0` as the only valid PASS state. "Looks the same" is not a valid completion criterion.
- **`ui-reverse-engineering`**: `evals/evals.json` — evals 26–27 added: pixel-perfect pass scenario (P1–P6 artifact chain), and mismatch found and fixed (targeted re-measurement, no full rewrite).
- **`transition-reverse-engineering`**: `evals/evals.json` — evals 20–21 added: pixel-perfect diff for before/after resting states, and "close enough" rejection with exact pixel fix.
- **`ui-capture`**: `evals/evals.json` — evals 15–16 added: Phase 4A standalone pass scenario, and mismatches fixed before compare.html generated.

### Changed
- **`ui-reverse-engineering`**: `SKILL.md` — Step 8 Visual Verification restructured into Phase A (reference capture), Phase B (impl capture), Phase C (frame comparison tables C1/C2/C3), and Phase D (pixel-perfect numerical diff via `pixel-perfect-diff.md`). Gate now requires ALL of C1/C2/C3 ✅ AND `pixel-perfect-diff.json` `"result": "pass"`, `"mismatches": 0`. Principle 6 added: "Numerical match, not visual match."
- **`ui-reverse-engineering`**: `visual-verification.md` — Phase D section added: explains what screenshot comparison cannot catch (font-size, font-weight, padding, height within ~10%), requires `pixel-perfect-diff.md` P1–P6 for each major section. Completion gate updated to `C1 ✅ AND C2 ✅ AND C3 ✅ AND Phase D "mismatches": 0`.
- **`ui-capture`**: `SKILL.md` — Phase 4 renamed to "Phase 4: Pixel-Perfect Diff + Comparison Page". Phase 4A (pixel-perfect-diff.md P1–P6 for every major section, gate before compare.html) added before Phase 4B (compare.html generation). Reference Files ordering corrected (pixel-perfect-diff.md listed as Phase 4A, comparison-page.md as Phase 4A gate + Phase 4B).
- **`ui-capture`**: `comparison-page.md` — Phase 4A section added with gate checklist; diff table CSS (`.diff-table`, `.diff-pass`, `.diff-fail`, `.diff-summary`) added to compare.html structure; pixel-perfect diff table embedded at top of compare.html before video sections.
- **`ui-capture`**: `evals/evals.json` — eval 6 `expected_output` updated to reflect Phase 4A requirement; duplicate key removed.
- **`transition-reverse-engineering`**: `SKILL.md` — Step 4 Verify now requires `pixel-perfect-diff.md` P1–P6 for resting states (before + after animation). Gate adds `pixel-perfect-diff.json` `"result": "pass"`, `"mismatches": 0`.
- **`transition-reverse-engineering`**: `verification.md` — "Pixel-Perfect Static State Diff (MANDATORY)" section added. Gate updated to require both `"result": "pass"` and `"mismatches": 0` (before + after states). Checklist item updated to match full two-condition form.
- `README.md` — intro framing corrected from "four skills" to "three skills + one shared verification document"; `pixel-perfect-diff` section header renamed from "Skill 4" to "Shared Document"; Security and Evals sections updated accordingly; flow diagrams updated for all three skills.
- `plugin.json` and `marketplace.json` — version bumped to 0.0.7; description updated to mention pixel-perfect numerical verification; keywords added (`pixel-perfect`, `getComputedStyle`, `numerical-diff`, `css-verification`).

## [0.0.6] - 2026-03-25

### Fixed
- **`ui-capture`**: `detection.md` — trigger-type classification table added before detection script. Each region now tagged with `triggerType` (`css-hover`, `js-class`, `intersection`, `scroll-driven`, `mousemove`, `auto-timer`). Wrong trigger type previously caused blank recordings.
- **`ui-capture`**: `detection.md` — `:hover` stylesheet scan integrated into detection script; `regions.json` schema updated with `triggerType` and `triggerClass` fields; example schema updated to show all three trigger types
- **`ui-capture`**: `capture-transitions.md` — documented `record start` fresh-context behavior (resets scroll to y=0 regardless of pre-scroll); correct pattern requires scroll AFTER `record start` + viewport re-set + verify screenshot
- **`ui-capture`**: `capture-transitions.md` — blank start crop script added (python3 stdev threshold to find first content frame); all capture sequences now use trigger-type-specific activation instead of generic hover
- **`ui-capture`**: `comparison-page.md` — video sync rewritten: `busy` flag prevents recursive play loops; `!a.ended` guard on pause listener prevents buffering events from halting playback; `seeked` events added for scrub sync; `ended` event no longer pauses the paired video (each plays to its own end)
- **`ui-capture`**: `SKILL.md` — 2D description updated to "mousemove raster-path video (10×10 grid sweep, single video per element)"; added trigger-type classification note before 2B–2E; 4 common failure rows added (wrong scroll position in recording, blank start, pause/play loop, shorter video stopping longer)

### Changed
- **`ui-capture`**: `SKILL.md` description updated — removed "cursor-position matrices" phrasing, simplified to "interactive animations"
- **`ui-capture`**: `SKILL.md` Phase 1 full scroll video now issues `record start` first, then scrolls (consistent with `record start` fresh-context rule)
- **`ui-capture`**: `SKILL.md` Phase 2C description expanded — "hover in/hold/out" → lists all 3 trigger types covered (css-hover, js-class, intersection)
- **`ui-capture`**: `SKILL.md` Phase 3 — removed stale "10×10 matrix → matrix/impl/" line; removed `matrix/` from Phase 1 directory setup (mousemove output is a video in `transitions/`, not a separate matrix directory)
- **`ui-capture`**: `SKILL.md` Phase 4 — removed "10×10 matrix grids" from comparison page description
- **`ui-capture`**: `comparison-page.md` — Matrix comparison section replaced with Cursor-reactive section using paired raster-path videos; removed `.matrix-grid` CSS; updated HTML comment
- **`ui-capture`**: `capture-transitions.md` Step 2E — fixed scroll-before-record bug: scroll now happens AFTER `record start` + viewport set + page load wait
- **`ui-capture`**: `detection.md` — detection script now tags ALL result types with `triggerType`: scroll (`scroll-driven`), mousemove (`mousemove`), timer (`auto-timer`); timer entries now include `interval_ms` estimated from `data-autoplay-speed`/`data-interval`/`data-delay` attributes (fallback 3000ms); regions.json schema example updated with triggerType in all arrays and a populated timer example
- **`ui-capture`**: `evals/evals.json` — eval 9 scroll/mousemove/timer array expectations updated with correct field names and triggerType values; eval 4 expected_output updated to `transitions/ref/` path (no matrix directory); eval 13 added for intersection trigger capture; eval 14 (was 13) renumbered
- plugin.json and marketplace.json updated, version bumped to 0.0.6; added keywords `trigger-type-detection`, `video-sync`

## [0.0.5] - 2026-03-24

### Added
- **`ui-capture`** — new skill for capturing baseline screenshots and transition videos from reference URLs. Detects scroll, hover, mousemove, and auto-timer transitions. Generates web-based comparison page (original vs clone) with synchronized video playback and 10×10 cursor-reactive matrix grids *(mousemove capture replaced with single raster-path video in 0.0.6)*. Includes error handling for bot detection, hydration delays, and lazy-loaded content.
- **`ui-capture`**: `evals/` directory with trigger-eval.json and evals.json
- **`ui-capture`**: `detection.md`, `capture-transitions.md`, `comparison-page.md` — phase implementation split out from SKILL.md following other skills' convention

### Changed
- **`ui-reverse-engineering`**: Phase A (reference capture) and Phase 4 (verification) now delegate to `/ui-capture` instead of executing visual-verification.md directly. visual-verification.md marked as deprecated.
- **`ui-reverse-engineering`**: Added `ui-capture` as a sub-skill in Reference Files section
- **`transition-reverse-engineering`**: Step 0 (capture reference frames) now offers `/ui-capture` as Option A for fullpage scope. Step 4 (verify) can delegate to `/ui-capture` for comparison.
- **`ralph-kage-bunshin-start`**: UI Clone Detection now invokes `/ui-capture` for baseline capture + web-based user confirmation before task generation
- **`ralph-kage-bunshin-loop`**: DoD visual regression check now invokes `/ui-capture` for impl capture and comparison
- plugin.json and marketplace.json updated to include ui-capture, version bumped to 0.0.5

## [0.0.4] - 2026-03-22

### Added
- **`transition-reverse-engineering`**: `js-animation-extraction.md` — new extraction path for JS-driven animations (scroll-driven, Motion, GSAP, rAF). Covers JS chunk identification, minified pattern decoding (useTransform/useScroll keyframes, interpolation ranges, scroll offsets), raw CSS stylesheet extraction for responsive units (`calc()`, `cqw`, `%`, custom properties), and 4 documented pitfalls (computed-only extraction, transform:none false negative, wrapper-vs-children scale, once-vs-toggle)
- **`transition-reverse-engineering`**: `canvas-webgl-extraction.md` — Rive/Spline/Lottie interactive extraction: scene URL extraction, state machine input detection via bundle grep (SMIBool/SMITrigger/SplineEventName/playSegments), interactive state capture (hover/click reference frames), and extracted.json schema for engine/interactions/playback

### Changed
- **`transition-reverse-engineering`**: SKILL.md — added core principles 8 (getComputedStyle limitation) and 9 (raw CSS over computed values); process flow now has 3 extraction paths (CSS / JS Animation / Canvas) instead of 2 (CSS / Canvas); Effect Classification adds JS Animation Path with CRITICAL warning that scroll-driven effects must use JS bundle analysis; Reference Files updated with js-animation-extraction.md
- README.md — transition-RE description includes scroll-driven JS animations; "When to Use" adds Motion/GSAP/rAF; process diagram shows Step 2a/2b/2c; Supported Animation Types adds scroll-driven and CSS-in-JS responsive layout rows

### Security evals
- **`ui-reverse-engineering`**: `evals/evals.json` — 3 security evals added (id 23–25): prompt injection in extracted DOM, suspicious bundle patterns, post-completion cleanup
- **`transition-reverse-engineering`**: `evals/evals.json` — 2 security evals added (id 18–19): suspicious bundle patterns, prompt injection in measurement data

### Security
- **`ui-reverse-engineering`**: Added Security section to SKILL.md — content boundary rules, prompt injection defense, bundle execution prohibition, credential forwarding prohibition, cleanup policy, and suspicious content handling
- **`ui-reverse-engineering`**: `dom-extraction.md` — post-extraction sanitization check scans `structure.json` for prompt injection patterns
- **`ui-reverse-engineering`**: `style-extraction.md` — post-extraction sanitization check scans `styles.json` for suspicious CSS values (`javascript:`, `expression()`, `data:text`)
- **`ui-reverse-engineering`**: `interaction-detection.md` — bundle sanitization check before analysis, security reminder that bundle analysis is read-only
- **`ui-reverse-engineering`**: `component-generation.md` — prompt boundary markers (`═══ BEGIN/END EXTRACTED DATA ═══`) wrap all untrusted content passed to generation, with explicit instruction to never interpret extracted text as directives
- **`transition-reverse-engineering`**: Added Security section to SKILL.md — untrusted data handling, bundle execution prohibition, credential forwarding prohibition, cleanup policy
- **`transition-reverse-engineering`**: `canvas-webgl-extraction.md` — bundle sanitization check after download, security reminder for read-only analysis
- **`transition-reverse-engineering`**: `css-extraction.md` — security comment on stylesheet curl analysis
- **`transition-reverse-engineering`**: `waapi-scrubbing.md` — security note clarifying scrubber injection context (trusted local script into remote page)
- **`transition-reverse-engineering`**: `measurement.md` — security note on treating `getComputedStyle` measurement data as untrusted
- **`ui-reverse-engineering`**: `responsive-detection.md` — security note on `node -e` JSON parsing from untrusted extraction data
- **`ui-reverse-engineering`**: `visual-verification.md` — post-completion cleanup step (`rm -rf tmp/ref/`) to remove sensitive data
- **`ui-reverse-engineering`**: `component-generation.md` — "EXACT text" rule clarified: directive-like text is rendered literally, never followed
- **`ui-reverse-engineering`**: `interaction-detection.md` — fixed grep regex syntax (`\|` → `|` for ERE mode with `-iE`)
- `README.md` — added Security section summarizing built-in mitigations
- `.claude-plugin/plugin.json` and `marketplace.json` — version bumped to 0.0.4

## [0.0.3] - 2026-03-21

### Added
- **`ui-reverse-engineering`**: `evals/evals.json` — 22 functional evals (137 expectations) covering all documented features: static clone, interactions (hover/click/scroll/auto-timer), responsive sweep, screenshot/video input, multi-section pages, overlay dismissal, SPA loading, Canvas/WebGL branching, JS bundle analysis, CORS fallback, fix protocol, CSS custom properties, @keyframes extraction, resize video, component self-containment, and partial extraction (single-section, hidden-element, multi-section)
- **`ui-reverse-engineering`**: `evals/trigger-eval.json` — 30 trigger evals (16 true / 14 false)
- **`transition-reverse-engineering`**: `evals/evals.json` — 17 functional evals (105 expectations) covering all documented features: hover CSS, WAAPI stagger, scroll parallax, Three.js particles, CSS @keyframes, modal spring overshoot, hybrid CSS+Canvas, Rive, Lottie, Spline, multi-line globalCharIndex stagger, scroll reverse direction, fix protocol, capture-frames.sh validation, children cascade, WAAPI recovery, and post-implementation capture
- **`transition-reverse-engineering`**: `evals/trigger-eval.json` — 25 trigger evals (13 true / 12 false)
- **`transition-reverse-engineering`**: `measurement.md` — mandatory Step -1: 11-point multi-property measurement pass (hover, page-load, scroll-driven). Reveals multi-phase timing and non-linear curves before implementation
- **`transition-reverse-engineering`**: `verification.md` — visual verification & bug diagnosis protocol extracted from SKILL.md. Includes scope-specific comparison tables (element vs fullpage), root-cause-first diagnosis protocol, and "Is This Done?" checklist
- **`transition-reverse-engineering`**: `waapi-scrubbing.md` — WAAPI scrubber injection procedure extracted from SKILL.md. Includes 3-level path fallback (CLAUDE_SKILLS_DIR → git root → ~/.claude/skills)
- **`ui-reverse-engineering`**: `responsive-detection.md` — Step 4: auto-detect real breakpoints via 2-pass viewport sweep (coarse 40px → fine 5px) instead of hardcoded 375/768/1440. Includes per-breakpoint style extraction, responsive verification (A-R/B-R/C-R), and resize video capture
- **`ui-reverse-engineering`**: Step 5b (deferred C3 capture) and Step 6b (assemble extracted.json) in SKILL.md pipeline

### Changed
- **`transition-reverse-engineering`**: SKILL.md restructured — gated step flow (Step -1 → 0 → 1 → 2 → 3 → 4) with explicit gates at each step; principles 6–7 added (measure all properties at multiple points, never assume linearity)
- **`transition-reverse-engineering`**: css-extraction.md — critical warning now references measurement.md instead of duplicating the rationale
- **`ui-reverse-engineering`**: SKILL.md — C1+C2 mandatory in Phase 1, C3 deferred to Step 5b (needs interaction data); breakpoints output changed from fixed `375/768/1440` to `{ "detected": [...], "tailwind": {...} }`
- **`ui-reverse-engineering`**: style-extraction.md — removed orphaned Step 4 section (now a one-line pointer to responsive-detection.md)
- **`ui-reverse-engineering`**: visual-verification.md — A-C3 explicitly marked as deferred to Step 5b; A-R deferred to Step 4
- **`ui-reverse-engineering`**: SKILL.md — added "Partial extraction" section with 4 scope types (single-section, multi-section, single-element, hidden-element), per-scope pipeline adjustments, and artifact naming conventions
- **`ui-reverse-engineering`**: SKILL.md description updated — trigger-oriented phrasing with typical request examples and explicit NOT-trigger conditions
- Eval files placed in per-skill `skills/*/evals/` directories (skill-creator convention)
- `.gitignore` — added `ui-skills-workspace/` for eval run artifacts
- README.md — pipeline diagram updated with Steps 5b/6b, viewport sweep description, transition-RE process overview, and eval coverage section
- `.claude-plugin/plugin.json` and `marketplace.json` — version bumped to 0.0.3; description updated with viewport sweep and 11-point measurement; added keywords (`breakpoint-detection`, `viewport-sweep`, `visual-verification`, `waapi`)

### Fixed
- **`transition-reverse-engineering`**: verification.md — removed Phase B/C terminology (belongs to ui-RE, not transition-RE)
- **`transition-reverse-engineering`**: measurement.md — scroll-driven example replaced overly specific placeholders (`<ring-group-selector>`) with generic pattern + explicit "adapt selectors" guidance
- **`transition-reverse-engineering`**: waapi-scrubbing.md — SKILL_DIR fallback now searches git root and env var, not just `~/.claude/skills`
- **`ui-reverse-engineering`**: SKILL.md Reference Files — `visual-verification.md` now listed as "Steps 8–9" (was "Step 8" only)
- **`transition-reverse-engineering`**: verification.md — SVG `className` now uses `.baseVal` fallback (consistent with dom-extraction.md, interaction-detection.md, css-extraction.md)
- **`ui-reverse-engineering`**: responsive-detection.md — Pass 1 coarse sweep now checks and re-registers `__responsiveMeasure` if page reloads mid-sweep (previously only Pass 2 had this guard)

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

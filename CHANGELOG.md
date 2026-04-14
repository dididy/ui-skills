# Changelog

## [0.2.0] - 2026-04-14

### Added
- **`visual-debug` skill** — Automated visual comparison between original site and implementation using AE/SSIM diff. **Zero vision tokens** — never reads images with LLM for comparison. Only reads diff images when AE reports a FAIL. Includes 4 scripts:
  - `batch-scroll.sh` — captures both original and implementation at identical scroll positions (0%-100%)
  - `ae-compare.sh` — compares two images, outputs AE score + identifies worst region (top/middle/bottom)
  - `batch-compare.sh` — compares all captured pairs, outputs markdown table of scores
  - `computed-diff.sh` — compares `getComputedStyle` values between original and implementation for specified selectors
- **Raw HTML Injection approach** (`site-detection.md`) — New implementation strategy for complex sites with CSS Modules, GSAP, Lottie, Canvas, or 200KB+ HTML. Extracts raw `outerHTML` per section, serves original CSS files from `/public/css/`, renders via `dangerouslySetInnerHTML`. Documents the critical "wrapper div problem" (extra `<div>` between parent and child breaks CSS Module selectors) and the "GSAP inline style cleanup" problem (layout values like `height: 500svh` must be preserved while animation values like `transform: rotateY(-180deg)` must be removed).
- **`extract-dynamic-styles.sh`** — Classifies inline styles as layout (height/width in svh/vh — KEEP) vs animation (transform/opacity/visibility — REMOVE). Prevents the #1 debugging issue: cleaning all GSAP inline styles removes layout heights, causing sections to collapse to 0px.
- **`validate-gate.sh` `dynamic-heights` gate** — Detects when scroll sentinels or sections have lost their `svh`/`vh` height values after GSAP cleanup. Warns about layout values that must be re-set by ClientShell JS.
- **`visual-debug` trigger evals** — 15 test cases (10 positive, 5 negative) for skill activation.
- **Parallel worktree builders** — Phase 3 generation splits into 3A (foundation, sequential) → 3B (section builders, parallel via Agent tool with worktree isolation) → 3C (assembly, sequential). 2-3x faster on pages with 4+ sections. Falls back to sequential if Agent tool unavailable.
- **Self-healing error loop (Phase H)** — When Phase D verification fails, defects are automatically classified by category (LAYOUT/COLOR/TYPOGRAPHY/ANIMATION/CONTENT) and severity (CRITICAL/MAJOR/MINOR), then fixed in priority order with minimal targeted edits. Re-verifies after each iteration. Max 3 cycles before escalating with structured defect report.
- **Click sweep** — `ui-capture` Phase 2 now detects and captures click-toggle (accordions, dropdowns, toggles) and click-cycle (tabs, pills) interactions. Detects via `aria-expanded`, `role="tab"`, `data-state`, `<details>`. Captures idle/active per toggle, per-state screenshots for tab cycles. Deduplicates against existing hover candidates.
- **`interaction-detection.md`** — `click-toggle` and `click-cycle` trigger types added to signal table.
- **`transition-implementation.md`** — React implementation patterns for click-toggle (useState + CSS transition) and click-cycle (activeIndex + tabpanel) with exact extracted values.
- **`visual-verification.md`** — Phase D comparison now includes click-toggle (idle/active) and click-cycle (state-0..N) states.

### Changed
- **`visual-debug` absorbs `visual-verification.md` + `pixel-perfect-diff.md`** — All visual verification is now in one place. `visual-debug/verification.md` contains the full Phase A/B/C/D/H/E procedure (formerly `ui-reverse-engineering/visual-verification.md`). `pixel-perfect-diff.md` and `visual-verification.md` are now redirect stubs. All cross-skill references updated.
- **`site-detection.md`** — Implementation Approach Gate added (MANDATORY before writing code). Detection script checks CSS Module ratio, JS animation library count, inline style count, and total HTML size. Decision matrix routes to Raw HTML Injection or React Component approach.
- **`plugin.json`** — `visual-debug` added to skills list.
- **Scripts JSON output** — `compare-sections.sh`, `validate-gate.sh`, `download-chunks.sh`, `section-clips.sh`, `extract-section-html.sh`, `extract-assets.sh` now output structured JSON: `{status, phase, data, defects, errors, duration_ms}`. Human-readable output moved to stderr. Exit codes unchanged — fully backward-compatible with existing SKILL.md flows.
- **`compare-sections.sh`** — Layer 3 style mismatches now include `category` (LAYOUT/COLOR/TYPOGRAPHY/ANIMATION/CONTENT) and `severity` (CRITICAL/MAJOR/MINOR) classification. Defect list written to `comparison-output.json` for self-healing loop consumption.
- **`validate-gate.sh`** — JSON output includes gate name, failed check count, and missing file list. New `dynamic-heights` gate added.

### Fixed
- `extract-dynamic-styles.sh` missing from `skills/ui-reverse-engineering/scripts/` (only existed in root `scripts/`)
- `validate-gate.sh` out of sync between root `scripts/` and `skills/ui-reverse-engineering/scripts/`
- `visual-debug` SKILL.md script paths used bare `scripts/` without `PLUGIN_ROOT` resolution
- `site-detection.md` referenced `extract-dynamic-styles.sh` without `PLUGIN_ROOT` path
- Visual verification scattered across 3 locations (visual-verification.md, pixel-perfect-diff.md, visual-debug) — now consolidated into `visual-debug`

## [0.1.1] - 2026-04-13

### Added
- **`style-extraction.md`** — **섹션 높이/간격 추출 필수 규칙.** 페이지 레벨 레이아웃(섹션별 높이, flex/grid gap, padding)을 반드시 추출하도록 명시. 실제 세션에서 flex container의 `gap: 234px`를 누락해 구현 전체 높이가 957px 짧아진 사례를 기반으로 추가.
- **`visual-verification.md`** — **섹션 정렬 비교 필수 규칙.** 원본과 구현의 섹션별 top offset을 비교해 50px 이상 차이 시 spacing 버그로 판단. 같은 스크롤 위치에서 다른 콘텐츠가 보이는 문제를 방지.
- **`visual-verification.md`** — **원본 SVG/에셋 추출 필수 규칙.** placeholder SVG 생성을 금지하고, DOM에서 원본 SVG outerHTML을 직접 추출하도록 명시. footer 로고(460×171 viewBox)를 placeholder 타원으로 대체했다가 3회 수정한 사례 기반.
- **`visual-verification.md`** — **Tailwind arbitrary value 호환성 체크.** `px-[19px]` 등 arbitrary value가 렌더링 후 `0px`이면 inline style로 대체하도록 안내. Tailwind v4에서 무시되어 전체 padding이 0이 된 사례 기반.
- **`interaction-detection.md`** — **프리로더/스플래시 JS 번들 분석 필수 규칙.** DOM 구조만으로 프리로더를 구현하지 않고, 커스텀 JS 파일을 다운로드하여 GSAP 타임라인, CustomEase, 전용 이미지, sessionStorage 게이팅을 추출하도록 명시. DOM의 `display:none` 상태만 보고 전체 화면 이미지 blur로 구현했다가, 실제로는 209×261px 중앙 박스 + 파란색(#050fff) clip-path + 8개 전용 이미지였던 사례 기반.
- **`component-generation.md`** — **폰트 사이즈 정확도 규칙 (#1 사용자 피드백).** 추출된 computed value를 그대로 사용하고, 반올림/근사치를 금지. 40px를 18px로 구현하여 반복 수정한 사례 기반.

### Fixed
- 섹션 간 간격을 추출하지 않아 스크롤 위치가 맞지 않는 문제
- placeholder SVG로 에셋을 대체하여 원본과 다른 문제
- Tailwind v4에서 arbitrary px value가 무시되는 문제 진단 누락
- 프리로더 애니메이션을 DOM만 보고 추측하여 원본과 다른 문제
- 폰트 사이즈를 근사치로 설정하여 반복 수정이 필요한 문제

## [0.1.0] - 2026-04-12

### Breaking Changes
- **CSS-First generation is now the default strategy.** Instead of extracting computed values and re-implementing with Tailwind/inline styles, the skill now downloads original CSS files and uses original class names in JSX. This produces pixel-perfect results but requires readable CSS class names (Shopify, WordPress, static sites). For obfuscated CSS (Tailwind, CSS-in-JS), falls back to the extract-values strategy.

### Added
- **`site-detection.md`** — Auto-detects site tech stack (Shopify/WordPress/Next.js/Tailwind/CSS-in-JS) at Step 1 and selects CSS-First or Extract-Values strategy. Prevents applying the wrong extraction approach.
- **`transition-implementation.md`** — Complete bundle → code translation guide. ScrollTrigger progress formulas, easing conversion table (power1-5 → cubic-bezier), splash/intro animation timing pattern (handles cached vs uncached video), sticky + overflow conflict pre-check, performance patterns (refs vs useState, will-change, passive listeners).
- **`run-pipeline.sh`** — State machine orchestrator. Detects current phase by checking which artifacts exist in `tmp/ref/`, prints exactly what to do next. Prevents skipping steps or guessing which phase you're in. Phases: 0-init → 1-capture → 2-extract → 2.5-css → 2.6-vars → 3-pregen → 4-generate → 5-verify.
- **`extract-assets.sh`** — Downloads video backgrounds, Typekit/Adobe Fonts, and CDN font files. Extracts static video frame as poster fallback. Solves "implementation uses static image but original has video background" mismatch.
- **`extract-section-html.sh`** — Per-section HTML structure + computed CSS + media element extraction. Produces the ground truth for code generation: element hierarchy, computed styles, video/img attributes.
- **`dom-extraction.md`** — Step 2.5: Download original CSS files (MANDATORY). Step 2.6: Extract and preserve CSS variables to `variables.txt` before `:root` cleanup. Download video backgrounds with `<video>` attribute detection. Download Typekit/Adobe Fonts via CSS URL extraction.
- **`component-generation.md`** — CSS-First Generation section: download CSS → import in project → use original class names in JSX. Original CSS + React structure conflict resolution (height override, transform conflicts, z-index stacking). Auto-detect missing assets (grep `url()` in CSS, verify local existence). CSS variable consistency rule (match computed values, not just defined values).
- **`visual-verification.md`** — Content-anchored screenshot alignment (use text anchors, not y-coordinates). ScrollTrigger progress-based comparison for pinned sections. Anti-pattern rule: "looks close enough" phrases banned, `getComputedStyle` numerical comparison required.
- **`validate-gate.sh`** — `pre-generate` gate: verifies original CSS files exist, CSS variables extracted to `variables.txt`, background image assets downloaded. `post-implement` gate: transition coverage checklist from `transition-spec.json`. Section-clip SSIM comparison with Layer 3 `getComputedStyle` diff.
- **`compare-sections.sh`** — Layer 3: `getComputedStyle` numerical comparison. Reads `clips/ref/styles.json` and `clips/impl/styles.json`, outputs per-property mismatches with exact selector + property + ref/impl values. Tells you exactly what CSS property to fix instead of showing a vague diff image.
- **`section-clips.sh`** — Per-section + per-element screenshot capture for targeted comparison.

### Changed
- **`SKILL.md`** — Process flow: `run-pipeline.sh status` is now the FIRST action before any work. Step 7 reads `site-detection.md` first, then `component-generation.md` + `transition-implementation.md`. Reference Files section updated with new documents.
- **`component-generation.md`** — "Transitions are NOT separate from generation" (HARD RULE). Transition coverage gate moved here from post-verification. Section HTML + ref screenshot must be Read before writing each component.
- **`dom-extraction.md`** — Step 2.6 added (per-section HTML structure extraction via `extract-section-html.sh`).

### Fixed
- CSS `:root` variables lost when cleaning downloaded CSS — now extracted to `variables.txt` before cleanup
- `overflow: hidden` silently breaking `position: sticky` — now detected as pre-implementation check
- Agent declaring "almost matches" without numerical verification — banned phrases + mandatory `getComputedStyle` comparison
- Background images not downloaded for showcase/product sections — auto-detected via `url()` grep in original CSS
- Splash animation expanding too fast when video is cached — reliable timing pattern with minimum 1s visibility

## [0.0.18] - 2026-04-11

### Added
- **`ui-reverse-engineering`**: `style-extraction.md` — **Global overlay scan** section. Detects full-page texture overlays (`position: fixed; pointer-events: none; z-index > 100`) such as film grain, noise patterns, and paper textures. Extracts `background-image`, `background-size`, `mix-blend-mode`, and `opacity`. These overlays are easy to miss during extraction but produce a noticeably "too clean" implementation when omitted.
- **`ui-reverse-engineering`**: `component-generation.md` — **"Do not invent interactions"** reminder. Explicitly prohibits adding hover transforms, opacity transitions, or other effects that were not observed in the reference extraction. Extends the existing "no guessing values" rule to cover interaction behavior.
- **`ui-reverse-engineering`**: `dom-extraction.md` — **Font download** section in Step 2.5. Extracts all `@font-face` rules from stylesheets, downloads woff2 files, and saves `fonts.json`. Missing fonts cause fallback to system fonts with different glyph metrics, producing cascading layout differences (wrong text width → wrong wrapping → wrong element positions) that are impossible to fix with CSS alone.
- **`ui-reverse-engineering`**: `SKILL.md` — Step 2.5 checkpoint updated to require `fonts.json` and downloaded font files.
- **`ui-reverse-engineering`**: `dom-extraction.md` — **Generation rules for downloaded assets.** Explicit instructions for applying favicon (add `<link rel="icon">` in HTML head) and images (copy to public directory). Previously, assets were downloaded but no rule specified how to wire them into the implementation.

### Changed
- **`pixel-perfect-diff.md`** merged into `ui-reverse-engineering/visual-verification.md` Phase D. The standalone file now redirects to the merged location. Other skills (`transition-reverse-engineering`, `ui-capture`) that reference `../pixel-perfect-diff.md` will see the redirect notice.

## [0.0.17] - 2026-04-11

### Added
- **`ui-reverse-engineering`**: `interaction-detection.md` — **Step 6b: Transition Spec Document** (new section). After bundle analysis, produce `bundle-map.json` (chunk → feature mapping) and `transition-spec.json` (per-transition spec with trigger, target, easing, duration, bundle branch, reference frames). Single source of truth for implementation — eliminates re-grepping bundles during fixes.
- **`ui-reverse-engineering`**: `interaction-detection.md` — **ALL loaded chunks download** via `performance.getEntriesByType('resource')`. Replaces single main.js download. Lazy chunks contain page-specific transition logic (bookmark animations, scroll triggers, component transitions).
- **`ui-reverse-engineering`**: `component-generation.md` — **HARD BLOCK on transition-spec.json**: generation step refuses to proceed without it. Includes "Using transition-spec.json during implementation" protocol (5 steps).
- **`ui-reverse-engineering`**: `component-generation.md` — **Mandatory comparison after each transition implementation**: screenshot original + impl at same state, compare before moving on. Max 3 cycles per transition.
- **`ui-reverse-engineering`**: `evals.json` — 5 new evals (31–35) covering: conditional branch verification, lazy chunk discovery, spec re-loading on re-invocation, frames-before-implementation, per-transition comparison loop.
- `scripts/validate-gate.sh` — **Bash gate enforcement script**. 4 gates: `bundle` (ALL chunks + element-animation-map), `spec` (transition-spec.json + bundle-map.json structure validation), `pre-generate` (all extraction artifacts + reference frames), `post-implement` (comparison screenshots exist). Exits with code 1 on failure — hard blocks proceeding.
- `scripts/download-chunks.sh` — **Automated chunk download + analysis**. Takes URL list (JSON array or newline), downloads all chunks, detects animation libraries (GSAP, Lenis, ScrollTrigger, SplitText, Framer Motion), extracts transition-related selectors, produces `bundle-analysis.json` + skeleton `bundle-map.json`.
- `scripts/gsap-to-css.sh` — **GSAP easing → CSS cubic-bezier converter**. Single lookup (`power5` → `cubic-bezier(0.05, 0.86, 0.09, 1)`), full table (`all`), or bundle scan (`scan file.js` finds all ease values and converts).
- **`ui-reverse-engineering`**: `SKILL.md` — **Phase 0: Load Existing Analysis**. On re-invocation, check for `transition-spec.json` / `bundle-map.json` and load immediately. Prevents redundant re-extraction.
- **`ui-reverse-engineering`**: `SKILL.md` — **Step 5d: Transition Spec** gate in process flow. `bundle-map.json` + `transition-spec.json` must exist before proceeding to animation detection.
- **`ui-reverse-engineering`**: `animation-detection.md` — AE diff curve analysis, GSAP timeline position parser, conditional branch detection, fixed overlay cleanup protocol.
- **`ui-reverse-engineering`**: `component-generation.md` — failure-based diagnosis entries, CSS multi-step limitation, package rebuild requirement.
- **`ui-reverse-engineering`**: `animation-detection.md` — **3-tier idle frame analysis**: Tier 1 AE diff (zero tokens, finds WHEN changes happen), Tier 2 DOM polling (zero tokens, finds WHAT elements change with exact timestamps), Tier 3 LLM Read (minimal tokens, only for transition boundaries that automation can't classify). Replaces "Read consecutive frame pairs" which consumed ~260K tokens for 104 frames. Expected usage: ~10K tokens (2-4 frame reads).
- **`ui-reverse-engineering`**: `component-generation.md` — **Loop 0: Original A/B comparison at 60fps** (MANDATORY for animated components). Captures both original and implementation at 60fps via agent-browser rAF polling, then diffs 5 properties: DIRECTION (which axis animates), RANGE (start/end values), TIMING (when transitions start/end), EASING (curve shape), COUPLING (which properties are synchronized). Prevents shipping wrong clipPath axis, inventing nonexistent animations, and desynchronized phases.
- **`ui-reverse-engineering`**: `component-generation.md` — **CSS-to-React translation pitfalls** section: 3 categories of errors when converting extracted CSS/GSAP animations to React components — (1) exit animations impossible with conditional rendering, (2) callback chains breaking on React lifecycle, (3) text line splitting must match CSS not character counts. Each with wrong/right patterns.
- **`ui-reverse-engineering`**: `component-generation.md` — 3 new entries in failure-based diagnosis table: splash transition not playing (conditional rendering), text line breaks differ (hardcoded split), scroll overlay not disappearing (callback chain failure).

### Changed
- **`ui-reverse-engineering`**: `animation-detection.md` — Tier 2 DOM polling upgraded from `setInterval(200ms)` (5fps) to `requestAnimationFrame` (60fps). 200ms polling loses easing curve shape, can't distinguish which clipPath axis animates, and merges simultaneous property changes. 60fps gives per-frame values that reveal direction, easing, and coupling. Includes comparison table showing what 5fps misses vs 60fps catches.
- **`ui-reverse-engineering`**: `animation-detection.md` — **Splash throttle protocol** added to Tier 2. `agent-browser eval` runs AFTER page load, so splash animations that fire on DOMContentLoaded are already finished by the time the capture script injects. Fix: apply network throttle (`agent-browser throttle 3g`) before eval injection, then remove throttle — this delays JS execution so the rAF capture starts before splash fires. Includes detection heuristic (Tier 1 AE spikes in first 3s = splash exists), fallback for when throttle isn't available (60fps video frame extraction + pixel measurement), and when-to-use decision matrix.
- **`ui-reverse-engineering`**: `animation-detection.md` — **MANDATORY video→bundle cross-reference** for splash animations. Both `eval` and `addInitScript` can miss splash because GSAP sets `from` values before capture starts — the captured "initial state" is already mid-animation. Video frames are the only reliable source. Protocol: (1) extract 60fps from video, (2) read 3-5 transition frames visually, (3) immediately grep bundle for the animation selector, (4) look for `> *` child-selector patterns that indicate per-child staggered animation.
- **`ui-reverse-engineering`**: `component-generation.md` — **SVG/DOM child staggered animation** pattern added to animation library wiring section. When bundle shows `.fromTo(".selector > *", ...)` with `stagger`, animate each child individually via loop, not the parent. Includes code template and common use cases (logo assembly, icon reveals, grid cards).
- **`ui-reverse-engineering`**: `component-generation.md` — 2 new entries in failure-based diagnosis table: (1) logo "assembles" in original but slides as unit in implementation → per-child animation, (2) splash data shows "element was always static" → eval/addInitScript missed it, use video frames.
- **`ui-reverse-engineering`**: `interaction-detection.md` — **Scroll method verification** (Step 5): when custom scroll detected, 3-screenshot comparison (before / scrollTo / wheel) to verify which scroll method works. Prevents `window.scrollTo()` false observations on Lenis/GSAP sites. Saves `scrollToWorks` and `verifiedMethod` to `scroll-engine.json`.
- **`ui-reverse-engineering`**: `interaction-detection.md` — **Bundle values → DOM element mapping** (mandatory after grep): cross-references bundle animation parameters with DOM selectors and idle capture frames to produce `element-animation-map.json`. Prevents applying wrong animation values to wrong elements.
- **`ui-reverse-engineering`**: `animation-detection.md` — **Idle capture execution protocol**: explicit command block with rationale for recording DURING page load (not after). Explains why "wait first, then record" misses splash animations entirely.
- **`ui-reverse-engineering`**: `SKILL.md` — JS bundle analysis promoted from conditional ("if needed") to **mandatory for ALL sites**. New Step 5c inserted into process flow with dedicated blocking gate.
- **`ui-reverse-engineering`**: `SKILL.md` — **Step Execution Rules reorganized**: 17 flat rules → **16 rules in 4 execution phases** (A: Before any work, B: During extraction, C: During implementation, D: During verification). Removed project-specific rules (shared package rebuild, URL TLD guessing). Consolidated bundle rules (download + analysis + branch verification).
- **`ui-reverse-engineering`**: `SKILL.md` — Bundle gate updated: "≥1 bundle" → "ALL loaded chunks downloaded via performance API".
- **`ui-reverse-engineering`**: `SKILL.md` — Step checkpoint table updated: Step 5→6 now requires ALL lazy chunks, not just main.js.
- **`ui-reverse-engineering`**: `interaction-detection.md` — Step 6 header changed from "JS Bundle Analysis (if needed)" to "JS Bundle Analysis (MANDATORY)". Added skip-rationalizations with rebuttals.
- **`ui-reverse-engineering`**: `animation-detection.md` — Phase A header changed to "MANDATORY".
- **`ui-reverse-engineering`**: `visual-verification.md` — Frame extraction standardized to 60fps.
- `plugin.json`, `marketplace.json` — version 0.0.17; description updated with transition-spec.json, bundle-map.json, phase-organized rules.

## [0.0.16] - 2026-04-08

### Added
- **`ui-capture`**: `report-page.md` — new overlay-based report page: fullpage screenshot as base layer with interactive transition overlays pinned at exact page coordinates. Sidebar region index with trigger badges, click-to-scroll navigation. Video overlays (scroll/mousemove/timer) auto-play via IntersectionObserver. Image toggle overlays (hover/intersection) show active state on mouse hover.
- **`ui-capture`**: `detection.md` — `bounds.x` coordinate collection: all 4 region types (hover, scroll, mousemove, timer) now capture `rect.left + window.scrollX` for precise horizontal overlay positioning.
- **`ui-reverse-engineering`**: `visual-verification.md` — Phase E: VLM sanity check. After all automated gates pass, read exactly 1 ref+impl screenshot pair (~4000 tokens) to catch issues outside measured selectors (missing elements, z-index stacking, overflow clipping, visual weight).

### Changed
- **`ui-reverse-engineering`**: `visual-verification.md` — all image comparisons switched from LLM Vision reading to AE/SSIM (zero tokens). C1: 5 static screenshots now compared via `compare -metric AE`. C2: 60fps scroll frames now compared via `ffmpeg SSIM` batch. C3 video frames: same SSIM batch. LLM only reads images for: fail diagnosis (diff images), one-time spot-checks (Phase A gate), and final VLM sanity check (Phase E, 1 pair).
- **`transition-reverse-engineering`**: `verification.md` — element-scope frame comparison switched from LLM table to AE batch. Fullpage-scope frame comparison switched to SSIM batch. Post-implementation capture comparison also SSIM-based.
- **`pixel-perfect-diff.md`** — diff image reading restricted to AE > 0 failures only. No image reading for passing elements.
- **`ui-capture`**: `comparison-page.md` — Report Mode section extracted to standalone `report-page.md`. Section now contains a short reference pointer instead of the full HTML template.
- **`ui-capture`**: `detection.md` — all region types now wrap coordinates in `bounds: { x, width, height }` object, matching `regions.json` schema. Previously output raw `x`, `y`, `width`, `height` at root level.
- **`ui-capture`**: `detection.md` — `regions.json` schema examples updated with `bounds.x` field for all region types.
- **`ui-capture`**: `SKILL.md` — reference files list includes `report-page.md`. Phase R references updated from `comparison-page.md` to `report-page.md`.
- **`ui-reverse-engineering`**: `SKILL.md` — reference files description updated with AE/SSIM comparison and Phase E VLM sanity check.
- `plugin.json`, `marketplace.json` — version bumped to 0.0.16; description updated with overlay report page.
- `README.md` — ui-capture description updated with overlay-based report page and `bounds.x` coordinate collection.

### Fixed
- **`ui-capture`**: `capture-transitions.md` — removed `hover-` prefix from css-hover capture filenames (`hover-<name>-idle.png` → `<name>-idle.png`). Now consistent with comparison-page.md and report-page.md templates.
- **`ui-capture`**: `report-page.md` — template placeholders renamed from `<xPct>/<wPct>/<hPct>` to `<topPct>/<leftPct>/<widthPct>/<heightPct>`, matching the overlay positioning rules section.

## [0.0.15] - 2026-04-06

### Added
- **`ui-reverse-engineering`**: `style-extraction.md` — design bundle grouping: post-processing step groups CSS properties into 5 co-varying bundles (surface, shape, type, tone, motion). Deduplicates identical bundles and assigns IDs. Results saved to `design-bundles.json`.
- **`ui-reverse-engineering`**: `component-generation.md` — bundle covariance rules: when fixing a property during iterations, all sibling properties in the same bundle must be verified. Prevents isolated fixes that break visual coherence (e.g., changing fontSize without lineHeight).
- **`ui-reverse-engineering`**: `style-audit.md` — 10-point design fidelity scoring: diagnostic checklist (typography, colors, spacing, surface, layout, responsive, interactions, motion, assets, completeness). Runs at each fix iteration to guide priority. Score regression triggers rollback. 3 iterations without 9+ triggers user escalation.
- **`ui-reverse-engineering`**: `SKILL.md` — Step 6c expanded from 3-check audit to 6-stage pre-generation design audit: data inventory, role identification, grouping + hierarchy, layout direction, design bundle verification, component boundaries. Each stage produces a JSON artifact.

### Changed
- **`ui-reverse-engineering`**: `visual-verification.md` — fix protocol updated: 10-point scoring runs first to guide fix direction, covariance rules checked before committing changes, score regression triggers rollback.
- **`ui-reverse-engineering`**: `visual-verification.md` — completion gate updated: score ≥ 9 required before running pixel-perfect-diff.
- **`ui-reverse-engineering`**: `SKILL.md` — Step 6b assembly list includes `design-bundles.json`. Extraction gate includes bundle validation.
- **`ui-reverse-engineering`**: `component-generation.md` — input checklist includes `design-bundles.json` and `component-map.json`.
- `plugin.json`, `marketplace.json` — version bumped to 0.0.15; description and keywords updated.
- `README.md` — pipeline diagram updated with 6-stage audit and scoring loop; 6b assembly list includes `design-bundles`.

### Fixed
- **`ui-reverse-engineering`**: `component-generation.md` — removed `typography-scale.json` from input checklist (absorbed by `design-bundles.json` type bundle). "Typographic scale consistency check" replaced with "Design bundle consistency check". Fixed Step 6c references in checklist (`interaction-states.json` from Step 5, `decorative-svgs.json` from Step 3).
- **`ui-reverse-engineering`**: `style-audit.md` — removed A3.6 "Cross-section typography consistency" (duplicated by 10-point scoring #1). Clarified A1-A4 → 10-point scoring relationship (detail → summary). Removed duplicate `---` separator. Scoring eval note: 10-point score derives from A1-A4 `style-audit-diff.json`, not a separate getComputedStyle run.
- **`ui-reverse-engineering`**: `style-extraction.md` — fixed bundle grouping eval: removed unused `bundles` initialization, declared at conversion point.
- **`ui-reverse-engineering`**: `SKILL.md` — differentiated 6b gate (existence) from 6c gate (consistency). Phase 4 completion gate now requires `10-point score ≥ 9`.
- All skill documents — translated remaining Korean text to English (`pixel-perfect-diff.md`, `capture-transitions.md`, `comparison-page.md`, `SKILL.md`, `visual-verification.md`, `README.md`).

## [0.0.14] - 2026-04-05

### Added
- **`ui-reverse-engineering`**: `dom-extraction.md` — portal-escaped element detection: finds `position: fixed` elements inside `transform`-ed scroll wrappers (broken by CSS spec). Detects elements rendered outside the wrapper (already portal-escaped) and elements inside (need portal in implementation). Results saved to `portal-candidates.json`.
- **`ui-reverse-engineering`**: `dom-extraction.md` — inline SVG collection: extracts `outerHTML` verbatim for all `<svg>` elements (logos, icons, brandmarks). Never recreates SVGs from visual appearance. Results saved to `inline-svgs.json`.
- **`ui-reverse-engineering`**: `style-extraction.md` — decorative SVG extraction: captures `position: absolute` / `aria-hidden` SVGs with full path data (`d`, `stroke-width`, `fill`, `strokeDasharray`).
- **`ui-reverse-engineering`**: `style-extraction.md` — stroke-based hover animation detection: captures idle + active `stroke-dasharray`/`stroke-dashoffset` values on SVG children during hover state delta.
- **`ui-reverse-engineering`**: `interaction-detection.md` — mouse-tracking interaction detection: finds elements that follow cursor position (image tooltips, custom cursors, parallax tilt, spotlight effects) by detecting absolutely-positioned `pointer-events: none` children.
- **`ui-reverse-engineering`**: `interaction-detection.md` — hover state delta now captures `stroke-dasharray`/`stroke-dashoffset` on ALL SVG children (`path`, `rect`, `circle`, `line`), not just the parent element.
- **`ui-reverse-engineering`**: `interaction-detection.md` — custom scroll engine detection: detects `overflow: hidden` + `transform`-based scroll (rAF lerp), extracts wrapper selector and lerp behavior via wheel event dispatch. Known library detection (Lenis, GSAP ScrollSmoother, Locomotive). Impact rules for downstream extraction steps (IntersectionObserver, window.scrollTo, portal escapes). Results saved to `scroll-engine.json`.
- **`ui-reverse-engineering`**: `interaction-detection.md` — cross-component DOM manipulation detection: finds `querySelector + style` patterns and scroll-position-based state changes in bundles. Records as `type: "cross-component"` in `interactions-detected.json`.
- **`ui-reverse-engineering`**: `SKILL.md` — Step 6c pre-generation audit: typography scale table (consistent values per role), multi-state interaction table (idle + active values), decorative SVG inventory (verbatim paths). Gate requires all three artifacts before code generation.
- **`ui-reverse-engineering`**: `component-generation.md` — Tailwind v4 custom font registration rule (`@theme` block, not `:root` CSS variables). `font-[var(--my-font)]` with comma-separated values does not work in Tailwind v4.
- **`ui-reverse-engineering`**: `component-generation.md` — font size vw conversion formula (`vw = extractedPx / viewportWidth * 100`) with `clamp()` pattern.
- **`ui-reverse-engineering`**: `component-generation.md` — custom scroll engine generation rules: rAF lerp loop, portal escape for fixed elements, scroll context for dependent components.
- **`ui-reverse-engineering`**: `component-generation.md` — mouse-follow interaction generation pattern (`onMouseMove` + absolute child positioning).
- **`ui-reverse-engineering`**: `component-generation.md` — SVG verbatim rule: never recreate from visual appearance, use `outerHTML` from `inline-svgs.json` with HTML→JSX attribute conversion.
- **`ui-reverse-engineering`**: `animation-detection.md` — NEW: 3-phase motion detection document (idle capture → scroll capture → per-element tracking). Detects splash, auto-timers, parallax, scroll-zoom, clip-reveal, sticky, word-stagger.
- **`ui-reverse-engineering`**: `style-audit.md` — NEW: post-generation class-level computed style comparison (ref vs impl). Catches wrong font-size, font-weight, missing SVGs, wrong images, spacing mismatches. Runs in parallel with Step 8.

### Changed
- **`ui-reverse-engineering`**: `SKILL.md` — Step 6b assembly list expanded with `portal-candidates.json`, `inline-svgs.json`, `scroll-engine.json`. Extraction gate checklist updated with new artifacts.
- **`ui-reverse-engineering`**: `SKILL.md` — Reference Files section updated: `interaction-detection.md` scoped to Step 5; new `animation-detection.md` listed for Step 6; `style-audit.md` listed as parallel post-generation check.
- **`ui-reverse-engineering`**: `component-generation.md` — input checklist expanded with `portal-candidates.json`, `inline-svgs.json`, `scroll-engine.json`, `typography-scale.json`, `interaction-states.json`, `decorative-svgs.json`.
- **`ui-reverse-engineering`**: `component-generation.md` — mandatory typography scale consistency check before generation.
- `plugin.json`, `marketplace.json` — version bumped to 0.0.14; description and keywords updated.
- `README.md` — pipeline diagram updated; new sub-documents listed.

## [0.0.13] - 2026-04-03

### Added
- **`ui-capture`**: Phase 1 — custom scroll container auto-detection (`data-lenis`, `.locomotive-scroll`, `overflow: hidden` fallback). Returns `scrollType` (`native`|`custom`) and `scrollSelector` for all subsequent scroll operations.
- **`ui-capture`**: Phase 1 — section-by-section screenshot capture: resize viewport to each section's actual height, scroll into view, capture. Replaces single fullpage screenshot.
- **`ui-capture`**: Phase 1 — `mouse wheel`-based scroll recording for custom scroll sites (Lenis, Locomotive, etc.) — only real wheel events trigger these libraries.
- **`ui-capture`**: Phase 1 — mandatory ffmpeg trim for scroll videos (`-ss 0.3 -t <activeDuration>`) to remove dead frames from `record start`/`stop`.
- **`ui-reverse-engineering`**: Step 6 — animation detection pipeline: frame extraction (`ffmpeg fps=2`) → consecutive frame comparison → DOM element mapping → classification (scroll-reveal, parallax, sticky, scale, clip-path, auto-timer) → per-animation capture. Results saved to `animations-detected.json`.
- **`ui-reverse-engineering`**: Step 6 — automatic `/transition-reverse-engineering` invocation when scroll-driven, canvas, or WebGL animations detected.

### Changed
- **`ui-capture`**: Phase 1 troubleshooting table expanded with 6 new entries: custom scroll container detection, `scrollTo` no-op on custom sites, blank selector screenshots, identical section heights, scroll video dead time, and scroll video instant-jump.
- **`ui-reverse-engineering`**: Step 6b assembly list now includes `animations-detected.json`.
- **`ui-reverse-engineering`**: Extraction gate checklist now requires `animations-detected.json` with selector/type/captures per entry.
- `plugin.json`, `marketplace.json` — version bumped to 0.0.13; description and keywords updated.
- `README.md` — pipeline diagram updated with animation detection step; ui-capture description updated with custom scroll and section screenshots.

## [0.0.12] - 2026-04-02

### Added
- **`ui-reverse-engineering`**: `interaction-detection.md` — auto-timer detection section: `setInterval`/`setTimeout` carousel/slideshow/rotating-text detection via timed screenshot comparison and bundle grep. Results saved to `interactions-detected.json` under `autoTimer` key.
- **`ui-reverse-engineering`**: `interaction-detection.md` — JS animation library detection section: bundle grep patterns for Framer Motion, GSAP, and pure CSS transitions. Extracts spring params, ease presets, duration/stagger from minified code.
- **`ui-reverse-engineering`**: `interaction-detection.md` — spring-to-cubic-bezier mapping table: common spring/ease configs → CSS `cubic-bezier` equivalents.
- **`ui-reverse-engineering`**: `interaction-detection.md` — known issues: `agent-browser record start` page reload workaround (rapid sequential screenshots), intro animation scroll blocking (5–8s wait).

### Changed
- `plugin.json`, `marketplace.json` — version bumped to 0.0.12; description and keywords updated.
- `README.md` — animation types table updated with auto-timer and animation library extraction rows.

## [0.0.11] - 2026-03-31

### Added
- **`ui-reverse-engineering`**: `dom-extraction.md` — Step 2.5: head metadata extraction (`<title>`, favicon, viewport) + visible image collection and download. Images filtered by `getBoundingClientRect().height > 0`. Assets saved to `tmp/ref/<component>/assets/`. HTTPS only, 10MB limit.
- **`ui-reverse-engineering`**: `interaction-detection.md` — scroll behavior detection step: scans all elements for `scroll-snap-type/align/stop`, `scroll-behavior: smooth`, `overscroll-behavior`. Results saved to `interactions-detected.json` under `scrollBehavior` field. JS scroll library detection (Lenis, GSAP ScrollSmoother, Locomotive) via bundle grep.
- **`transition-reverse-engineering`**: `js-animation-extraction.md` — scroll library parameter extraction section: detection signatures, config extraction (lerp, duration, wheelMultiplier, smooth, wrapper/content), `scroll-library.json` schema, and Lenis component generation example.

### Evals
- **`ui-reverse-engineering`**: `evals/evals.json` — evals 28–30 added: asset download (favicon + visible images), scroll behavior detection (snap/smooth/overscroll), and Lenis JS scroll library extraction.
- **`transition-reverse-engineering`**: `evals/evals.json` — eval 22 added: GSAP ScrollSmoother config extraction from bundle.

### Changed
- **`ui-reverse-engineering`**: `component-generation.md` — input checklist updated with `head.json` + `assets.json`; image rule updated to prefer downloaded assets over placeholders; scroll behavior added to generation prompt template with Tailwind utility mapping.
- **`ui-reverse-engineering`**: `interaction-detection.md` — JS scroll library detection moved from Step 5 to Step 6 (after bundle download, where bundles actually exist).
- **`ui-reverse-engineering`**: `SKILL.md` — pipeline diagram updated with Step 2.5 (head + assets extraction); Step 6b assembly list includes head.json + assets.json; Output schema includes head/assets/scrollBehavior fields; Reference Files updated.
- **`ui-capture`**: `SKILL.md` — Phase R added: standalone report mode (`report.html`) when no local-url provided. Shows fullpage screenshot, detected regions table, per-region captures, and CTA. Process flow diagram updated with branching (local-url → compare mode, no local-url → report mode).
- **`ui-capture`**: `SKILL.md` — Phase 5 rewritten from "User Review" to "Completion Gate" with two paths: interactive mode (wait for user feedback) and autonomous mode (ralph-loop). Autonomous mode uses `pixel-perfect-diff.json` as binary pass/fail gate with 3 auto-fix retries before escalation.
- **`ui-capture`**: `comparison-page.md` — Report Mode section added with full `report.html` template: regions table with trigger-type badges, per-region capture previews (clip screenshots + videos), and usage conditions (standalone vs comparison).
- `README.md` — pipeline diagram updated with Step 2.5; scroll behavior row added to animation types table; description updated to mention asset extraction.
- `plugin.json`, `marketplace.json` — version bumped to 0.0.11; keywords updated.

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
- **Consistency fixes** — `capture-transitions.md` Step 2B-2 "4 states" corrected to "3 states" (before/mid/after); all clip screenshot paths in Step 2C unified to `clip/{ref,impl}/` (was incorrectly `transitions/{ref,impl}/`); `compare` command paths in `visual-verification.md` and `verification.md` prefixed with correct `tmp/ref/<component>/`; Phase D and Step 4 gate wording updated to cover all state variants (idle / active / before / mid / after).

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

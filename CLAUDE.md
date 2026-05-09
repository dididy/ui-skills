# CLAUDE.md — ui-clone-skills development guide

## Project structure

```
ui_clone/          Python package (gates, hooks, pipeline, DAG, metrics)
skills/            3 Claude Code skills (ui-reverse-engineering, ui-capture, visual-debug)
scripts/           Bash automation (extraction, verification, git hooks)
hooks/             Plugin hook registration (hooks.json + shim.sh)
tests/             pytest suite (286 tests)
.claude-plugin/    Plugin manifest (plugin.json, marketplace.json)
```

## Development commands

```bash
uv run python -m pytest tests/ -q          # run all tests
uv run python -m pytest tests/test_gate.py  # run specific module
bash scripts/ci-local.sh                    # full CI mirror (pytest + mypy + ruff + shell + review)
bash scripts/pre-push-security.sh           # security + cross-ref + version sync
python -m ui_clone.gate tmp/ref/<c> all     # validate all gates
```

## Verification gate (must pass before commit)

```
[] bash scripts/ci-local.sh — 0 failures (mirrors GitHub Actions test job)
[] bash scripts/pre-push-security.sh — 0 blockers
```

`scripts/ci-local.sh` is the single source of truth for what CI runs. `scripts/claude-pre-push.sh` calls it automatically before `git push` (bypass for emergencies: `UI_RE_SKIP_CI_LOCAL=1 git push`). If you change CI, update `ci-local.sh` to match — and vice versa.

## Rules

### Language
- All skill docs (`skills/**/*.md`), README, CHANGELOG: **English only**
- Code comments: English only
- Commit messages: English only

### Naming
- Python package: `ui_clone`
- npm package: `agent-browser`
- GitHub: `vercel-labs/agent-browser`, `rtk-ai/rtk`
- Owner: `voidmatcha`

### Pipeline step numbering
Sub-docs must match SKILL.md pipeline numbering:
- Step 5 = interaction-detection.md
- Step 5c-a = bundle-analysis.md (download + grep; NOT "Step 6")
- Step 5c-b = bundle-verification.md (numerical comparison)
- Step 5c-c = paid-features-detect.sh (paid font CDN scan; produces paid-features.json)
- Step 5d = transition-spec-rules.md (produces external-sdks.json)
- Step 6 = animation-detection.md
- Step 6c = section-audit.md
- Step 6d = transition-coverage.md
- Step 8-pre-bound = breakpoint-collision-check.sh (produces responsive/boundary-collisions.json)
- Step 8b-pre = font-parity-check.sh (produces font-parity.json)

### Gate → artifact mapping
Each gate checks artifacts produced BEFORE that gate fires. Dispatch keys live in `ui_clone/gate.py` `VALID_GATES`:
- `reference` (after Phase 1 / `/ui-capture`): static/ref/ ≥5 PNGs, transitions/ref/ ≥1 file, regions.json
- `extraction` (after Step 3): structure.json, head.json, styles.json, fonts.json, visible-images.json, inline-svgs.json, body-state.json, design-bundles.json, css/variables.txt, em-conversion.json (if scalingSystem ≠ px-fixed)
- `bundle` (after 5c-a): bundles/ (≥1 JS chunk; warns <3), interactions-detected.json, scroll-engine.json
- `paid-features` (after 5c-c): paid-features.json — every paid font CDN hit must have `decision` ∈ {`use`, `substitute`, `skip`}. Empty findings pass. GSAP plugins are not checked (GSAP is now 100% free). See `skills/visual-debug/scripts/paid-features-detect.sh`.
- `spec` (after 5d): bundle-map.json, external-sdks.json, transition-spec.json (validates `transitions[0]` has id/trigger/bundle_branch), verify/ ≥5 frames. Also cross-validates against `paid-features.json`: any paid font marked `decision="substitute"` must have an entry in `asset-substitution.json` `fonts[]` — otherwise font-parity FAILs after generation.
- `pre-generate` (before Step 7): extracted.json, transition-coverage.json, section-map.json, hover timing resolved, dom-state-diff.json (if hasPreloader), webflow-* (if Webflow), audit artifacts (element-roles, element-groups, layout-decisions, component-map)
- `post-implement` (after each transition impl): extracted.json, transition-spec.json, static/ref ≥5
- `boundary` (after 8-pre-bound): responsive/boundary-collisions.json — must be `[]`. Produced by `skills/visual-debug/scripts/breakpoint-collision-check.sh` (REF_DIR env required to write the artifact). Catches Tailwind ↔ project @media inclusive-boundary collisions (Root Cause J in diagnosis.md).
- `font-parity` (after 8b-pre): font-parity.json — `parity:"match"` PASSes (with silent-fallback guard via `document.fonts.check()`); `parity:"mismatch"` requires `asset-substitution.json` with at least one `fonts[]` entry. Produced by `skills/visual-debug/scripts/font-parity-check.sh`.
- `section-compare` (Stop hook): tmp/ref/<c>/sections/result.txt — 0 ❌ FAIL lines and 0 "⚠️ MISSING impl" lines

If you add an artifact check to a gate, ensure the sub-doc that produces it runs BEFORE that gate.

**Phase 0A note:** `canvas-webgl-detection.json` is produced by the pipeline but is *advisory*, not gated — it routes the agent to `canvas-webgl-extraction.md` when needed. No `gate_canvas_*` exists.

### Sub-doc conventions
- Title format: `# <Name> — Step <N>` matching SKILL.md pipeline
- "After this step" links must point to the correct next step per SKILL.md
- `animations-detected.json` is merged into `extracted.json` at Step 6b — not checked by gates directly
- All agent-browser commands must use `--session <name>`
- All JS evals must use IIFE: `(() => { ... })()`

### Version sync
- `plugin.json` and `marketplace.json` versions must match
- `pyproject.toml` version must be updated on release
- `claude-pre-push.sh` enforces this automatically

### Section name detection (scripts)
3 scripts share the same keyword → name mapping for section detection:
- `extract-assets.sh`, `extract-section-html.sh`, `section-clips.sh`
When adding new keywords, update all 3.

### FPS
All video frame extraction uses 60fps. `video-transition-compare.sh` defaults to `FPS=60`.

### Token management
- Large eval output → pipe to file, then Read/Grep specific lines
- Never let DOM/style JSON print to stdout
- Ref screenshots: AE/SSIM diff only, never Read for comparison (except Phase E)

## Review checklist

Run before push — `scripts/review.sh` automates this:

```
[] Tests pass (260+)
[] Security gate passes (11 checks)
[] Sub-doc step numbers match SKILL.md pipeline
[] Gate artifact checks match sub-doc output timing
[] No stale refs to deleted files (validate-gate.sh, run-pipeline.sh, ui_skills.*)
[] README numbers accurate (sub-doc count, token count, FPS)
[] Cross-skill refs use correct relative paths (../visual-debug/...)
[] plugin.json + marketplace.json versions match
[] No hardcoded local paths in SKILL.md (use $SCRIPTS_DIR, $PLUGIN_ROOT)
[] Section name keyword lists consistent across 3 scripts
```

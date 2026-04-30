#!/usr/bin/env bash
# validate-gate.sh — Block phase transitions when required artifacts are missing
#
# Usage: bash validate-gate.sh <ref-dir> <gate>
#   gate: reference | extraction | bundle | spec | pre-generate | post-implement | all
#
# Exit: 0 = PASS (may proceed), 1 = BLOCKED (fix before continuing)
#
# The SKILL.md pipeline references this script at every phase boundary.
# Without it, the LLM can skip phases — this makes skipping impossible.
#
# Staleness detection: if a parent artifact is newer than a child artifact,
# the child is marked stale (re-extraction required). Staleness is BLOCKING
# for the assembled artifact (extracted.json) and WARNING for intermediate files.

set -euo pipefail

REF_DIR="${1:?Usage: validate-gate.sh <ref-dir> <gate>}"
GATE="${2:?Usage: validate-gate.sh <ref-dir> <gate>  (reference|extraction|bundle|spec|pre-generate|post-implement|all)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

FAIL=0
TOTAL=0

# Returns mtime as integer (seconds since epoch), portable macOS/Linux
_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

check_file() {
  local path="$1"
  local label="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$path" ]; then
    local size
    size=$(wc -c < "$path" | tr -d ' ')
    if [ "$size" -lt 10 ]; then
      echo -e "  ${RED}✗${NC} $label — exists but empty ($size bytes)"
      FAIL=$((FAIL + 1))
    else
      echo -e "  ${GREEN}✓${NC} $label"
    fi
  else
    echo -e "  ${RED}✗${NC} $label — MISSING"
    FAIL=$((FAIL + 1))
  fi
}

# check_stale PARENT CHILD CHILD_LABEL [block|warn]
# If CHILD exists but PARENT is newer → child is stale (based on stale parent data)
# mode=block → FAIL counted in TOTAL (hard gate); mode=warn → advisory only, not in TOTAL
check_stale() {
  local parent="$1" child="$2" child_label="$3" mode="${4:-warn}"
  [ -f "$parent" ] || return 0  # parent doesn't exist — gate_* handles that separately
  [ -f "$child" ] || return 0   # child doesn't exist — check_file handles that
  local parent_mtime child_mtime
  parent_mtime=$(_mtime "$parent")
  child_mtime=$(_mtime "$child")
  if [ "$parent_mtime" -gt "$child_mtime" ]; then
    local parent_name; parent_name=$(basename "$parent")
    if [ "$mode" = "block" ]; then
      TOTAL=$((TOTAL + 1))
      echo -e "  ${RED}✗${NC} $child_label — STALE (${parent_name} was re-extracted after this file was built)"
      echo -e "    Re-run the step that produces $(basename "$child") to pick up the new ${parent_name}."
      FAIL=$((FAIL + 1))
    else
      # warn: advisory only — not counted in TOTAL so PASS: N/N stays accurate
      echo -e "  ${YELLOW}⚠${NC}  $child_label — may be stale (${parent_name} is newer). Re-run this step if values look wrong."
    fi
  fi
}

# check_json_key FILE KEY LABEL — validates that a JSON file contains a required top-level key
check_json_key() {
  local path="$1" key="$2" label="$3"
  [ -f "$path" ] || return 0  # check_file already handles missing
  TOTAL=$((TOTAL + 1))
  local has_key
  has_key=$(python3 -c "
import json, sys
try:
    d = json.load(open('$path'))
    print('yes' if '$key' in d else 'no')
except json.JSONDecodeError as e:
    print('malformed:' + str(e)[:60])
except Exception as e:
    print('error:' + str(e)[:60])
" 2>/dev/null || echo "error")
  if [ "$has_key" = "yes" ]; then
    echo -e "  ${GREEN}✓${NC} $label (has '$key' key)"
  elif echo "$has_key" | grep -q '^malformed:'; then
    echo -e "  ${RED}✗${NC} $label — malformed JSON: ${has_key#malformed:}"
    FAIL=$((FAIL + 1))
  else
    echo -e "  ${RED}✗${NC} $label — JSON missing required key '$key'"
    FAIL=$((FAIL + 1))
  fi
}

check_dir() {
  local path="$1"
  local label="$2"
  local min_files="${3:-1}"
  TOTAL=$((TOTAL + 1))
  if [ -d "$path" ]; then
    local count
    count=$({ find "$path" -type f 2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$count" -lt "$min_files" ]; then
      echo -e "  ${RED}✗${NC} $label — directory exists but only $count files (need ≥$min_files)"
      FAIL=$((FAIL + 1))
    else
      echo -e "  ${GREEN}✓${NC} $label ($count files)"
    fi
  else
    echo -e "  ${RED}✗${NC} $label — MISSING directory"
    FAIL=$((FAIL + 1))
  fi
}

# ── Gate: reference (Phase 1 complete) ──
gate_reference() {
  echo "Gate: reference (Phase 1)"
  check_dir "$REF_DIR/static/ref" "static/ref screenshots" 5
  check_file "$REF_DIR/regions.json" "regions.json (transition regions)"
}

# ── Gate: extraction (Phase 2 Steps 1-3 complete) ──
gate_extraction() {
  echo "Gate: extraction (Phase 2 Steps 1-3)"
  check_file "$REF_DIR/structure.json" "structure.json (DOM hierarchy)"
  check_file "$REF_DIR/head.json" "head.json (metadata)"
  check_file "$REF_DIR/styles.json" "styles.json (computed styles)"
  check_file "$REF_DIR/fonts.json" "fonts.json (font faces)"
  check_file "$REF_DIR/css/variables.txt" "css/variables.txt (CSS custom properties)"
  check_file "$REF_DIR/visible-images.json" "visible-images.json"
  check_file "$REF_DIR/inline-svgs.json" "inline-svgs.json"
  check_file "$REF_DIR/body-state.json" "body-state.json"
  check_file "$REF_DIR/design-bundles.json" "design-bundles.json"

  # Viewport-scaled font em-conversion gate
  if [ -f "$REF_DIR/typography.json" ]; then
    local scaling
    scaling=$(python3 -c "import json; d=json.load(open('$REF_DIR/typography.json')); print(d.get('scalingSystem',''))" 2>/dev/null || echo "")
    if echo "$scaling" | grep -qiE 'viewport-scaled|em-based'; then
      check_file "$REF_DIR/em-conversion.json" "em-conversion.json (REQUIRED: scalingSystem=$scaling — px values are viewport-specific)"
    fi
  fi
}

# ── Gate: bundle (Phase 2 Step 5c — JS bundles downloaded) ──
gate_bundle() {
  echo "Gate: bundle (Phase 2 Step 5c)"
  check_dir "$REF_DIR/bundles" "bundles/ (downloaded JS chunks)" 1
  # Advisory: warn if fewer than 3 chunks — typical SPAs have ≥3 (app + vendor + lazy chunks).
  # Some sites legitimately have fewer; this is not blocking but worth noting.
  if [ -d "$REF_DIR/bundles" ]; then
    local _chunk_count
    _chunk_count=$({ find "$REF_DIR/bundles" -type f -name "*.js" 2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$_chunk_count" -lt 3 ] && [ "$_chunk_count" -ge 1 ]; then
      echo -e "  ${YELLOW}⚠${NC}  Only $_chunk_count JS chunk(s) — typical SPAs have ≥3. Verify all chunks downloaded via performance.getEntriesByType('resource')."
    fi
  fi
  check_file "$REF_DIR/interactions-detected.json" "interactions-detected.json"
  check_file "$REF_DIR/scroll-engine.json" "scroll-engine.json"
  check_file "$REF_DIR/external-sdks.json" "external-sdks.json (GSAP/Lenis/Framer detection — {} for no SDKs)"
}

# ── Gate: spec (Phase 2 Step 5d+5e — transition-spec written AND verified) ──
gate_spec() {
  echo "Gate: spec (Phase 2 Step 5d+5e)"
  # bundle-map.json is required ONLY for sites with transitions.
  # Static sites write bundle-map.json as {} — that is fine.
  check_file "$REF_DIR/bundle-map.json" "bundle-map.json (Step 5d input — {} for static sites)"
  check_file "$REF_DIR/transition-spec.json" "transition-spec.json (single source of truth)"

  # Staleness: transition-spec.json should reflect bundle-map.json (Step 5d outputs both)
  check_stale "$REF_DIR/bundle-map.json" "$REF_DIR/transition-spec.json" "transition-spec.json" warn

  # Validate structure if file exists and jq is available
  if [ -f "$REF_DIR/transition-spec.json" ] && command -v jq &>/dev/null; then
    TOTAL=$((TOTAL + 1))
    local trans_len
    trans_len=$(jq '.transitions | length' "$REF_DIR/transition-spec.json" 2>/dev/null || echo "0")
    if [ "$trans_len" -gt 0 ]; then
      echo -e "  ${GREEN}✓${NC} .transitions array ($trans_len entries)"
      # Only validate first entry keys when transitions exist
      TOTAL=$((TOTAL + 1))
      local has_keys
      has_keys=$(jq '.transitions[0] | (has("id") and has("trigger") and has("bundle_branch"))' "$REF_DIR/transition-spec.json" 2>/dev/null || echo "false")
      if [ "$has_keys" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} transitions[0] has id, trigger, bundle_branch"
      else
        echo -e "  ${RED}✗${NC} transitions[0] missing required keys (id, trigger, bundle_branch)"
        FAIL=$((FAIL + 1))
      fi
    else
      # Empty transitions array is valid for static sites
      echo -e "  ${GREEN}✓${NC} .transitions array (empty — static site or no transitions detected)"
    fi
  fi

  # Step 5e: Capture verification — verify/ directory must exist with frames
  TOTAL=$((TOTAL + 1))
  local verify_frames
  verify_frames=$({ find "$REF_DIR/verify" -name "*.png" 2>/dev/null || true; } | wc -l | tr -d ' ')
  if [ "$verify_frames" -ge 5 ]; then
    echo -e "  ${GREEN}✓${NC} capture verification frames ($verify_frames frames in verify/)"
  else
    echo -e "  ${YELLOW}⚠${NC} capture verification missing or incomplete ($verify_frames frames — need ≥5)"
    echo -e "    Record the original site, extract frames, verify spatial values."
    echo -e "    See interaction-detection.md 'MANDATORY: Capture Verification'."
    # Warning only, not blocking — but strongly recommended
  fi
}

# ── Gate: pre-generate (Phase 2 Step 6c — audit complete, ready for code gen) ──
gate_pre_generate() {
  echo "Gate: pre-generate (Phase 2 Step 6c)"
  check_file "$REF_DIR/extracted.json" "extracted.json (assembled extraction)"
  check_json_key "$REF_DIR/extracted.json" "sections" "extracted.json content validation"
  check_file "$REF_DIR/transition-spec.json" "transition-spec.json"

  # ── Staleness detection: extracted.json must be newer than all parent artifacts ──
  # If structure.json, styles.json, or component-map.json were re-extracted AFTER extracted.json
  # was assembled, the assembly is stale and must be re-run (Step 6b).
  for parent_artifact in structure.json styles.json component-map.json interactions-detected.json hover-css-rules.json transition-coverage.json; do
    check_stale "$REF_DIR/$parent_artifact" "$REF_DIR/extracted.json" "extracted.json (stale vs $parent_artifact)" block
  done

  # Animation init styles (Step 2.6) — initial CSS state before JS overrides
  check_file "$REF_DIR/animation-init-styles.json" "animation-init-styles.json (Step 2.6 — initial CSS before JS)"

  # Section map (from dom-extraction.md Step 2 enumeration)
  check_file "$REF_DIR/section-map.json" "section-map.json (semantic section enumeration)"

  # Multi-viewport sizing expressions (Step 4-C2)
  check_file "$REF_DIR/responsive/sizing-expressions.json" "sizing-expressions.json (multi-viewport element sizing)"

  # Staleness: section-map is a downstream product of structure.json; component-map of section-map
  check_stale "$REF_DIR/structure.json" "$REF_DIR/section-map.json" "section-map.json" warn
  check_stale "$REF_DIR/section-map.json" "$REF_DIR/component-map.json" "component-map.json" warn

  # Viewport-scaled font em-conversion (re-check at pre-generate)
  if [ -f "$REF_DIR/typography.json" ]; then
    local scaling
    scaling=$(python3 -c "import json; d=json.load(open('$REF_DIR/typography.json')); print(d.get('scalingSystem',''))" 2>/dev/null || echo "")
    if echo "$scaling" | grep -qiE 'viewport-scaled|em-based'; then
      check_file "$REF_DIR/em-conversion.json" "em-conversion.json (REQUIRED for $scaling sites)"
    fi
  fi

  # JS hover timing — warn if deltas exist but timing is unknown
  if [ -f "$REF_DIR/hover-deltas.json" ] && [ -f "$REF_DIR/interactions-detected.json" ]; then
    TOTAL=$((TOTAL + 1))
    local unknown_timing
    unknown_timing=$(python3 -c "
import json
data = json.load(open('$REF_DIR/interactions-detected.json'))
interactions = data.get('interactions', [])
unknown = [i for i in interactions if i.get('timingSource') == 'unknown']
print(len(unknown))
" 2>/dev/null || echo "0")
    if [ "$unknown_timing" -gt 0 ]; then
      echo -e "  ${RED}✗${NC} $unknown_timing hover interactions have timingSource='unknown' — bundle analysis must resolve"
      FAIL=$((FAIL + 1))
    else
      echo -e "  ${GREEN}✓${NC} All hover interactions have known timing"
    fi
  fi

  # SVG-as-text detection (Step 2.5b)
  check_file "$REF_DIR/svg-text-elements.json" "svg-text-elements.json (SVG-as-text detection)"

  # Webflow IX2 (Step W) — required if site is Webflow
  if [ -f "$REF_DIR/webflow-detection.json" ] && command -v jq &>/dev/null; then
    local is_webflow
    is_webflow=$(jq -r '.isWebflow // false' "$REF_DIR/webflow-detection.json" 2>/dev/null || echo "false")
    if [ "$is_webflow" = "true" ]; then
      check_file "$REF_DIR/webflow-hide-rule.json" "webflow-hide-rule.json (IX2 selector inventory — Step W-2)"
      check_file "$REF_DIR/webflow-ix2.json" "webflow-ix2.json (IX2 timeline data — Step W-3)"
    fi
  fi

  # Transition coverage audit (Step 6d) — animatedElements must be non-empty
  # Exception: static sites (transition-spec.json with empty transitions[]) are allowed to have 0 animated elements
  check_file "$REF_DIR/transition-coverage.json" "transition-coverage.json (Step 6d multi-position scroll measurement)"
  if [ -f "$REF_DIR/transition-coverage.json" ] && command -v jq &>/dev/null; then
    TOTAL=$((TOTAL + 1))
    local animated_count is_static_site
    animated_count=$(jq '.animatedElements | length' "$REF_DIR/transition-coverage.json" 2>/dev/null || echo "0")
    is_static_site="false"
    if [ -f "$REF_DIR/transition-spec.json" ]; then
      local trans_len
      trans_len=$(jq '.transitions | length' "$REF_DIR/transition-spec.json" 2>/dev/null || echo "1")
      [ "$trans_len" -eq 0 ] && is_static_site="true"
    fi
    if [ "$animated_count" -gt 0 ]; then
      echo -e "  ${GREEN}✓${NC} transition-coverage: $animated_count animated elements"
    elif [ "$is_static_site" = "true" ]; then
      echo -e "  ${GREEN}✓${NC} transition-coverage: 0 animated elements (static site — transitions[] is empty)"
    else
      echo -e "  ${RED}✗${NC} transition-coverage.json animatedElements is empty — audit incomplete or site truly static (rare)"
      FAIL=$((FAIL + 1))
    fi
    # Removed: data-w-id ratio heuristic — too prone to false positives on Webflow sites
    # where many data-w-id elements are non-animated (containers, wrappers, static sections).
  fi

  # Hover CSS rules + video evidence — only required when hover interactions exist
  local has_hover_interactions="false"
  if [ -f "$REF_DIR/interactions-detected.json" ]; then
    has_hover_interactions=$(python3 -c "
import json
d = json.load(open('$REF_DIR/interactions-detected.json'))
interactions = d.get('interactions', [])
print('true' if any(i.get('trigger') == 'hover' for i in interactions) else 'false')
" 2>/dev/null || echo "false")
  fi

  if [ "$has_hover_interactions" = "true" ]; then
    # Hover CSS rules from live page (Step 5d-2b)
    check_file "$REF_DIR/hover-css-rules.json" "hover-css-rules.json (ALL :hover rules from live stylesheets)"
  else
    echo -e "  ${GREEN}✓${NC} hover-css-rules.json (skipped — no hover interactions detected)"
  fi

  if [ "$has_hover_interactions" = "true" ]; then
    # Hover video: advisory only — simple hover effects (color, underline) don't need video.
    # Complex effects (3D fold, morphing, text swap) should be recorded, but blocking here
    # prevents generation even for trivial hover styles.
    local hover_videos
    hover_videos=$({ find "$REF_DIR" -name "hover-*.webm" 2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$hover_videos" -ge 1 ]; then
      echo -e "  ${GREEN}✓${NC} Hover video recordings ($hover_videos videos)"
    else
      echo -e "  ${YELLOW}⚠${NC}  Hover video recordings: none found (advisory)"
      echo -e "    Record complex hover effects (3D fold, text swap, morphing) before verification."
      echo -e "    Simple hover (color, underline, scale) can skip video."
    fi
  else
    echo -e "  ${GREEN}✓${NC} Hover video recordings (skipped — no hover interactions detected)"
  fi

  # Dual-snapshot diff (Step 2.6-pre) — required if preloader detected
  if [ -f "$REF_DIR/interactions-detected.json" ]; then
    local has_preloader
    has_preloader=$(python3 -c "
import json
d = json.load(open('$REF_DIR/interactions-detected.json'))
print('true' if d.get('hasPreloader') else 'false')
" 2>/dev/null || echo "false")
    if [ "$has_preloader" = "true" ]; then
      check_file "$REF_DIR/dom-state-diff.json" "dom-state-diff.json (REQUIRED: site has preloader — dual-snapshot needed)"
    fi
  fi

  # Audit artifacts (skip for single-section scope)
  if [ -f "$REF_DIR/data-inventory.json" ] || [ -f "$REF_DIR/section-map.json" ]; then
    check_file "$REF_DIR/element-roles.json" "element-roles.json"
    check_file "$REF_DIR/element-groups.json" "element-groups.json"
    check_file "$REF_DIR/layout-decisions.json" "layout-decisions.json"
    check_file "$REF_DIR/component-map.json" "component-map.json"
  fi

  # Cross-check: section count in section-map vs component-map
  if [ -f "$REF_DIR/section-map.json" ] && [ -f "$REF_DIR/component-map.json" ]; then
    local section_count component_count
    section_count=$(python3 -c "import json; d=json.load(open('$REF_DIR/section-map.json')); print(d.get('totalCount', len(d.get('sections', []))))" 2>/dev/null || echo "0")
    component_count=$(python3 -c "import json; d=json.load(open('$REF_DIR/component-map.json')); print(d.get('sectionCount', len(d.get('sections', []))))" 2>/dev/null || echo "0")

    if [ "$section_count" != "0" ] && [ "$component_count" != "0" ] && [ "$section_count" != "$component_count" ]; then
      # Advisory only — intentional section merging or omission is valid.
      # The footer check below catches the most common real mistake.
      echo -e "  ${YELLOW}⚠${NC}  Section count: section-map=$section_count, component-map=$component_count (advisory)"
      echo -e "    If sections were intentionally merged/omitted, this is fine."
      echo -e "    If a section is missing, run section-audit.md Stage 1 again."
    else
      echo -e "  ${GREEN}✓${NC} Section count matches ($section_count sections)"
    fi

    # Check if footer exists in section-map but not in component-map
    local has_footer
    has_footer=$(python3 -c "import json; d=json.load(open('$REF_DIR/section-map.json')); print('true' if d.get('hasFooter') else 'false')" 2>/dev/null || echo "false")
    if [ "$has_footer" = "true" ]; then
      local footer_in_map
      footer_in_map=$(python3 -c "
import json
d=json.load(open('$REF_DIR/component-map.json'))
sections = d.get('sections', [])
has = any(s.get('sourceTag','').lower() == 'footer' or 'footer' in s.get('componentName','').lower() or 'footer' in s.get('sourceClass','').lower() for s in sections)
print('true' if has else 'false')
" 2>/dev/null || echo "unknown")
      if [ "$footer_in_map" = "false" ]; then
        echo -e "  ${RED}✗${NC} section-map.json has a <footer> but component-map.json does not include it"
        echo -e "    Add a Footer component to component-map.json before generating code."
        FAIL=$((FAIL + 1))
      fi
    fi
  fi
}

# ── Gate: post-implement (Phase 3 complete, ready for verification) ──
gate_post_implement() {
  echo "Gate: post-implement (Phase 3)"
  check_file "$REF_DIR/extracted.json" "extracted.json"
  check_file "$REF_DIR/transition-spec.json" "transition-spec.json"
  check_dir "$REF_DIR/static/ref" "static/ref screenshots" 5

  # Resolve project root once — used by hover, px-leak, and scroll checks
  # Priority: $CLAUDE_PROJECT_DIR → git root → walk-up (same as hooks and run-pipeline.sh)
  local project_root
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    project_root="$CLAUDE_PROJECT_DIR"
  else
    local _git_root
    _git_root=$(cd "$REF_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$_git_root" ]; then
      project_root="$_git_root"
    else
      # Walk-up: find highest directory containing tmp/ref/
      local _dir="$REF_DIR" _best=""
      while [ "$_dir" != "/" ]; do
        [ -d "$_dir/tmp/ref" ] && _best="$_dir"
        _dir=$(dirname "$_dir")
      done
      project_root="${_best:-$(dirname "$(dirname "$(dirname "$REF_DIR")")")}"
    fi
  fi

  # Hover rule coverage — count of :hover selectors in original vs all project CSS files combined
  if [ -f "$REF_DIR/hover-css-rules.json" ]; then
    TOTAL=$((TOTAL + 1))
    local orig_hover_count impl_hover_count
    orig_hover_count=$(python3 -c "import json; print(len(json.load(open('$REF_DIR/hover-css-rules.json'))))" 2>/dev/null || echo "0")
    # Sum :hover occurrences across ALL project CSS files (not just first) to avoid false negatives
    # when hover rules are split across globals.css, components.css, etc.
    impl_hover_count=$({ find "$project_root" -name "*.css" -not -path "*/node_modules/*" -not -path "*/.next/*" -exec grep -c ':hover' {} \; 2>/dev/null || true; } | awk '{s+=$1} END {print s+0}')
    if [ "$impl_hover_count" -ge "$orig_hover_count" ]; then
      echo -e "  ${GREEN}✓${NC} Hover rules: impl ($impl_hover_count across all CSS) >= original ($orig_hover_count)"
    else
      echo -e "  ${RED}✗${NC} Hover rules: impl ($impl_hover_count across all CSS) < original ($orig_hover_count) — missing hover transitions"
      FAIL=$((FAIL + 1))
    fi
  fi

  # px fontSize leak check (viewport-scaled sites)
  if [ -f "$REF_DIR/typography.json" ]; then
    local scaling
    scaling=$(python3 -c "import json; d=json.load(open('$REF_DIR/typography.json')); print(d.get('scalingSystem',''))" 2>/dev/null || echo "")
    if echo "$scaling" | grep -qiE 'viewport-scaled|em-based'; then
      TOTAL=$((TOTAL + 1))
      local px_leaks
      px_leaks=$(grep -rnE "fontSize.*[0-9]+(\.[0-9]+)?px" "$project_root/src/" "$project_root/app/" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" 2>/dev/null | grep -v 'clamp\|// px-override-ok\|node_modules\|\.next' | wc -l | tr -d ' ' || echo "0")
      if [ "$px_leaks" -gt 0 ]; then
        echo -e "  ${RED}✗${NC} $px_leaks px fontSize values in component files (viewport-scaled site requires em)"
        FAIL=$((FAIL + 1))
      else
        echo -e "  ${GREEN}✓${NC} No px fontSize leaks in component files"
      fi
    fi
  fi

  # scroll event listener check (smooth scroll sites only)
  # Rule: addEventListener('scroll') is correct for class-toggle animations (card stack, sticky header).
  #       RAF + getBoundingClientRect is required for progress-based transforms (parallax, smooth scroll).
  # We only flag scroll listeners that are combined with transform/translate — class toggles are fine.
  if [ -f "$REF_DIR/scroll-engine.json" ]; then
    local is_smooth_scroll
    is_smooth_scroll=$(python3 -c "
import json
d = json.load(open('$REF_DIR/scroll-engine.json'))
engine = d.get('engine', '')
print('true' if engine in ('lenis', 'locomotive', 'smooth-scroll', 'gsap-scroll-smoother') else 'false')
" 2>/dev/null || echo "false")
    if [ "$is_smooth_scroll" = "true" ]; then
      TOTAL=$((TOTAL + 1))
      # Only flag scroll listeners that also manipulate transform/translate (progress-based, not class-toggle)
      local scroll_transform_listeners
      scroll_transform_listeners=$(grep -rn "addEventListener.*scroll" "$project_root/src/" "$project_root/app/" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" 2>/dev/null | grep -v 'node_modules\|\.next\|classList\|class\|toggle\|hide\|active\|sticky' | wc -l | tr -d ' ' || echo "0")
      if [ "$scroll_transform_listeners" -gt 0 ]; then
        echo -e "  ${RED}✗${NC} $scroll_transform_listeners addEventListener('scroll') with transform logic on smooth-scroll site — use RAF + getBoundingClientRect"
        FAIL=$((FAIL + 1))
      else
        echo -e "  ${GREEN}✓${NC} No progress-based scroll listeners (smooth scroll compatible)"
      fi
    fi
  fi
  # Check that implementation is actually running
  if [ -f "$REF_DIR/.impl-url" ]; then
    local url
    url=$(cat "$REF_DIR/.impl-url")
    if curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
      echo -e "  ${GREEN}✓${NC} Implementation server responding at $url"
    else
      echo -e "  ${RED}✗${NC} Implementation server NOT responding at $url"
      FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
  fi
}

# ── Run gates ──
case "$GATE" in
  reference)     gate_reference ;;
  extraction)    gate_extraction ;;
  bundle)        gate_bundle ;;
  spec)          gate_spec ;;
  pre-generate)  gate_pre_generate ;;
  post-implement) gate_post_implement ;;
  all)
    gate_reference
    echo ""
    gate_extraction
    echo ""
    gate_bundle
    echo ""
    gate_spec
    echo ""
    gate_pre_generate
    echo ""
    gate_post_implement
    ;;
  *)
    echo "Unknown gate: $GATE"
    echo "Valid gates: reference | extraction | bundle | spec | pre-generate | post-implement | all"
    exit 2
    ;;
esac

# ── Result ──
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}BLOCKED${NC}: $FAIL/$TOTAL checks failed. Fix before proceeding."

  # ── Context injection: print relevant guidance from sub-docs ──
  SKILL_DIR="$(cd "$(dirname "$0")/../skills/ui-reverse-engineering" && pwd 2>/dev/null || echo "")"
  SKIP_ZONES="$SKILL_DIR/skip-zones.md"
  DIAGNOSIS="$SKILL_DIR/diagnosis.md"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Print the zone most relevant to this gate
  case "$GATE" in
    reference|extraction)
      echo "▶ RELEVANT GUIDANCE: skip-zones.md ZONE 1 (Extraction Gates)"
      echo ""
      if [ -f "$SKIP_ZONES" ]; then
        awk '/^## ZONE 1:/,/^## ZONE 2:/' "$SKIP_ZONES" | head -30
      fi
      ;;
    bundle|spec)
      echo "▶ RELEVANT GUIDANCE: skip-zones.md ZONE 1 (Extraction Gates — bundle/spec)"
      echo ""
      if [ -f "$SKIP_ZONES" ]; then
        awk '/^## ZONE 1:/,/^## ZONE 2:/' "$SKIP_ZONES" | grep -A5 "5c\|5d\|bundle\|spec" | head -20
      fi
      ;;
    pre-generate)
      echo "▶ RELEVANT GUIDANCE: skip-zones.md ZONE 1 + ZONE 2 (Extraction + Implementation Foundations)"
      echo ""
      if [ -f "$SKIP_ZONES" ]; then
        awk '/^## ZONE 1:/,/^## ZONE 3:/' "$SKIP_ZONES" | head -60
      fi
      ;;
    post-implement)
      echo "▶ RELEVANT GUIDANCE: skip-zones.md ZONE 3 + ZONE 4 (Interaction + Host CSS)"
      echo ""
      if [ -f "$SKIP_ZONES" ]; then
        awk '/^## ZONE 3:/,/^## ZONE 5:/' "$SKIP_ZONES" | head -60
      fi
      ;;
  esac

  echo ""
  echo "▶ IF YOU SEE A VISUAL MISMATCH AFTER FIXING — Root Cause quick-ref:"
  if [ -f "$DIAGNOSIS" ]; then
    awk '/^## Root Cause/,/^---/' "$DIAGNOSIS" | head -50
  else
    echo "  A: DOM Mismatch — computed-diff.sh + child order eval"
    echo "  B: CSS Cascade — grep host.css for ^button,^a"
    echo "  C: Missing Wrapper — check first child className"
    echo "  D: Wrong Element Type — check tagName, outerHTML"
    echo "  E: Animation — check transitionDuration, getAnimations()"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  exit 1
else
  echo -e "${GREEN}PASS${NC}: $TOTAL/$TOTAL checks passed. May proceed."
  exit 0
fi

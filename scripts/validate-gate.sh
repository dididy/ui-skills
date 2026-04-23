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

set -uo pipefail

REF_DIR="${1:?Usage: validate-gate.sh <ref-dir> <gate>}"
GATE="${2:?Usage: validate-gate.sh <ref-dir> <gate>  (reference|extraction|bundle|spec|pre-generate|post-implement|all)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

FAIL=0
TOTAL=0

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

check_dir() {
  local path="$1"
  local label="$2"
  local min_files="${3:-1}"
  TOTAL=$((TOTAL + 1))
  if [ -d "$path" ]; then
    local count
    count=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')
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
  check_dir "$REF_DIR/bundles" "bundles/ (downloaded JS chunks)" 3
  check_file "$REF_DIR/interactions-detected.json" "interactions-detected.json"
  check_file "$REF_DIR/scroll-engine.json" "scroll-engine.json"
}

# ── Gate: spec (Phase 2 Step 5d+5e — transition-spec written AND verified) ──
gate_spec() {
  echo "Gate: spec (Phase 2 Step 5d+5e)"
  check_file "$REF_DIR/transition-spec.json" "transition-spec.json (single source of truth)"

  # Validate structure if file exists and jq is available
  if [ -f "$REF_DIR/transition-spec.json" ] && command -v jq &>/dev/null; then
    TOTAL=$((TOTAL + 1))
    local trans_len
    trans_len=$(jq '.transitions | length' "$REF_DIR/transition-spec.json" 2>/dev/null || echo "0")
    if [ "$trans_len" -gt 0 ]; then
      echo -e "  ${GREEN}✓${NC} .transitions array ($trans_len entries)"
    else
      echo -e "  ${RED}✗${NC} .transitions array is empty or missing"
      FAIL=$((FAIL + 1))
    fi

    # Check first entry has required keys
    TOTAL=$((TOTAL + 1))
    local has_keys
    has_keys=$(jq '.transitions[0] | (has("id") and has("trigger") and has("bundle_branch"))' "$REF_DIR/transition-spec.json" 2>/dev/null || echo "false")
    if [ "$has_keys" = "true" ]; then
      echo -e "  ${GREEN}✓${NC} transitions[0] has id, trigger, bundle_branch"
    else
      echo -e "  ${RED}✗${NC} transitions[0] missing required keys (id, trigger, bundle_branch)"
      FAIL=$((FAIL + 1))
    fi
  fi

  # Step 5e: Capture verification — verify/ directory must exist with frames
  TOTAL=$((TOTAL + 1))
  local verify_frames
  verify_frames=$(find "$REF_DIR/verify" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
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
  check_file "$REF_DIR/transition-spec.json" "transition-spec.json"

  # Section map (from dom-extraction.md Step 2 enumeration)
  check_file "$REF_DIR/section-map.json" "section-map.json (semantic section enumeration)"

  # Multi-viewport sizing expressions (Step 4-C2)
  check_file "$REF_DIR/responsive/sizing-expressions.json" "sizing-expressions.json (multi-viewport element sizing)"

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

  # Hover CSS rules from live page (Step 5d-2b)
  check_file "$REF_DIR/hover-css-rules.json" "hover-css-rules.json (ALL :hover rules from live stylesheets)"

  # Hover video evidence (Step 5d-2d) — at least one hover video should exist
  TOTAL=$((TOTAL + 1))
  local hover_videos
  hover_videos=$(find "$REF_DIR" -name "hover-*.webm" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$hover_videos" -ge 1 ]; then
    echo -e "  ${GREEN}✓${NC} Hover video recordings ($hover_videos videos)"
  else
    echo -e "  ${RED}✗${NC} No hover video recordings found — hover effects may be missed"
    echo -e "    Record: agent-browser record start hover-<element>.webm → hover → record stop"
    FAIL=$((FAIL + 1))
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
      echo -e "  ${RED}✗${NC} Section count mismatch: section-map has $section_count sections, component-map has $component_count"
      echo -e "    You are likely MISSING a section (footer? header?). Run section-audit.md Stage 1 again."
      FAIL=$((FAIL + 1))
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

  # Hover rule coverage — every :hover rule from original must exist in project CSS
  if [ -f "$REF_DIR/hover-css-rules.json" ]; then
    TOTAL=$((TOTAL + 1))
    local orig_hover_count impl_hover_count
    orig_hover_count=$(python3 -c "import json; print(len(json.load(open('$REF_DIR/hover-css-rules.json'))))" 2>/dev/null || echo "0")
    # Find project CSS — search upward from REF_DIR for any .css with :hover
    local project_root
    project_root=$(cd "$REF_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$REF_DIR")/../..")
    local project_css
    project_css=$(find "$project_root" -name "*.css" -not -path "*/node_modules/*" -not -path "*/.next/*" -exec grep -l ':hover' {} \; 2>/dev/null | head -1)
    if [ -n "$project_css" ]; then
      impl_hover_count=$(grep -c ':hover' "$project_css" 2>/dev/null || echo "0")
      if [ "$impl_hover_count" -ge "$orig_hover_count" ]; then
        echo -e "  ${GREEN}✓${NC} Hover rules: impl ($impl_hover_count) >= original ($orig_hover_count)"
      else
        echo -e "  ${RED}✗${NC} Hover rules: impl ($impl_hover_count) < original ($orig_hover_count) — missing hover transitions"
        FAIL=$((FAIL + 1))
      fi
    fi
  fi

  # px fontSize leak check (viewport-scaled sites)
  if [ -f "$REF_DIR/typography.json" ]; then
    local scaling
    scaling=$(python3 -c "import json; d=json.load(open('$REF_DIR/typography.json')); print(d.get('scalingSystem',''))" 2>/dev/null || echo "")
    if echo "$scaling" | grep -qiE 'viewport-scaled|em-based'; then
      TOTAL=$((TOTAL + 1))
      local project_root
      project_root=$(cd "$REF_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$REF_DIR")/../..")
      local px_leaks
      px_leaks=$(grep -rnE "fontSize.*[0-9]+(\.[0-9]+)?px" "$project_root/src/" "$project_root/app/" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" 2>/dev/null | grep -v 'clamp\|// px-override-ok\|node_modules\|\.next' | wc -l | tr -d ' ')
      if [ "$px_leaks" -gt 0 ]; then
        echo -e "  ${RED}✗${NC} $px_leaks px fontSize values in component files (viewport-scaled site requires em)"
        FAIL=$((FAIL + 1))
      else
        echo -e "  ${GREEN}✓${NC} No px fontSize leaks in component files"
      fi
    fi
  fi

  # scroll event listener check (smooth scroll sites)
  if [ -f "$REF_DIR/scroll-engine.json" ]; then
    TOTAL=$((TOTAL + 1))
    local project_root
    project_root=$(cd "$REF_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$REF_DIR")/../..")
    local scroll_listeners
    scroll_listeners=$(grep -rn "addEventListener.*scroll" "$project_root/src/" "$project_root/app/" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" 2>/dev/null | grep -v 'node_modules\|\.next' | wc -l | tr -d ' ')
    if [ "$scroll_listeners" -gt 0 ]; then
      echo -e "  ${RED}✗${NC} $scroll_listeners addEventListener('scroll') — use RAF + getBoundingClientRect for smooth scroll compat"
      FAIL=$((FAIL + 1))
    else
      echo -e "  ${GREEN}✓${NC} No addEventListener('scroll') — smooth scroll compatible"
    fi
  fi
  # Check that implementation is actually running
  if [ -f "$REF_DIR/.impl-url" ]; then
    local url
    url=$(cat "$REF_DIR/.impl-url")
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
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
  exit 1
else
  echo -e "${GREEN}PASS${NC}: $TOTAL/$TOTAL checks passed. May proceed."
  exit 0
fi

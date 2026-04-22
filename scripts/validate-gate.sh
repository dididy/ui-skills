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

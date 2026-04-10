#!/usr/bin/env bash
# validate-gate.sh — Enforces extraction gates before proceeding
# Usage: bash scripts/validate-gate.sh <component-dir> <gate-name>
# Example: bash scripts/validate-gate.sh tmp/ref/9to5studio bundle
#          bash scripts/validate-gate.sh tmp/ref/9to5studio spec
#          bash scripts/validate-gate.sh tmp/ref/9to5studio pre-generate
#          bash scripts/validate-gate.sh tmp/ref/9to5studio post-implement

set -euo pipefail

DIR="${1:?Usage: validate-gate.sh <component-dir> <gate-name>}"
GATE="${2:?Usage: validate-gate.sh <component-dir> <gate-name>}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAIL=0

check_file() {
  local file="$1"
  local min_bytes="${2:-10}"
  local desc="${3:-}"

  if [ ! -f "$DIR/$file" ]; then
    echo -e "${RED}❌ MISSING${NC} $file${desc:+ — $desc}"
    FAIL=$((FAIL + 1))
    return 1
  fi

  local size
  size=$(wc -c < "$DIR/$file" | tr -d ' ')
  if [ "$size" -lt "$min_bytes" ]; then
    echo -e "${RED}❌ TOO SMALL${NC} $file (${size}B < ${min_bytes}B)${desc:+ — $desc}"
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo -e "${GREEN}✅${NC} $file (${size}B)"
  return 0
}

check_json_key() {
  local file="$1"
  local key="$2"
  local desc="${3:-}"

  if [ ! -f "$DIR/$file" ]; then
    echo -e "${RED}❌ MISSING${NC} $file${desc:+ — $desc}"
    FAIL=$((FAIL + 1))
    return 1
  fi

  if ! jq -e "$key" "$DIR/$file" > /dev/null 2>&1; then
    echo -e "${RED}❌ KEY MISSING${NC} $file → $key${desc:+ — $desc}"
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo -e "${GREEN}✅${NC} $file has $key"
  return 0
}

check_glob_count() {
  local pattern="$1"
  local min_count="$2"
  local desc="${3:-}"

  local count
  count=$(find "$DIR" -path "$DIR/$pattern" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -lt "$min_count" ]; then
    echo -e "${RED}❌ INSUFFICIENT${NC} $pattern — found $count, need ≥$min_count${desc:+ — $desc}"
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo -e "${GREEN}✅${NC} $pattern ($count files)"
  return 0
}

# ─────────────────────────────────────────────
# Gate: bundle — ALL chunks downloaded
# Run after Step 5c (bundle download)
# ─────────────────────────────────────────────
gate_bundle() {
  echo "═══ GATE: Bundle Analysis ═══"
  check_glob_count "bundles/*.js" 1 "Download ALL loaded chunks via performance API"

  # Each JS file should be > 1KB (not error pages)
  local small=0
  for f in "$DIR"/bundles/*.js; do
    [ -f "$f" ] || continue
    local sz
    sz=$(wc -c < "$f" | tr -d ' ')
    if [ "$sz" -lt 1024 ]; then
      echo -e "${YELLOW}⚠️  $(basename "$f") is only ${sz}B — may be an error page${NC}"
      small=$((small + 1))
    fi
  done
  if [ "$small" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $small chunk(s) suspiciously small${NC}"
  fi

  check_file "bundle-analysis.json" 50 "Chunk analysis (from download-chunks.sh)"
  check_file "element-animation-map.json" 50 "Bundle values mapped to DOM elements"
}

# ─────────────────────────────────────────────
# Gate: spec — transition-spec.json + bundle-map.json
# Run after Step 5d (transition spec)
# ─────────────────────────────────────────────
gate_spec() {
  echo "═══ GATE: Transition Spec ═══"
  check_file "bundle-map.json" 50 "Chunk → feature mapping"
  check_file "transition-spec.json" 100 "Per-transition spec"

  # Validate transition-spec structure
  check_json_key "transition-spec.json" '.transitions' "Must have transitions array"
  check_json_key "transition-spec.json" '.transitions[0].id' "Each entry needs id"
  check_json_key "transition-spec.json" '.transitions[0].trigger' "Each entry needs trigger"
  check_json_key "transition-spec.json" '.transitions[0].source_chunk' "Each entry needs source_chunk"
  check_json_key "transition-spec.json" '.transitions[0].bundle_branch' "Each entry needs bundle_branch"
  check_json_key "transition-spec.json" '.transitions[0].animation' "Each entry needs animation"

  # Reject placeholder values — bundle_branch must be specific
  if [ -f "$DIR/transition-spec.json" ]; then
    local branch
    branch=$(jq -r '.transitions[0].bundle_branch // ""' "$DIR/transition-spec.json" 2>/dev/null)
    if [ "$branch" = "unknown" ] || [ "$branch" = "" ] || [ "$branch" = "null" ]; then
      echo -e "${RED}❌ PLACEHOLDER${NC} transition-spec.json → bundle_branch is '$branch' — must specify which conditional branch (e.g. 'n=true, first visit')"
      FAIL=$((FAIL + 1))
    else
      echo -e "${GREEN}✅${NC} bundle_branch: $branch"
    fi

    # Check animation has at least duration or property
    local has_anim
    has_anim=$(jq -r '.transitions[0].animation | keys | length' "$DIR/transition-spec.json" 2>/dev/null || echo "0")
    if [ "$has_anim" -lt 2 ]; then
      echo -e "${RED}❌ INCOMPLETE${NC} transition-spec.json → animation object has < 2 keys"
      FAIL=$((FAIL + 1))
    fi
  fi

  # Validate bundle-map structure
  check_json_key "bundle-map.json" '.chunks' "Must have chunks array"
  check_json_key "bundle-map.json" '.chunks[0].file' "Each chunk needs file"
  check_json_key "bundle-map.json" '.chunks[0].contains' "Each chunk needs contains list"
}

# ─────────────────────────────────────────────
# Gate: pre-generate — everything needed before code generation
# Run before Step 7 (component generation)
# ─────────────────────────────────────────────
gate_pre_generate() {
  echo "═══ GATE: Pre-Generation ═══"

  # Critical extraction artifacts (Step 2-6)
  check_file "structure.json" 100
  check_file "styles.json" 100
  check_file "interactions-detected.json" 10
  check_file "scroll-engine.json" 10 "Scroll engine type"
  check_file "extracted.json" 100

  # Transition spec (HARD BLOCK — #1 source of errors without it)
  check_file "transition-spec.json" 100 "HARD BLOCK — cannot generate without this"
  check_file "bundle-map.json" 50

  # Reference frames
  local frame_count
  frame_count=$(find "$DIR" -name "*.png" -path "*/ref/*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$frame_count" -lt 1 ]; then
    echo -e "${RED}❌ NO REFERENCE FRAMES${NC} — capture original before implementing"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}✅${NC} Reference frames ($frame_count files)"
  fi
}

# ─────────────────────────────────────────────
# Gate: post-implement — verify after each transition
# Run after implementing a transition
# ─────────────────────────────────────────────
gate_post_implement() {
  echo "═══ GATE: Post-Implementation ═══"

  # Check comparison screenshots exist
  local compare_count
  compare_count=$(find "$DIR" -name "compare-*.png" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$compare_count" -lt 2 ]; then
    echo -e "${RED}❌ NO COMPARISON SCREENSHOTS${NC} — must compare ref vs impl BEFORE telling user to check"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}✅${NC} Comparison screenshots ($compare_count files)"
  fi
}

# ─────────────────────────────────────────────
# Run the requested gate
# ─────────────────────────────────────────────
case "$GATE" in
  bundle)       gate_bundle ;;
  spec)         gate_spec ;;
  pre-generate) gate_pre_generate ;;
  post-implement) gate_post_implement ;;
  all)
    gate_bundle
    echo ""
    gate_spec
    echo ""
    gate_pre_generate
    ;;
  *)
    echo "Unknown gate: $GATE"
    echo "Available: bundle | spec | pre-generate | post-implement | all"
    exit 1
    ;;
esac

# ─────────────────────────────────────────────
# Final verdict
# ─────────────────────────────────────────────
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}⛔ BLOCKED — $FAIL check(s) failed. Fix before proceeding.${NC}"
  exit 1
else
  echo -e "${GREEN}✅ GATE PASSED${NC}"
  exit 0
fi

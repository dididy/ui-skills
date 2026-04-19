#!/usr/bin/env bash
# auto-verify.sh — Single verification command that runs all checks
#
# Usage: bash auto-verify.sh <session> <orig-url> <impl-url> <ref-dir>
#
# Runs in order:
#   D0: layout-health-check (structural comparison)
#   C:  batch-scroll + AE comparison (pixel comparison)
#   Gate: post-implement validation
#
# Exit: 0 = all pass, 1 = failures found
#
# DO NOT run individual checks selectively. This script exists to prevent
# cherry-picking passing checks while ignoring failures.

set -uo pipefail

SESSION="${1:?Usage: auto-verify.sh <session> <orig-url> <impl-url> <ref-dir>}"
ORIG_URL="${2:?}"
IMPL_URL="${3:?}"
REF_DIR="${4:?}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve visual-debug scripts location
# Try: sibling skill dir, then installed skills, then fallback find
VISUAL_DEBUG_SCRIPTS=""
for candidate in \
  "$(dirname "$SCRIPT_DIR")/skills/visual-debug/scripts" \
  "$HOME/.claude/skills/visual-debug/scripts"; do
  if [ -d "$candidate" ] && [ -f "$candidate/ae-compare.sh" ]; then
    VISUAL_DEBUG_SCRIPTS="$candidate"
    break
  fi
done
if [ -z "$VISUAL_DEBUG_SCRIPTS" ]; then
  VISUAL_DEBUG_SCRIPTS="$(find "$HOME/.claude/skills" -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)"
fi
if [ -z "$VISUAL_DEBUG_SCRIPTS" ]; then
  echo "ERROR: visual-debug scripts not found (ae-compare.sh, batch-compare.sh)"
  echo "Expected at: $(dirname "$SCRIPT_DIR")/skills/visual-debug/scripts/"
  exit 2
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_CHECKS=0
TOTAL_FAIL=0

run_check() {
  local label="$1"
  shift
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  echo -e "\n${BOLD}[$TOTAL_CHECKS] $label${NC}"
  if "$@"; then
    echo -e "  ${GREEN}PASS${NC}"
  else
    echo -e "  ${RED}FAIL${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
}

echo -e "${BOLD}═══ auto-verify.sh ═══${NC}"
echo "Session: $SESSION"
echo "Original: $ORIG_URL"
echo "Implementation: $IMPL_URL"
echo "Ref dir: $REF_DIR"

# ── Pre-check: ensure both URLs are reachable ──
echo -e "\n${BOLD}Pre-check: URL reachability${NC}"
for url in "$ORIG_URL" "$IMPL_URL"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    echo -e "  ${GREEN}✓${NC} $url → $code"
  else
    echo -e "  ${RED}✗${NC} $url → $code"
    echo -e "${RED}BLOCKED: Cannot reach $url. Start the server first.${NC}"
    exit 1
  fi
done

# ── D0: Layout health check ──
if [ -f "$VISUAL_DEBUG_SCRIPTS/layout-health-check.sh" ]; then
  run_check "D0: Layout health check" \
    bash "$VISUAL_DEBUG_SCRIPTS/layout-health-check.sh" "$SESSION" "$ORIG_URL" "$IMPL_URL" "$REF_DIR"
else
  echo -e "\n${YELLOW}SKIP: layout-health-check.sh not found at $VISUAL_DEBUG_SCRIPTS${NC}"
fi

# ── C: Capture impl screenshots + batch comparison ──
echo -e "\n${BOLD}Capturing implementation screenshots...${NC}"
mkdir -p "$REF_DIR/static/impl" "$REF_DIR/static/diff"

# Capture impl at same scroll positions as ref
agent-browser open "$IMPL_URL" --session "${SESSION}-verify" 2>/dev/null
agent-browser set viewport 1440 900 --session "${SESSION}-verify" 2>/dev/null
sleep 5

for pct in 0 10 20 30 40 50 60 70 80 90 100; do
  agent-browser eval "(()=>{const h=document.documentElement.scrollHeight-window.innerHeight;window.scrollTo(0,h*$pct/100);return $pct})()" --session "${SESSION}-verify" 2>/dev/null
  sleep 1
  agent-browser screenshot "$REF_DIR/static/impl/${pct}pct.png" --session "${SESSION}-verify" 2>/dev/null
done

agent-browser close --session "${SESSION}-verify" 2>/dev/null

# Run batch comparison
if [ -f "$VISUAL_DEBUG_SCRIPTS/batch-compare.sh" ]; then
  run_check "C: Batch AE comparison (ref vs impl)" \
    bash "$VISUAL_DEBUG_SCRIPTS/batch-compare.sh" "$REF_DIR"
else
  echo -e "\n${YELLOW}SKIP: batch-compare.sh not found${NC}"
  # Fallback: manual AE comparison
  if [ -f "$VISUAL_DEBUG_SCRIPTS/ae-compare.sh" ]; then
    echo -e "\n${BOLD}Fallback: individual AE comparisons${NC}"
    PASS_COUNT=0
    FAIL_COUNT=0
    for ref_img in "$REF_DIR"/static/ref/*.png; do
      fname=$(basename "$ref_img")
      impl_img="$REF_DIR/static/impl/$fname"
      if [ -f "$impl_img" ]; then
        result=$(bash "$VISUAL_DEBUG_SCRIPTS/ae-compare.sh" "$ref_img" "$impl_img" "$REF_DIR/static/diff/$fname" 2>/dev/null)
        status=$(echo "$result" | grep -o 'STATUS=[A-Z]*' | cut -d= -f2)
        ae=$(echo "$result" | grep -o 'AE=[0-9]*' | cut -d= -f2)
        if [ "$status" = "PASS" ]; then
          echo -e "  ${GREEN}✓${NC} $fname AE=$ae"
          PASS_COUNT=$((PASS_COUNT + 1))
        else
          echo -e "  ${RED}✗${NC} $fname AE=$ae"
          FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
      fi
    done
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ "$FAIL_COUNT" -gt 0 ]; then
      echo -e "  ${RED}$FAIL_COUNT/$((PASS_COUNT + FAIL_COUNT)) screenshots FAIL${NC}"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
    else
      echo -e "  ${GREEN}All $PASS_COUNT screenshots PASS${NC}"
    fi
  fi
fi

# ── Post-implement gate ──
run_check "Gate: post-implement" \
  bash "$SCRIPT_DIR/validate-gate.sh" "$REF_DIR" post-implement

# ── Summary ──
echo -e "\n${BOLD}═══ RESULT ═══${NC}"
if [ "$TOTAL_FAIL" -gt 0 ]; then
  echo -e "${RED}FAIL: $TOTAL_FAIL/$TOTAL_CHECKS checks failed.${NC}"
  echo -e "${YELLOW}DO NOT declare done. Diagnose each failure, fix, and re-run.${NC}"
  exit 1
else
  echo -e "${GREEN}PASS: $TOTAL_CHECKS/$TOTAL_CHECKS checks passed.${NC}"
  echo -e "Proceed to Phase D (pixel-perfect visual gate) for final sign-off."
  exit 0
fi

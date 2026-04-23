#!/usr/bin/env bash
# dssim-compare.sh — Structural visual similarity comparison using DSSIM
#
# Usage: bash dssim-compare.sh <dir> [threshold]
#
# Complements ae-compare/batch-compare:
#   AE    = "how many pixels differ" (catches pixel-level errors)
#   DSSIM = "how structurally different" (catches layout/composition errors)
#
# DSSIM scale (from testing):
#   0.00       = identical files
#   0.01-0.20  = same content, minor rendering differences
#   0.20-0.50  = similar structure, noticeable content differences
#   0.50-0.80  = significant structural differences
#   0.80+      = completely different pages
#
# Use AFTER AE comparison to catch structural issues that AE misses
# (e.g., AE=1 but wrong section rendered due to matching colors)

set -uo pipefail

DIR="${1:?Usage: dssim-compare.sh <dir> [threshold]}"
THRESHOLD="${2:-0.50}"

REF_DIR="$DIR/static/ref"
IMPL_DIR="$DIR/static/impl"

if ! command -v dssim &>/dev/null; then
  echo "ERROR: dssim not installed. Run: brew install dssim"
  exit 2
fi

if [ ! -d "$REF_DIR" ]; then echo "ERROR: $REF_DIR not found"; exit 1; fi
if [ ! -d "$IMPL_DIR" ]; then echo "ERROR: $IMPL_DIR not found"; exit 1; fi

# Clean up resized temp files on exit
TMPFILES=()
cleanup() { rm -f "${TMPFILES[@]}" 2>/dev/null; }
trap cleanup EXIT

echo "| Position | DSSIM | Threshold | Status |"
echo "|----------|-------|-----------|--------|"

PASS=0
FAIL=0
TOTAL=0

for REF_FILE in "$REF_DIR"/*.png; do
  BASENAME=$(basename "$REF_FILE")
  IMPL_FILE="$IMPL_DIR/$BASENAME"
  POS="${BASENAME%.png}"

  if [ ! -f "$IMPL_FILE" ]; then
    echo "| $POS | — | — | ⚠️ MISSING |"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi

  # Resize impl if dimensions differ
  REF_SIZE=$(identify -format "%wx%h" "$REF_FILE" 2>/dev/null)
  IMPL_SIZE=$(identify -format "%wx%h" "$IMPL_FILE" 2>/dev/null)
  COMPARE_IMPL="$IMPL_FILE"
  if [ "$REF_SIZE" != "$IMPL_SIZE" ]; then
    W=$(echo "$REF_SIZE" | cut -dx -f1)
    H=$(echo "$REF_SIZE" | cut -dx -f2)
    RESIZED=$(mktemp /tmp/dssim-resized-XXXXXX.png)
    convert "$IMPL_FILE" -resize "${W}x${H}!" "$RESIZED" 2>/dev/null
    TMPFILES+=("$RESIZED")
    COMPARE_IMPL="$RESIZED"
  fi

  SCORE=$(dssim "$REF_FILE" "$COMPARE_IMPL" 2>/dev/null | awk '{print $1}')
  SCORE="${SCORE:-999}"

  # Use awk for float comparison
  STATUS=$(echo "$SCORE $THRESHOLD" | awk '{if ($1 <= $2) print "PASS"; else print "FAIL"}')

  if [ "$STATUS" = "PASS" ]; then
    echo "| $POS | $SCORE | $THRESHOLD | ✅ |"
    PASS=$((PASS + 1))
  else
    echo "| $POS | $SCORE | $THRESHOLD | ❌ |"
    FAIL=$((FAIL + 1))
  fi

  TOTAL=$((TOTAL + 1))
done

echo ""
echo "**Result: $PASS/$TOTAL PASS, $FAIL FAIL** (threshold=$THRESHOLD)"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "DSSIM FAIL means structural/compositional mismatch — not just pixel noise."
  echo "Investigate: missing sections, wrong layout, content misalignment."
  exit 1
fi

exit 0

#!/usr/bin/env bash
# batch-compare.sh — Compare all ref/impl screenshot pairs, output markdown table
# Usage: bash batch-compare.sh <dir> [threshold]
#
# Expects: <dir>/static/ref/*.png and <dir>/static/impl/*.png
# with matching filenames (e.g., 0pct.png, 10pct.png, ...)
#
# Output: Markdown table of AE scores + PASS/FAIL status
# Only FAIL rows need investigation.

set -uo pipefail

DIR="${1:?Usage: batch-compare.sh <dir> [threshold]}"
THRESHOLD="${2:-500}"

REF_DIR="$DIR/static/ref"
IMPL_DIR="$DIR/static/impl"
DIFF_DIR="$DIR/static/diff"

if [ ! -d "$REF_DIR" ]; then echo "ERROR: $REF_DIR not found"; exit 1; fi
if [ ! -d "$IMPL_DIR" ]; then echo "ERROR: $IMPL_DIR not found"; exit 1; fi

mkdir -p "$DIFF_DIR"

echo "| Position | AE | Status | Region |"
echo "|----------|-----|--------|--------|"

PASS=0
FAIL=0
TOTAL=0

for REF_FILE in "$REF_DIR"/*.png; do
  BASENAME=$(basename "$REF_FILE")
  IMPL_FILE="$IMPL_DIR/$BASENAME"
  DIFF_FILE="$DIFF_DIR/$BASENAME"
  POS="${BASENAME%.png}"

  if [ ! -f "$IMPL_FILE" ]; then
    echo "| $POS | — | ⚠️ MISSING | impl not found |"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi

  # Check size match, resize if needed
  REF_SIZE=$(identify -format "%wx%h" "$REF_FILE" 2>/dev/null)
  IMPL_SIZE=$(identify -format "%wx%h" "$IMPL_FILE" 2>/dev/null)

  COMPARE_IMPL="$IMPL_FILE"
  if [ "$REF_SIZE" != "$IMPL_SIZE" ]; then
    W=$(echo "$REF_SIZE" | cut -dx -f1)
    H=$(echo "$REF_SIZE" | cut -dx -f2)
    RESIZED="/tmp/batch-compare-resized-${BASENAME}"
    convert "$IMPL_FILE" -resize "${W}x${H}!" "$RESIZED" 2>/dev/null
    COMPARE_IMPL="$RESIZED"
  fi

  # AE diff
  AE=$(compare -metric AE "$REF_FILE" "$COMPARE_IMPL" "$DIFF_FILE" 2>&1 || true)
  AE=$(echo "$AE" | grep -oE '^[0-9]+' | head -1)
  AE="${AE:-0}"

  if [ "$AE" -le "$THRESHOLD" ]; then
    echo "| $POS | $AE | ✅ | — |"
    PASS=$((PASS + 1))
  else
    # Identify worst region
    H_PX=$(identify -format "%h" "$REF_FILE" 2>/dev/null)
    W_PX=$(identify -format "%w" "$REF_FILE" 2>/dev/null)
    THIRD=$((H_PX / 3))
    WORST=""
    WORST_AE=0
    for PART in top mid bot; do
      case $PART in
        top) OFF=0 ;;
        mid) OFF=$THIRD ;;
        bot) OFF=$((THIRD * 2)) ;;
      esac
      PAE=$(compare -metric AE \
        -extract "${W_PX}x${THIRD}+0+${OFF}" "$REF_FILE" \
        -extract "${W_PX}x${THIRD}+0+${OFF}" "$COMPARE_IMPL" \
        /dev/null 2>&1 || true)
      PAE=$(echo "$PAE" | grep -oE '^[0-9]+' | head -1)
      PAE="${PAE:-0}"
      if [ "$PAE" -gt "$WORST_AE" ]; then WORST_AE=$PAE; WORST=$PART; fi
    done
    echo "| $POS | $AE | ❌ | $WORST ($WORST_AE) |"
    FAIL=$((FAIL + 1))
  fi

  TOTAL=$((TOTAL + 1))
done

echo ""
echo "**Result: $PASS/$TOTAL PASS, $FAIL FAIL** (threshold=$THRESHOLD)"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Investigate FAIL positions by reading diff images:"
  echo "\`\`\`"
  for DIFF_FILE in "$DIFF_DIR"/*.png; do
    BASENAME=$(basename "$DIFF_FILE")
    echo "Read $DIFF_FILE   # only if ❌ above"
  done
  echo "\`\`\`"

  # Anti-rationalization enforcement
  if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "═══ MANDATORY DIAGNOSIS ═══"
    echo "⛔ $FAIL position(s) FAILED. Each FAIL must be diagnosed before proceeding."
    echo ""
    echo "DO NOT rationalize FAILs as 'content differences' or 'expected mismatch'."
    echo "DO NOT proceed to declare any section 'done' until all FAILs are resolved or diagnosed."
    echo ""
    echo "For each FAIL position:"
    echo "  1. Read the diff image (listed above)"
    echo "  2. Run layout health check:"
    echo "     bash \"\$(dirname \"\$0\")/layout-health-check.sh\" <session> <orig-url> <impl-url>"
    echo "  3. Run computed-diff on elements in the failing region:"
    echo "     bash \"\$(dirname \"\$0\")/computed-diff.sh\" <session> <orig-url> <impl-url> <selectors>"
    echo ""
    echo "Only after all FAILs have documented root causes can verification proceed."
  fi

  exit 1
fi

exit 0

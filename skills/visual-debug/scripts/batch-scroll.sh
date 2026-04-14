#!/usr/bin/env bash
# batch-scroll.sh — Capture screenshots at identical scroll positions from two URLs
# Usage: bash batch-scroll.sh <original-url> <impl-url> <session> [output-dir]
#
# Captures at 0%, 10%, 20%, ..., 100% scroll progress from both sites.
# Uses content-anchored alignment: measures total scroll height per site,
# converts percentage to absolute scroll position.
#
# Output: <dir>/static/ref/*.png and <dir>/static/impl/*.png

set -euo pipefail

ORIG_URL="${1:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
IMPL_URL="${2:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
SESSION="${3:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
DIR="${4:-tmp/ref/visual-debug}"

mkdir -p "$DIR/static/ref" "$DIR/static/impl" "$DIR/static/diff"

POSITIONS=(0 10 20 30 40 50 60 70 80 90 100)

echo "═══ Batch Scroll Capture ═══"
echo "Original: $ORIG_URL"
echo "Implementation: $IMPL_URL"
echo ""

# Phase 1: Capture original
echo "▸ Capturing original..."
agent-browser --session "$SESSION" open "$ORIG_URL" 2>&1 | head -1
agent-browser --session "$SESSION" set viewport 1440 900 2>&1 > /dev/null
agent-browser --session "$SESSION" wait 6000 2>&1 > /dev/null

# Get total height
ORIG_HEIGHT=$(agent-browser --session "$SESSION" eval "(() => document.documentElement.scrollHeight)()" 2>&1 | tr -d '"')
echo "  Total height: ${ORIG_HEIGHT}px"

for PCT in "${POSITIONS[@]}"; do
  Y=$(echo "$ORIG_HEIGHT * $PCT / 100" | bc 2>/dev/null || echo "0")
  agent-browser --session "$SESSION" eval "(() => { window.scrollTo(0, $Y); return $Y; })()" 2>&1 > /dev/null
  sleep 0.5
  agent-browser --session "$SESSION" screenshot "$DIR/static/ref/${PCT}pct.png" 2>&1 > /dev/null
  echo "  ✓ ${PCT}% (y=$Y)"
done

# Phase 2: Capture implementation
echo ""
echo "▸ Capturing implementation..."
agent-browser --session "$SESSION" open "$IMPL_URL" 2>&1 | head -1
agent-browser --session "$SESSION" set viewport 1440 900 2>&1 > /dev/null
agent-browser --session "$SESSION" wait 6000 2>&1 > /dev/null

IMPL_HEIGHT=$(agent-browser --session "$SESSION" eval "(() => document.documentElement.scrollHeight)()" 2>&1 | tr -d '"')
echo "  Total height: ${IMPL_HEIGHT}px"

for PCT in "${POSITIONS[@]}"; do
  Y=$(echo "$IMPL_HEIGHT * $PCT / 100" | bc 2>/dev/null || echo "0")
  agent-browser --session "$SESSION" eval "(() => { window.scrollTo(0, $Y); return $Y; })()" 2>&1 > /dev/null
  sleep 0.5
  agent-browser --session "$SESSION" screenshot "$DIR/static/impl/${PCT}pct.png" 2>&1 > /dev/null
  echo "  ✓ ${PCT}% (y=$Y)"
done

echo ""
echo "▸ Captured ${#POSITIONS[@]} positions × 2 sites = $((${#POSITIONS[@]} * 2)) screenshots"
echo "  Run: bash scripts/batch-compare.sh $DIR"

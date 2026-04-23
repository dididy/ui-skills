#!/usr/bin/env bash
# batch-scroll.sh — Capture screenshots at identical scroll positions from two URLs
# Usage: bash batch-scroll.sh <original-url> <impl-url> <session> [output-dir]
#
# Captures at 0%, 10%, 20%, ..., 100% scroll progress from both sites.
# Uses interleaved capture: ref 0% → impl 0% → ref 10% → impl 10% → ...
# This eliminates carousel/animation drift between the two sides.
#
# Uses content-anchored alignment: measures total scroll height per site,
# converts percentage to absolute scroll position.
#
# Output: <dir>/static/ref/*.png and <dir>/static/impl/*.png

set -euo pipefail

ORIG_URL="${1:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
IMPL_URL="${2:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
SESSION="${3:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
DIR="${4:-tmp/ref/visual-debug}"

VIEW_W="${VIEW_W:-1440}"
VIEW_H="${VIEW_H:-900}"

SESSION_REF="${SESSION}-ref"
SESSION_IMPL="${SESSION}-impl"

cleanup_browsers() {
  agent-browser close --session "$SESSION_REF" 2>/dev/null
  agent-browser close --session "$SESSION_IMPL" 2>/dev/null
}
trap cleanup_browsers EXIT

mkdir -p "$DIR/static/ref" "$DIR/static/impl" "$DIR/static/diff"

POSITIONS=(0 10 20 30 40 50 60 70 80 90 100)

echo "═══ Batch Scroll Capture (interleaved) ═══"
echo "Original: $ORIG_URL"
echo "Implementation: $IMPL_URL"
echo ""

# Open both sites in parallel sessions
# Add cache-buster to original URL to avoid stale server-side state (e.g., carousel position from cookies)
CACHE_BUST="_vcb=$(date +%s)"
if echo "$ORIG_URL" | grep -q '?'; then
  ORIG_URL_CB="${ORIG_URL}&${CACHE_BUST}"
else
  ORIG_URL_CB="${ORIG_URL}?${CACHE_BUST}"
fi

echo "▸ Opening both sites..."
agent-browser --session "$SESSION_REF" open "$ORIG_URL_CB" 2>&1 | head -1
agent-browser --session "$SESSION_IMPL" open "$IMPL_URL" 2>&1 | head -1

agent-browser --session "$SESSION_REF" set viewport $VIEW_W $VIEW_H 2>&1 > /dev/null
agent-browser --session "$SESSION_IMPL" set viewport $VIEW_W $VIEW_H 2>&1 > /dev/null

# Wait for page JS to fully initialize (GSAP sets section heights, ScrollTrigger binds).
agent-browser --session "$SESSION_REF" wait 6000 2>&1 > /dev/null
agent-browser --session "$SESSION_IMPL" wait 6000 2>&1 > /dev/null

# Smart carousel freeze: find and pause only carousel/auto-rotation timers.
# Approach: intercept setInterval calls ≥2s (carousel-like), without killing existing GSAP intervals.
# We monkey-patch setInterval to block FUTURE carousel registrations, then selectively pause
# GSAP timelines that control carousel rotation (identified by their repeat/yoyo pattern).
SMART_FREEZE='(() => {
  // 1. Block future carousel-like intervals (≥2s period)
  const _si = window.setInterval;
  window.setInterval = function(fn, ms) {
    if (typeof ms === "number" && ms >= 2000) return -1;
    return _si.apply(window, arguments);
  };
  // 2. Pause GSAP carousel timelines (if gsap exists)
  let gsapPaused = 0;
  if (window.gsap && window.gsap.globalTimeline) {
    const children = window.gsap.globalTimeline.getChildren(true, false, true);
    children.forEach(function(tl) {
      // Carousel timelines typically repeat infinitely or have long duration with no scroll trigger
      if (tl.repeat && tl.repeat() === -1) { tl.pause(); gsapPaused++; }
    });
  }
  // 3. Freeze carousel DOM mutations (classList + inline style)
  // GSAP changes both CSS classes AND inline styles (backgroundColor, opacity, transform)
  try {
    // Freeze classList on carousel and its children
    var frozen = 0;
    document.querySelectorAll("section[class*=carousel], section[class*=carousel] *, [class*=overlay] *, [class*=card] *").forEach(function(el) {
      if (el.classList) {
        el.classList.remove = function() {};
        el.classList.add = function() {};
        el.classList.toggle = function() {};
      }
    });
    // Snapshot current inline styles on carousel section + overlay card
    // and make style.cssText a no-op for these elements
    var carouselSection = document.querySelector("section[class*=carousel]");
    if (carouselSection) {
      var snap = carouselSection.getAttribute("style") || "";
      var origSet = carouselSection.style.setProperty.bind(carouselSection.style);
      Object.defineProperty(carouselSection.style, "cssText", { set: function(){}, get: function(){ return snap; } });
      // Also freeze backgroundColor specifically
      Object.defineProperty(carouselSection.style, "backgroundColor", { set: function(){}, get: function(){ return getComputedStyle(carouselSection).backgroundColor; } });
      frozen++;
    }
    // Freeze overlay card face opacity changes
    document.querySelectorAll("[class*=program-service_]").forEach(function(face) {
      var curOp = getComputedStyle(face).opacity;
      Object.defineProperty(face.style, "opacity", { set: function(){}, get: function(){ return curOp; } });
      frozen++;
    });
    gsapPaused = frozen > 0 ? -frozen : 0;
  } catch(e) { gsapPaused = -999; }
  return "smart-freeze (frozen=" + gsapPaused + ")";
})()'

agent-browser --session "$SESSION_REF" eval "$SMART_FREEZE" 2>&1 | sed 's/^/  Ref: /'
agent-browser --session "$SESSION_IMPL" eval "$SMART_FREEZE" 2>&1 | sed 's/^/  Impl: /'

# Get total heights
ORIG_HEIGHT=$(agent-browser --session "$SESSION_REF" eval "(() => document.documentElement.scrollHeight)()" 2>&1 | tr -d '"')
IMPL_HEIGHT=$(agent-browser --session "$SESSION_IMPL" eval "(() => document.documentElement.scrollHeight)()" 2>&1 | tr -d '"')

if ! [[ "$ORIG_HEIGHT" =~ ^[0-9]+$ ]] || ! [[ "$IMPL_HEIGHT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Failed to extract page heights (orig=$ORIG_HEIGHT, impl=$IMPL_HEIGHT)"
  exit 1
fi

echo "  Ref height:  ${ORIG_HEIGHT}px"
echo "  Impl height: ${IMPL_HEIGHT}px"

# Height ratio check
if command -v bc &>/dev/null; then
  RATIO=$(echo "scale=2; $IMPL_HEIGHT / $ORIG_HEIGHT" | bc 2>/dev/null || echo "1.00")
  if (( $(echo "$RATIO > 1.30" | bc -l 2>/dev/null || echo 0) )); then
    echo ""
    echo "  ⛔ HEIGHT MISMATCH: impl is ${RATIO}x taller than ref"
    echo "  Run: bash \"\$(dirname \"\$0\")/layout-health-check.sh\" $SESSION $ORIG_URL $IMPL_URL"
    echo ""
  elif (( $(echo "$RATIO < 0.70" | bc -l 2>/dev/null || echo 0) )); then
    echo ""
    echo "  ⛔ HEIGHT MISMATCH: impl is ${RATIO}x shorter than ref"
    echo "  Run: bash \"\$(dirname \"\$0\")/layout-health-check.sh\" $SESSION $ORIG_URL $IMPL_URL"
    echo ""
  fi
fi

echo ""

# Interleaved capture: ref N% → impl N% for each position
echo "▸ Capturing (interleaved)..."
for PCT in "${POSITIONS[@]}"; do
  Y_REF=$(echo "$ORIG_HEIGHT * $PCT / 100" | bc 2>/dev/null || echo "0")
  Y_IMPL=$(echo "$IMPL_HEIGHT * $PCT / 100" | bc 2>/dev/null || echo "0")

  # Scroll both
  agent-browser --session "$SESSION_REF" eval "(() => { window.scrollTo(0, $Y_REF); return $Y_REF; })()" 2>&1 > /dev/null
  agent-browser --session "$SESSION_IMPL" eval "(() => { window.scrollTo(0, $Y_IMPL); return $Y_IMPL; })()" 2>&1 > /dev/null

  sleep 0.5

  # Screenshot both
  agent-browser --session "$SESSION_REF" screenshot "$DIR/static/ref/${PCT}pct.png" 2>&1 > /dev/null
  agent-browser --session "$SESSION_IMPL" screenshot "$DIR/static/impl/${PCT}pct.png" 2>&1 > /dev/null

  echo "  ✓ ${PCT}% (ref y=$Y_REF, impl y=$Y_IMPL)"
done

echo ""
echo "▸ Captured ${#POSITIONS[@]} positions × 2 sites = $((${#POSITIONS[@]} * 2)) screenshots"
echo "  Run: bash \"\$(dirname \"\$0\")/batch-compare.sh\" $DIR"

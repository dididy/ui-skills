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
#
# Options (env vars):
#   VIEW_W=1440        Viewport width (default: 1440)
#   VIEW_H=900         Viewport height (default: 900)
#   NO_IMAGES=1        Hide all images/video via CSS + Blink flag — reduces AE noise from dynamic content (default: 0)
#   WAIT_INIT=6000     Page settle wait in ms after open (default: 6000)
#   WAIT_SCROLL=500    Wait in ms between scroll and screenshot (default: 500)

set -euo pipefail

ORIG_URL="${1:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
IMPL_URL="${2:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
SESSION="${3:?Usage: batch-scroll.sh <original-url> <impl-url> <session> [output-dir]}"
DIR="${4:-tmp/ref/visual-debug}"

VIEW_W="${VIEW_W:-1440}"
VIEW_H="${VIEW_H:-900}"
NO_IMAGES="${NO_IMAGES:-0}"
WAIT_INIT="${WAIT_INIT:-6000}"
WAIT_SCROLL="${WAIT_SCROLL:-500}"

SESSION_REF="${SESSION}-ref"
SESSION_IMPL="${SESSION}-impl"
BROWSER_ARGS=""
if [ "${NO_IMAGES:-0}" = "1" ]; then
  BROWSER_ARGS="--blink-settings=imagesEnabled=false"
fi

cleanup_browsers() {
  agent-browser --session "$SESSION_REF" close 2>/dev/null || true
  agent-browser --session "$SESSION_IMPL" close 2>/dev/null || true
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
agent-browser --session "$SESSION_REF" ${BROWSER_ARGS:+--args "$BROWSER_ARGS"} open "$ORIG_URL_CB" 2>&1 | head -1
agent-browser --session "$SESSION_IMPL" ${BROWSER_ARGS:+--args "$BROWSER_ARGS"} open "$IMPL_URL" 2>&1 | head -1

agent-browser --session "$SESSION_REF" set viewport $VIEW_W $VIEW_H 2>&1 > /dev/null
agent-browser --session "$SESSION_IMPL" set viewport $VIEW_W $VIEW_H 2>&1 > /dev/null

# Block images to reduce AE noise from dynamic content differences
# Injected after page load: hides all img elements and background-image CSS
# (network route can't intercept already-loaded images, so we use CSS instead)
HIDE_IMAGES_JS='(() => {
  // 1. CSS rule: hide all img and picture elements
  const style = document.createElement("style");
  style.id = "__no_images__";
  style.textContent = "img, picture, video, iframe { visibility: hidden !important; }";
  document.head.appendChild(style);
  // 2. Strip inline background-image from all elements
  document.querySelectorAll("*").forEach(el => {
    if (el.style && el.style.backgroundImage) el.style.backgroundImage = "none";
  });
  // 3. MutationObserver to catch dynamically added elements
  new MutationObserver(muts => {
    muts.forEach(m => m.addedNodes.forEach(n => {
      if (n.style && n.style.backgroundImage) n.style.backgroundImage = "none";
      if (n.querySelectorAll) n.querySelectorAll("[style*=background-image]").forEach(el => { el.style.backgroundImage = "none"; });
    }));
  }).observe(document.body, { childList: true, subtree: true });
})()'

# Wait for page JS to fully initialize (GSAP sets section heights, ScrollTrigger binds).
agent-browser --session "$SESSION_REF" wait "$WAIT_INIT" 2>&1 > /dev/null
agent-browser --session "$SESSION_IMPL" wait "$WAIT_INIT" 2>&1 > /dev/null

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

if [ "${NO_IMAGES:-0}" = "1" ]; then
  echo "▸ Hiding images (NO_IMAGES=1, CSS fallback for dynamic images)..."
  agent-browser --session "$SESSION_REF" eval "$HIDE_IMAGES_JS" 2>/dev/null || true
  agent-browser --session "$SESSION_IMPL" eval "$HIDE_IMAGES_JS" 2>/dev/null || true
fi

# Detect the actual scroll container — Lenis/locomotive-scroll sites lock body
# overflow and scroll an inner wrapper instead, so document.documentElement.scrollHeight
# == viewport height and window.scrollTo is a no-op. Find the largest scrollable
# element and use it for both height detection and scroll commands.
_detect_scroller_js='(() => {
  const dh = document.documentElement.scrollHeight;
  const dc = document.documentElement.clientHeight;
  if (dh > dc + 100) return { sel: "__document__", sh: dh };
  let best = null;
  document.querySelectorAll("*").forEach(el => {
    const cs = getComputedStyle(el);
    if ((cs.overflowY === "auto" || cs.overflowY === "scroll" || cs.overflowY === "hidden")
        && el.scrollHeight > el.clientHeight + 100) {
      if (!best || el.scrollHeight > best.sh) {
        best = { el, sh: el.scrollHeight, ch: el.clientHeight };
      }
    }
  });
  if (!best) return { sel: "__document__", sh: dh };
  let sel = best.el.tagName.toLowerCase();
  if (best.el.id) sel += "#" + best.el.id;
  else if (best.el.className && typeof best.el.className === "string") {
    const cls = best.el.className.split(" ").find(c => c.startsWith("js-") || c.includes("lenis") || c.includes("scroll"));
    if (cls) sel += "." + cls;
  }
  return { sel, sh: best.sh };
})()'

# Stash the detected scroller selector for both sessions so the scroll loop reuses it.
ORIG_SCROLLER=$(agent-browser --session "$SESSION_REF" eval "$_detect_scroller_js" 2>&1)
IMPL_SCROLLER=$(agent-browser --session "$SESSION_IMPL" eval "$_detect_scroller_js" 2>&1)

_extract_height() {
  python3 -c "import sys, json; v=sys.argv[1]; d=json.loads(v) if v.startswith('{') or v.startswith('\"') else None; print(d['sh'] if isinstance(d, dict) else (json.loads(v) if v.startswith('\"') else int(v)))" "$1" 2>/dev/null || echo ""
}
_extract_sel() {
  python3 -c "import sys, json; v=sys.argv[1]; d=json.loads(v) if v.startswith('{') else None; print(d['sel'] if isinstance(d, dict) and 'sel' in d else '__document__')" "$1" 2>/dev/null || echo "__document__"
}

ORIG_HEIGHT=$(_extract_height "$ORIG_SCROLLER")
IMPL_HEIGHT=$(_extract_height "$IMPL_SCROLLER")
ORIG_SEL=$(_extract_sel "$ORIG_SCROLLER")
IMPL_SEL=$(_extract_sel "$IMPL_SCROLLER")

if [ "$ORIG_SEL" != "__document__" ] || [ "$IMPL_SEL" != "__document__" ]; then
  echo "  ▸ Inner scroll container detected (Lenis/locomotive-style)"
  echo "    ref:  $ORIG_SEL"
  echo "    impl: $IMPL_SEL"
fi

if ! [[ "$ORIG_HEIGHT" =~ ^[0-9]+$ ]] || ! [[ "$IMPL_HEIGHT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Failed to extract page heights (orig=$ORIG_HEIGHT, impl=$IMPL_HEIGHT)"
  exit 1
fi

echo "  Ref height:  ${ORIG_HEIGHT}px"
echo "  Impl height: ${IMPL_HEIGHT}px"

# Height ratio check — use awk (always available), no bc dependency
RATIO=$(awk "BEGIN { printf \"%.2f\", $IMPL_HEIGHT / $ORIG_HEIGHT }")
if awk "BEGIN { exit ($RATIO > 1.30) ? 0 : 1 }"; then
  echo ""
  echo "  ⛔ HEIGHT MISMATCH: impl is ${RATIO}x taller than ref"
  echo "  Run: bash \"\$(dirname \"\$0\")/layout-health-check.sh\" $SESSION $ORIG_URL $IMPL_URL"
  echo ""
elif awk "BEGIN { exit ($RATIO < 0.70) ? 0 : 1 }"; then
  echo ""
  echo "  ⛔ HEIGHT MISMATCH: impl is ${RATIO}x shorter than ref"
  echo "  Run: bash \"\$(dirname \"\$0\")/layout-health-check.sh\" $SESSION $ORIG_URL $IMPL_URL"
  echo ""
fi

echo ""

# Interleaved capture: ref N% → impl N% for each position
echo "▸ Capturing (interleaved)..."
for PCT in "${POSITIONS[@]}"; do
  Y_REF=$(awk "BEGIN { printf \"%d\", $ORIG_HEIGHT * $PCT / 100 }")
  Y_IMPL=$(awk "BEGIN { printf \"%d\", $IMPL_HEIGHT * $PCT / 100 }")

  # Scroll both — falls back to inner-wrapper scrollTop when document body has overflow:hidden
  _scroll_js() {
    local sel="$1"; local y="$2"
    if [ "$sel" = "__document__" ]; then
      echo "(() => { window.scrollTo(0, $y); return $y; })()"
    else
      # Use the detected selector; dispatch a 'scroll' event so libraries that listen
      # for scroll events (Lenis, IntersectionObserver poll) re-evaluate.
      echo "(() => { const w = document.querySelector('$sel'); if (!w) { window.scrollTo(0, $y); return $y; } w.scrollTop = $y; w.dispatchEvent(new Event('scroll')); return w.scrollTop; })()"
    fi
  }
  agent-browser --session "$SESSION_REF" eval "$(_scroll_js "$ORIG_SEL" "$Y_REF")" 2>&1 > /dev/null
  agent-browser --session "$SESSION_IMPL" eval "$(_scroll_js "$IMPL_SEL" "$Y_IMPL")" 2>&1 > /dev/null

  sleep "$(awk "BEGIN { printf \"%.3f\", $WAIT_SCROLL / 1000 }")"

  # Screenshot both
  agent-browser --session "$SESSION_REF" screenshot "$DIR/static/ref/${PCT}pct.png" 2>&1 > /dev/null
  agent-browser --session "$SESSION_IMPL" screenshot "$DIR/static/impl/${PCT}pct.png" 2>&1 > /dev/null

  # Verify screenshots were actually written (silent failure guard)
  if [ ! -s "$DIR/static/ref/${PCT}pct.png" ] || [ ! -s "$DIR/static/impl/${PCT}pct.png" ]; then
    echo "  ⚠️  ${PCT}% — screenshot missing or empty (browser may have crashed)"
  else
    echo "  ✓ ${PCT}% (ref y=$Y_REF, impl y=$Y_IMPL)"
  fi
done

# Final count verification
REF_ACTUAL=$({ find "$DIR/static/ref" -name "*.png" 2>/dev/null || true; } | wc -l | tr -d ' ')
IMPL_ACTUAL=$({ find "$DIR/static/impl" -name "*.png" 2>/dev/null || true; } | wc -l | tr -d ' ')
echo ""
echo "▸ Captured: ref=$REF_ACTUAL impl=$IMPL_ACTUAL (expected ${#POSITIONS[@]} each)"
if [ "$REF_ACTUAL" -lt "${#POSITIONS[@]}" ] || [ "$IMPL_ACTUAL" -lt "${#POSITIONS[@]}" ]; then
  echo "  ⚠️  Some captures missing — check browser sessions above"
fi
echo "▸ Next: bash \"\$(dirname \"\$0\")/batch-compare.sh\" $DIR"

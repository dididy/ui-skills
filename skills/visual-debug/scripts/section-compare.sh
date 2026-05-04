#!/usr/bin/env bash
# section-compare.sh — Compare original vs implementation by section
#
# Usage: bash section-compare.sh <orig-url> <impl-url> <session> [output-dir]
#
# Instead of full-page scroll screenshots, this script:
# 1. Enumerates semantic sections on both sites
# 2. Matches sections by text content similarity
# 3. Crops element-level screenshots per section
# 4. Runs AE comparison per section
# 5. Diffs computedStyle + DOM structure per section
#
# Output: <dir>/sections/{ref,impl,diff}/<section-name>.png
#         <dir>/sections/report.json
#
# This eliminates scroll-alignment noise from full-page comparisons.

set -euo pipefail

VIEW_W="${VIEW_W:-1440}"
VIEW_H="${VIEW_H:-900}"
NO_IMAGES="${NO_IMAGES:-0}"
WAIT_REF="${WAIT_REF:-8000}"
WAIT_IMPL="${WAIT_IMPL:-6000}"
WAIT_LAZY_LOAD="${WAIT_LAZY_LOAD:-2}"
WAIT_SCROLL_SETTLE="${WAIT_SCROLL_SETTLE:-0.5}"

ORIG_URL="${1:?Usage: section-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
IMPL_URL="${2:?Usage: section-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
SESSION="${3:?Usage: section-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
DIR="${4:-tmp/ref/visual-debug}"
# ⚠️  IMPORTANT: Always pass $4 = absolute path to tmp/ref/<component-name>.
# The default (tmp/ref/visual-debug) is for standalone runs only.
# The Stop gate looks for sections/result.txt in the ACTIVE REF_DIR (which is absolute).
# If you use the default, the Stop gate will NEVER clear because result.txt is in the wrong place.
#
# Correct usage:
#   bash section-compare.sh <orig> <impl> <session> "$(pwd)/tmp/ref/<component>"
if [ "$DIR" = "tmp/ref/visual-debug" ]; then
  echo "⚠️  WARNING: Using default output-dir 'tmp/ref/visual-debug'." >&2
  echo "   The Stop gate hook won't find this result. Pass the component ref dir as \$4:" >&2
  echo "   bash section-compare.sh <orig> <impl> <session> \"\$(pwd)/tmp/ref/<component>\"" >&2
fi
# Convert to absolute path (if relative, resolve from PWD)
if [[ "$DIR" != /* ]]; then
  DIR="$(pwd)/$DIR"
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Guard: spaces in DIR path break Python one-liners that embed $DIR in string literals
if [[ "$DIR" == *" "* ]]; then
  echo "ERROR: output-dir path contains spaces: '$DIR'" >&2
  echo "       Rename the directory to remove spaces before running section-compare.sh." >&2
  exit 1
fi

SESSION_REF="${SESSION}-sc-ref"
SESSION_IMPL="${SESSION}-sc-impl"

cleanup_browsers() {
  agent-browser --session "$SESSION_REF" close 2>/dev/null || true
  agent-browser --session "$SESSION_IMPL" close 2>/dev/null || true
}
trap cleanup_browsers EXIT

mkdir -p "$DIR/sections/ref" "$DIR/sections/impl" "$DIR/sections/diff"

# Clean stale outputs from prior runs. Without this, deleted/renamed sections
# leave orphan PNGs that get picked up by the AE loop (REF_IMGS glob) and
# inflate the section count with stale entries that never re-render.
rm -f "$DIR/sections/ref/"*.png "$DIR/sections/impl/"*.png "$DIR/sections/diff/"*.png 2>/dev/null || true

echo "═══ Section-Level Comparison ═══"
echo "Original: $ORIG_URL"
echo "Implementation: $IMPL_URL"
echo ""

# ── Open both sites ──
echo "▸ Opening both sites..."
agent-browser --session "$SESSION_REF" open "$ORIG_URL" 2>&1 | head -1
agent-browser --session "$SESSION_IMPL" open "$IMPL_URL" 2>&1 | head -1

agent-browser --session "$SESSION_REF" set viewport "$VIEW_W" "$VIEW_H" > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" set viewport "$VIEW_W" "$VIEW_H" > /dev/null 2>&1

agent-browser --session "$SESSION_REF" wait "$WAIT_REF" > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" wait "$WAIT_IMPL" > /dev/null 2>&1

# Remove common overlays (cookie banners, newsletter popups)
DISMISS_OVERLAYS='(() => {
  document.querySelectorAll("[class*=popup], [class*=modal], [class*=cookie], [class*=banner], [class*=overlay], [class*=signup]").forEach(el => {
    const s = getComputedStyle(el);
    if (s.position === "fixed" || s.position === "absolute") {
      if (el.offsetWidth > window.innerWidth * 0.3 && el.offsetHeight > window.innerHeight * 0.2) {
        el.remove();
      }
    }
  });
  document.body.style.overflow = "";
  document.documentElement.style.overflow = "";
  return "overlays dismissed";
})()'

agent-browser --session "$SESSION_REF" eval "$DISMISS_OVERLAYS" 2>&1 > /dev/null
agent-browser --session "$SESSION_IMPL" eval "$DISMISS_OVERLAYS" 2>&1 > /dev/null

# Pause carousels/sliders/auto-advancing animations to get a stable frame for comparison.
# This freezes CSS animations and stops Swiper/Splide autoplay — does NOT affect layout.
# Set SKIP_PAUSE_ANIMATIONS=1 to disable if your site relies on animation-based initial layout.
PAUSE_ANIMATIONS='(() => {
  // Freeze all CSS animations and transitions
  const style = document.createElement("style");
  style.id = "__sc-pause__";
  style.textContent = `
    *, *::before, *::after {
      animation-play-state: paused !important;
      transition-duration: 0s !important;
    }
  `;
  document.head.appendChild(style);

  // Stop Swiper autoplay
  if (window.Swiper) {
    document.querySelectorAll(".swiper").forEach(el => {
      if (el.swiper) el.swiper.autoplay.stop();
    });
  }
  // Stop Splide autoplay
  if (window.Splide) {
    document.querySelectorAll(".splide").forEach(el => {
      if (el.splide) el.splide.Components.Autoplay.pause();
    });
  }
  // Stop any setInterval-based sliders (common pattern: stash interval IDs in data attributes)
  // We cannot enumerate all intervals, but freezing CSS transitions catches visual state.
  return "animations paused";
})()'

if [ "${SKIP_PAUSE_ANIMATIONS:-0}" != "1" ]; then
  agent-browser --session "$SESSION_REF" eval "$PAUSE_ANIMATIONS" 2>&1 > /dev/null
  agent-browser --session "$SESSION_IMPL" eval "$PAUSE_ANIMATIONS" 2>&1 > /dev/null
fi

# Hide images to reduce AE noise from dynamic content (thumbnails, ads, etc.)
HIDE_IMAGES_JS='(() => {
  const style = document.createElement("style");
  style.id = "__no_images__";
  style.textContent = "img, picture, video, iframe { visibility: hidden !important; }";
  document.head.appendChild(style);
  document.querySelectorAll("*").forEach(el => {
    if (el.style && el.style.backgroundImage) el.style.backgroundImage = "none";
  });
  new MutationObserver(muts => {
    muts.forEach(m => m.addedNodes.forEach(n => {
      if (n.style && n.style.backgroundImage) n.style.backgroundImage = "none";
      if (n.querySelectorAll) n.querySelectorAll("[style*=background-image]").forEach(el => { el.style.backgroundImage = "none"; });
    }));
  }).observe(document.body, { childList: true, subtree: true });
})()'

if [ "$NO_IMAGES" = "1" ]; then
  echo "▸ Hiding images (NO_IMAGES=1)..."
  agent-browser --session "$SESSION_REF" eval "$HIDE_IMAGES_JS" 2>/dev/null || true
  agent-browser --session "$SESSION_IMPL" eval "$HIDE_IMAGES_JS" 2>/dev/null || true
fi

sleep 1

# ── Detect the actual scroll container ──
# Lenis / locomotive-scroll / overflow:hidden body sites move the document
# scrollbar to an inner wrapper; window.scrollTo silently no-ops on those,
# producing identical screenshots at every "scroll position". Detect once
# per session and reuse for all subsequent scroll commands.
DETECT_SCROLLER_JS='(() => {
  const dh = document.documentElement.scrollHeight;
  const dc = document.documentElement.clientHeight;
  if (dh > dc + 100) return "__document__";
  let best = null;
  document.querySelectorAll("*").forEach(el => {
    const cs = getComputedStyle(el);
    if ((cs.overflowY === "auto" || cs.overflowY === "scroll" || cs.overflowY === "hidden")
        && el.scrollHeight > el.clientHeight + 100) {
      if (!best || el.scrollHeight > best.sh) best = { el, sh: el.scrollHeight };
    }
  });
  if (!best) return "__document__";
  const cls = (typeof best.el.className === "string" ? best.el.className : "")
    .split(" ").find(c => c.startsWith("js-") || c.includes("lenis") || c.includes("scroll"));
  return best.el.tagName.toLowerCase() + (cls ? "." + cls : "");
})()'
_unwrap_scroller() {
  python3 -c "import sys, json; v=sys.argv[1]; print(json.loads(v) if v.startswith('\"') else v)" "$1" 2>/dev/null || echo "__document__"
}
# Validate the detected selector against a strict allow-list before it flows into
# downstream Python f-strings. Detection produces values like `div.js-foo`; anything
# else (special chars, malformed) falls back to __document__. Matches v0.4.2's
# transition-compare.sh hardening discipline.
_validate_scroller() {
  local sel="$1"
  if [ "$sel" = "__document__" ] || [[ "$sel" =~ ^[a-z][a-z0-9]*(#[a-zA-Z][a-zA-Z0-9_-]*)?(\.[a-zA-Z][a-zA-Z0-9_-]*)?$ ]]; then
    echo "$sel"
  else
    echo "__document__"
  fi
}
REF_SCROLLER_SEL=$(_unwrap_scroller "$(agent-browser --session "$SESSION_REF" eval "$DETECT_SCROLLER_JS" 2>&1 | tail -1)")
IMPL_SCROLLER_SEL=$(_unwrap_scroller "$(agent-browser --session "$SESSION_IMPL" eval "$DETECT_SCROLLER_JS" 2>&1 | tail -1)")
REF_SCROLLER_SEL=$(_validate_scroller "$REF_SCROLLER_SEL")
IMPL_SCROLLER_SEL=$(_validate_scroller "$IMPL_SCROLLER_SEL")
[ -z "$REF_SCROLLER_SEL" ] && REF_SCROLLER_SEL="__document__"
[ -z "$IMPL_SCROLLER_SEL" ] && IMPL_SCROLLER_SEL="__document__"
if [ "$REF_SCROLLER_SEL" != "__document__" ] || [ "$IMPL_SCROLLER_SEL" != "__document__" ]; then
  echo "  ▸ Inner scroll container detected (Lenis/locomotive-style)"
  echo "    ref:  $REF_SCROLLER_SEL"
  echo "    impl: $IMPL_SCROLLER_SEL"
fi

# Build per-session scroll JS — falls back to window.scrollTo when the scroller is __document__.
_scroll_js() {
  local sel="$1"; local y="$2"
  if [ "$sel" = "__document__" ]; then
    echo "(() => { window.scrollTo(0, $y); return $y; })()"
  else
    echo "(() => { const w = document.querySelector('$sel'); if (!w) { window.scrollTo(0, $y); return $y; } w.scrollTop = $y; w.dispatchEvent(new Event('scroll')); return w.scrollTop; })()"
  fi
}

# ── Pre-scroll: trigger lazy-loaded content before fingerprint extraction ──
# Sites with IntersectionObserver-based lazy loading will have empty innerText
# for off-screen sections at load time. Scrolling through the full page forces
# all lazy content to load before we build section fingerprints.
# This prevents MATCH_COUNT=0 on sites with aggressive lazy loading.
echo "▸ Pre-scrolling to trigger lazy content..."
_pre_scroll_js() {
  local sel="$1"
  if [ "$sel" = "__document__" ]; then
    cat <<'JSEOF'
(() => {
  const total = document.documentElement.scrollHeight;
  const step = Math.max(window.innerHeight * 0.8, 400);
  let y = 0;
  const timer = setInterval(() => {
    window.scrollTo(0, y);
    y += step;
    if (y >= total) { clearInterval(timer); window.scrollTo(0, 0); }
  }, 120);
  return total;
})()
JSEOF
  else
    cat <<JSEOF
(() => {
  const w = document.querySelector('$sel');
  if (!w) { window.scrollTo(0, document.documentElement.scrollHeight); window.scrollTo(0, 0); return 0; }
  const total = w.scrollHeight;
  const step = Math.max(w.clientHeight * 0.8, 400);
  let y = 0;
  const timer = setInterval(() => {
    w.scrollTop = y;
    w.dispatchEvent(new Event('scroll'));
    y += step;
    if (y >= total) { clearInterval(timer); w.scrollTop = 0; w.dispatchEvent(new Event('scroll')); }
  }, 120);
  return total;
})()
JSEOF
  fi
}
agent-browser --session "$SESSION_REF" eval "$(_pre_scroll_js "$REF_SCROLLER_SEL")" > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" eval "$(_pre_scroll_js "$IMPL_SCROLLER_SEL")" > /dev/null 2>&1
sleep "$WAIT_LAZY_LOAD"  # Wait for lazy content to load and render after scroll
agent-browser --session "$SESSION_REF" eval "$(_scroll_js "$REF_SCROLLER_SEL" 0)" > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" eval "$(_scroll_js "$IMPL_SCROLLER_SEL" 0)" > /dev/null 2>&1
sleep "$WAIT_SCROLL_SETTLE"

# ── Step 1: Enumerate sections on both sites ──
echo "▸ Enumerating sections..."

ENUMERATE_SECTIONS='(() => {
  const semanticTags = new Set(["section", "footer", "header", "nav", "main"]);
  const containers = [];

  function collect(parent, depth) {
    if (depth > 6) return;
    const children = Array.from(parent.children);

    children.forEach(el => {
      const tag = el.tagName.toLowerCase();
      if (tag === "script" || tag === "style" || tag === "link" || tag === "noscript") return;
      const rect = el.getBoundingClientRect();
      const h = rect.height;
      if (h < 50 || rect.width < 100) return;

      const isSemantic = semanticTags.has(tag);
      const isLargeDiv = tag === "div" && h > window.innerHeight * 0.2;
      const isPageWrapper = h > document.documentElement.scrollHeight * 0.8;

      if (isSemantic) {
        // Descend only when this element directly wraps other structural sections
        // (e.g., <main> with <section> children, or <section> wrapping nested <section>s).
        // Do NOT descend on content semantics like <article>/<figure> nested inside a section.
        const hasStructuralChild = Array.from(el.children).some(c => {
          const t = c.tagName.toLowerCase();
          return t === "section" || t === "main" || t === "header" || t === "footer" || t === "nav" || t === "aside";
        });
        if (hasStructuralChild) {
          collect(el, depth + 1);
        } else {
          containers.push({ el, tag, rect });
        }
      } else if (isLargeDiv) {
        // If this div wraps most of the page, descend into it instead
        if (isPageWrapper) {
          collect(el, depth + 1);
        } else {
          // Check if this div has semantic children — if so, descend
          const hasSemanticChildren = Array.from(el.children).some(c =>
            semanticTags.has(c.tagName.toLowerCase())
          );
          if (hasSemanticChildren) {
            collect(el, depth + 1);
          } else {
            containers.push({ el, tag, rect });
          }
        }
      } else if (tag === "div" && h > 100) {
        collect(el, depth + 1);
      }
    });
  }

  collect(document.body, 0);

  // Deduplicate: remove parents that contain other found sections
  const filtered = containers.filter((c, i) =>
    !containers.some((other, j) => j !== i && c.el.contains(other.el) && c.el !== other.el)
  );

  filtered.sort((a, b) => a.rect.top - b.rect.top);

  return filtered.map((c, i) => {
    const el = c.el;
    const rect = el.getBoundingClientRect();
    const scrollY = window.scrollY;

    // Extract text fingerprint (first 100 chars of visible text, normalized)
    const text = el.innerText || "";
    const words = text.replace(/\\s+/g, " ").trim().substring(0, 200);
    const fingerprint = words.substring(0, 100).toLowerCase().replace(/[^a-z0-9 ]/g, "");

    // Check for SVGs
    const svgs = el.querySelectorAll("svg");
    const hasSvgText = [...svgs].some(svg => {
      const paths = svg.querySelectorAll("path");
      if (paths.length < 3) return false;
      const totalD = [...paths].reduce((sum, p) => sum + (p.getAttribute("d")?.length || 0), 0);
      return totalD > 500;
    });

    // Get rendering info
    const cs = getComputedStyle(el);

    return {
      index: i,
      tag: c.tag,
      id: el.id || null,
      className: (el.className?.toString?.() || "").substring(0, 80),
      fingerprint,
      hasSvgText,
      rect: {
        top: Math.round(rect.top + scrollY),
        left: Math.round(rect.left),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      },
      display: cs.display,
      gridCols: cs.gridTemplateColumns !== "none" ? cs.gridTemplateColumns : null,
      childCount: el.children.length,
    };
  });
})()'

agent-browser --session "$SESSION_REF" eval "$ENUMERATE_SECTIONS" > "$DIR/sections/ref-sections.json" 2>&1
agent-browser --session "$SESSION_IMPL" eval "$ENUMERATE_SECTIONS" > "$DIR/sections/impl-sections.json" 2>&1

_parse_section_count() {
  local f="$1"
  # Check for JS error (agent-browser eval failure) before parsing JSON
  local first
  first=$(head -1 "$f" 2>/dev/null || echo "")
  if echo "$first" | grep -qE '^(SyntaxError|TypeError|ReferenceError|Error:|Uncaught|\[object)'; then
    echo "JS_ERROR: $first" >&2
    echo "0"
    return
  fi
  python3 -c "
import json, sys
try:
    d = json.loads(open('$f').read())
    print(len(d) if isinstance(d, list) else 0)
except Exception as e:
    print(0, file=sys.stderr)
    print(0)
" 2>/dev/null || echo "0"
}
REF_COUNT=$(_parse_section_count "$DIR/sections/ref-sections.json")
IMPL_COUNT=$(_parse_section_count "$DIR/sections/impl-sections.json")

echo "  Ref:  $REF_COUNT sections"
echo "  Impl: $IMPL_COUNT sections"

if [ "$REF_COUNT" = "0" ] || [ "$IMPL_COUNT" = "0" ]; then
  echo "ERROR: Failed to enumerate sections — check if pages loaded correctly"
  echo "  Ref JSON head: $(head -3 "$DIR/sections/ref-sections.json" 2>/dev/null || echo "(missing)")"
  echo "  Impl JSON head: $(head -3 "$DIR/sections/impl-sections.json" 2>/dev/null || echo "(missing)")"
  exit 1
fi

# ── Step 2: Match sections by fingerprint similarity ──
echo "▸ Matching sections..."

python3 -c "
import json, sys

ref = json.loads(open('$DIR/sections/ref-sections.json').read())
impl = json.loads(open('$DIR/sections/impl-sections.json').read())

def similarity(a, b):
    if not a or not b:
        return 0
    words_a = set(a.split())
    words_b = set(b.split())
    if not words_a or not words_b:
        return 0
    intersection = words_a & words_b
    union = words_a | words_b
    return len(intersection) / len(union)

matches = []
used_impl = set()
used_names = set()  # dedup: prevent multiple sections mapping to same filename

def make_name(item, fallback_prefix):
    raw = item.get('id') or ''
    if not raw and item.get('className'):
        raw = item['className'].split()[0]
    if not raw:
        raw = f'{fallback_prefix}-{item[\"index\"]}'
    return raw.replace('/', '-').replace(' ', '-')[:40]

def dedup_name(base, used):
    if base not in used:
        used.add(base)
        return base
    i = 2
    while f'{base}-{i}' in used:
        i += 1
    n = f'{base}-{i}'
    used.add(n)
    return n

for r in ref:
    best_score = 0
    best_impl = None
    for im in impl:
        if im['index'] in used_impl:
            continue
        score = similarity(r['fingerprint'], im['fingerprint'])
        # Also boost if same tag and similar position ratio
        if r['tag'] == im['tag']:
            score += 0.1
        if score > best_score:
            best_score = score
            best_impl = im

    if best_impl and best_score > 0.05:
        used_impl.add(best_impl['index'])
        name = dedup_name(make_name(r, 'section'), used_names)
        # STRUCTURAL_WRAPPER: ref section is an empty container (sticky-image holder,
        # spacer wrapper, etc) — its visible content lives in nested children that
        # match other sections. Pixel-AE comparison is meaningless here because the
        # ref renders nothing of its own.
        is_wrapper = (not r.get('fingerprint', '').strip()) and r.get('childCount', 0) <= 1
        entry = {
            'name': name,
            'score': round(best_score, 3),
            'ref': r,
            'impl': best_impl,
        }
        if is_wrapper:
            entry['wrapper'] = True
        matches.append(entry)
    else:
        name = dedup_name(make_name(r, 'section'), used_names)
        matches.append({
            'name': name,
            'score': 0,
            'ref': r,
            'impl': None,
            'status': 'UNMATCHED',
        })

# Unmatched impl sections
for im in impl:
    if im['index'] not in used_impl:
        name = dedup_name(make_name(im, 'impl-section'), used_names)
        matches.append({
            'name': name,
            'score': 0,
            'ref': None,
            'impl': im,
            'status': 'EXTRA_IN_IMPL',
        })

json.dump(matches, open('$DIR/sections/matches.json', 'w'), indent=2)
print(f'  {len([m for m in matches if m.get(\"impl\")])} matched, {len([m for m in matches if not m.get(\"impl\")])} unmatched ref, {len([m for m in matches if not m.get(\"ref\")])} extra impl')
" 2>&1

# ── Step 3: Crop element screenshots per matched section ──
echo "▸ Capturing section screenshots..."

MATCH_COUNT=$(python3 -c "import json; m=json.load(open('$DIR/sections/matches.json')); print(len([x for x in m if x.get('ref') and x.get('impl')]))" 2>/dev/null || echo "0")

# EC-SC-3: Zero matches means fingerprint extraction failed on one side (wrong URL, JS error,
# CSP-blocked eval). Continuing would compare stale screenshots from a previous run —
# a false-pass risk. Exit early with a clear diagnostic.
if [ "$MATCH_COUNT" -eq 0 ]; then
  echo ""
  echo "ERROR: 0 sections matched between ref and impl."
  echo "  Possible causes:"
  echo "    1. Wrong URL passed (orig vs impl swapped?)"
  echo "    2. JS eval blocked by CSP on one page"
  echo "    3. Page not fully loaded — try adding a delay or scrolling to trigger lazy-load"
  echo "    4. Single-section site — fingerprint matching needs ≥2 sections"
  echo ""
  echo "  Debug: check $DIR/sections/matches.json"
  echo "  Expected: entries with both 'ref' and 'impl' populated"
  # Write a FAIL result.txt so the Stop gate gives a useful message instead of "not run"
  mkdir -p "$DIR/sections"
  {
    echo "| Section | AE | AE/Mpx | Severity | Status |"
    echo "|---------|-----|--------|----------|--------|"
    echo "| (none) | — | — | — | ❌ |"
    echo ""
    echo "**Result: 0 PASS, 1 FAIL, 0 SKIP**"
    echo ""
    echo "FAILURE REASON: 0 sections matched — fingerprint extraction failed."
    echo "Re-run section-compare.sh after fixing the URL or page load issue."
  } > "$DIR/sections/result.txt"
  exit 1
fi

python3 -c "
import json, subprocess, sys

matches = json.loads(open('$DIR/sections/matches.json').read())

for m in matches:
    name = m['name']
    ref = m.get('ref')
    impl = m.get('impl')

    # Re-apply animation pause after each scroll — scroll-triggered CSS transitions
    # (enter-reveal, GSAP ScrollTrigger) reset on scroll and can be mid-animation
    # at the screenshot moment if we only pause once at page load.
    pause_js = r'(() => { const s = document.getElementById(\"__sc-pause__\"); if (!s) { const ns = document.createElement(\"style\"); ns.id = \"__sc-pause__\"; ns.textContent = \"*, *::before, *::after { animation-play-state: paused !important; transition-duration: 0s !important; }\"; document.head.appendChild(ns); } return \"paused\"; })()'

    if ref:
        r = ref['rect']
        # Scroll to section and screenshot with clip
        scroll_y = max(0, r['top'] - 50)
        clip_top = r['top'] - scroll_y
        ref_sel = '$REF_SCROLLER_SEL'
        if ref_sel == '__document__':
            scroll_js_ref = '(() => { window.scrollTo(0, ' + str(scroll_y) + '); return ' + str(scroll_y) + '; })()'
        else:
            scroll_js_ref = (
                \"(() => { const w = document.querySelector('\" + ref_sel + \"'); \"
                + 'if (!w) { window.scrollTo(0, ' + str(scroll_y) + '); return ' + str(scroll_y) + '; } '
                + 'w.scrollTop = ' + str(scroll_y) + '; '
                + \"w.dispatchEvent(new Event('scroll')); return w.scrollTop; })()\"
            )
        cmd_scroll = f'agent-browser --session $SESSION_REF eval \"{scroll_js_ref}\"'
        subprocess.run(cmd_scroll, shell=True, capture_output=True)
        import time; time.sleep(0.1)
        # Re-apply pause to catch any scroll-triggered transitions that fired after scroll
        cmd_pause = f'agent-browser --session $SESSION_REF eval \"{pause_js}\"'
        subprocess.run(cmd_pause, shell=True, capture_output=True)
        time.sleep(0.2)
        cmd_ss = f'agent-browser --session $SESSION_REF screenshot $DIR/sections/ref/{name}.png'
        subprocess.run(cmd_ss, shell=True, capture_output=True)
        # Crop to section bounds
        crop_h = min(r['height'], 1800)  # Cap at 2x viewport
        cmd_crop = f'magick $DIR/sections/ref/{name}.png -crop {r[\"width\"]}x{crop_h}+{r[\"left\"]}+{clip_top} +repage $DIR/sections/ref/{name}.png'
        subprocess.run(cmd_crop, shell=True, capture_output=True)

    if impl:
        r = impl['rect']
        scroll_y = max(0, r['top'] - 50)
        clip_top = r['top'] - scroll_y
        impl_sel = '$IMPL_SCROLLER_SEL'
        if impl_sel == '__document__':
            scroll_js_impl = '(() => { window.scrollTo(0, ' + str(scroll_y) + '); return ' + str(scroll_y) + '; })()'
        else:
            scroll_js_impl = (
                \"(() => { const w = document.querySelector('\" + impl_sel + \"'); \"
                + 'if (!w) { window.scrollTo(0, ' + str(scroll_y) + '); return ' + str(scroll_y) + '; } '
                + 'w.scrollTop = ' + str(scroll_y) + '; '
                + \"w.dispatchEvent(new Event('scroll')); return w.scrollTop; })()\"
            )
        cmd_scroll = f'agent-browser --session $SESSION_IMPL eval \"{scroll_js_impl}\"'
        subprocess.run(cmd_scroll, shell=True, capture_output=True)
        import time; time.sleep(0.1)
        cmd_pause = f'agent-browser --session $SESSION_IMPL eval \"{pause_js}\"'
        subprocess.run(cmd_pause, shell=True, capture_output=True)
        time.sleep(0.2)
        cmd_ss = f'agent-browser --session $SESSION_IMPL screenshot $DIR/sections/impl/{name}.png'
        subprocess.run(cmd_ss, shell=True, capture_output=True)
        crop_h = min(r['height'], 1800)
        cmd_crop = f'magick $DIR/sections/impl/{name}.png -crop {r[\"width\"]}x{crop_h}+{r[\"left\"]}+{clip_top} +repage $DIR/sections/impl/{name}.png'
        subprocess.run(cmd_crop, shell=True, capture_output=True)

    sys.stdout.write(f'  ✓ {name}\n')
    sys.stdout.flush()
" 2>&1

# ── Step 4: AE comparison per section ──
echo ""
echo "▸ Comparing sections..."

RESULTS=""
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Build a lookup of wrapper-only sections so the AE loop can skip them.
# These have no ref content of their own (sticky-image holders, spacer wrappers).
WRAPPER_NAMES=$(python3 -c "
import json
m = json.loads(open('$DIR/sections/matches.json').read())
print(' '.join(x['name'] for x in m if x.get('wrapper')))
" 2>/dev/null || echo "")

# Guard: nullglob — if no ref PNGs were captured, the glob expands to a literal string
shopt -s nullglob
REF_IMGS=("$DIR/sections/ref/"*.png)
shopt -u nullglob
if [ ${#REF_IMGS[@]} -eq 0 ]; then
  echo "ERROR: No ref section images captured in $DIR/sections/ref/ — check Step 3 output above"
  exit 1
fi

for REF_IMG in "${REF_IMGS[@]}"; do
  NAME=$(basename "$REF_IMG" .png)
  IMPL_IMG="$DIR/sections/impl/${NAME}.png"

  if [ ! -f "$IMPL_IMG" ]; then
    RESULTS="${RESULTS}| ${NAME} | — | — | — | ⚠️ MISSING impl |\n"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Skip strict AE for STRUCTURAL_WRAPPER sections (ref has no visible content
  # of its own — pixel comparison would always fail against the impl that
  # actually renders something).
  if echo " $WRAPPER_NAMES " | grep -q " ${NAME} "; then
    RESULTS="${RESULTS}| ${NAME} | — | — | wrapper | ⏭️ SKIP (structural wrapper) |\n"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Resize impl to match ref dimensions
  REF_SIZE=$(magick identify -format "%wx%h" "$REF_IMG" 2>/dev/null)
  IMPL_SIZE=$(magick identify -format "%wx%h" "$IMPL_IMG" 2>/dev/null)

  if [ "$REF_SIZE" != "$IMPL_SIZE" ]; then
    magick "$IMPL_IMG" -resize "$REF_SIZE!" -quality 95 "$IMPL_IMG" 2>/dev/null
  fi

  DIFF_IMG="$DIR/sections/diff/${NAME}.png"
  # -fuzz tolerance: pixels with color diff <= fuzz% are considered identical.
  # Filters sub-pixel AA noise, font hinting, paper-texture/JPEG grain — keeping AE on structural divergence.
  FUZZ="${SECTION_FUZZ:-8%}"
  AE=$(magick compare -metric AE -fuzz "$FUZZ" "$REF_IMG" "$IMPL_IMG" "$DIFF_IMG" 2>&1 || true)
  # AE may be scientific notation (e.g. "1.0e+06") for large diffs.
  AE=$(echo "$AE" | head -1 | awk '{ if ($1 ~ /^[0-9.eE+-]+$/) printf "%.0f\n", $1 }')

  if [ -z "$AE" ]; then
    RESULTS="${RESULTS}| ${NAME} | ERROR | — | — | ⚠️ |\n"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Normalize AE by section pixel area (per megapixel) so a 1200px-tall section
  # isn't unfairly penalized vs a 600px-tall one with identical defect density.
  # Severity tiers below use this normalized value, not raw AE.
  REF_W=$(echo "$REF_SIZE" | cut -dx -f1)
  REF_H=$(echo "$REF_SIZE" | cut -dx -f2)
  AE_PER_MPX=$(awk -v ae="$AE" -v w="$REF_W" -v h="$REF_H" 'BEGIN { area = (w*h)/1000000; if (area > 0) printf "%.0f", ae/area; else print "0" }')

  # Thresholds operate on AE/Mpx (defect density). Default 2000 still works for
  # static content; use SECTION_THRESHOLD=50000 for image/animation-rich pages.
  THRESHOLD="${SECTION_THRESHOLD:-2000}"
  if [ "$AE_PER_MPX" -le 500 ]; then
    STATUS="✅"
    SEV="ok"
    PASS_COUNT=$((PASS_COUNT + 1))
  elif [ "$AE_PER_MPX" -le "$THRESHOLD" ]; then
    STATUS="✅"
    SEV="minor"
    PASS_COUNT=$((PASS_COUNT + 1))
  elif [ "$AE_PER_MPX" -le $((THRESHOLD * 10)) ]; then
    STATUS="❌"
    SEV="major"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    STATUS="❌"
    SEV="critical"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  RESULTS="${RESULTS}| ${NAME} | ${AE} | ${AE_PER_MPX} | ${SEV} | ${STATUS} |\n"
done

echo ""
echo "| Section | AE | AE/Mpx | Severity | Status |"
echo "|---------|-----|--------|----------|--------|"
echo -e "$RESULTS"
echo ""
echo "**Result: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL, ${SKIP_COUNT} SKIP**"
echo "(Severity is based on AE/Mpx — defect density per megapixel — not raw AE.)"

# ── Auto-save result for Stop gate hook ──
mkdir -p "$DIR/sections"
{
  echo "| Section | AE | AE/Mpx | Severity | Status |"
  echo "|---------|-----|--------|----------|--------|"
  echo -e "$RESULTS"
  echo ""
  echo "**Result: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL, ${SKIP_COUNT} SKIP**"
  echo "(Severity is based on AE/Mpx — defect density per megapixel — not raw AE.)"
} > "$DIR/sections/result.txt"

# ── Step 5: Structure diff per section ──
echo ""
echo "▸ Structure comparison..."

python3 -c "
import json

matches = json.loads(open('$DIR/sections/matches.json').read())
diffs = []

for m in matches:
    ref = m.get('ref')
    impl = m.get('impl')
    if not ref or not impl:
        continue

    issues = []

    # Check SVG-as-text mismatch
    if ref.get('hasSvgText') and not impl.get('hasSvgText'):
        issues.append('SVG_TEXT_MISSING: ref has SVG text paths, impl does not')
    if not ref.get('hasSvgText') and impl.get('hasSvgText'):
        issues.append('SVG_TEXT_EXTRA: impl has SVG text paths, ref does not')

    # Check layout system mismatch
    if ref.get('gridCols') and not impl.get('gridCols'):
        issues.append(f'LAYOUT_MISMATCH: ref uses grid ({ref[\"gridCols\"][:40]}), impl does not')
    if ref.get('display') != impl.get('display'):
        issues.append(f'DISPLAY_MISMATCH: ref={ref[\"display\"]}, impl={impl[\"display\"]}')

    # Check height ratio
    rh = ref['rect']['height']
    ih = impl['rect']['height']
    if rh > 0:
        ratio = ih / rh
        if ratio < 0.7 or ratio > 1.3:
            issues.append(f'HEIGHT_MISMATCH: ref={rh}px, impl={ih}px (ratio={ratio:.2f})')

    # Check child count
    rc = ref.get('childCount', 0)
    ic = impl.get('childCount', 0)
    if rc > 0 and abs(rc - ic) > max(2, rc * 0.3):
        issues.append(f'CHILD_COUNT_MISMATCH: ref={rc}, impl={ic}')

    # Classify severity
    rh = ref['rect']['height']
    ih = impl['rect']['height']
    h_ratio = ih / rh if rh > 0 else 1.0
    # When fingerprint similarity is high (>=0.85), the visible content matches
    # closely — child-count differences usually reflect harmless DOM nesting
    # variations (semantic <article> wrappers, extra grid containers) rather
    # than real divergence. Downgrade those to minor.
    score = m.get('score', 0)
    fingerprint_strong = score >= 0.85
    sev = 'ok'
    if any('SVG_TEXT_MISSING' in i or 'LAYOUT_MISMATCH' in i for i in issues):
        sev = 'critical'
    elif h_ratio < 0.3 or h_ratio > 3.0:
        sev = 'critical'
    elif any('HEIGHT_MISMATCH' in i or 'DISPLAY_MISMATCH' in i for i in issues):
        sev = 'major'
    elif any('CHILD_COUNT_MISMATCH' in i for i in issues):
        sev = 'minor' if fingerprint_strong else 'major'
    elif issues:
        sev = 'minor'

    if issues:
        diffs.append({'section': m['name'], 'issues': issues, 'severity': sev, 'score': score})

json.dump(diffs, open('$DIR/sections/structure-diff.json', 'w'), indent=2)

if diffs:
    # Sort by severity: critical first, then major, then minor
    sev_order = {'critical': 0, 'major': 1, 'minor': 2, 'ok': 3}
    diffs.sort(key=lambda d: sev_order.get(d.get('severity', 'ok'), 3))
    print('')
    for d in diffs:
        sev_icon = {'critical': '🔴', 'major': '🟠', 'minor': '🟡'}.get(d['severity'], '⚪')
        print(f'  {sev_icon} [{d[\"severity\"].upper()}] {d[\"section\"]}:')
        for issue in d['issues']:
            print(f'     - {issue}')
    print('')
    crit = sum(1 for d in diffs if d['severity'] == 'critical')
    maj = sum(1 for d in diffs if d['severity'] == 'major')
    minor = sum(1 for d in diffs if d['severity'] == 'minor')
    print(f'  Severity: {crit} critical, {maj} major, {minor} minor')
    if crit > 0:
        print(f'  ⛔ Fix {crit} CRITICAL issue(s) first — these indicate missing/broken sections')
else:
    print('  ✅ No structural mismatches detected')
" 2>&1

# ── Summary ──
echo ""
echo "═══ Section Compare Complete ═══"
echo "  Screenshots: $DIR/sections/{ref,impl,diff}/"
echo "  Matches:     $DIR/sections/matches.json"
echo "  Diffs:       $DIR/sections/structure-diff.json"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "⛔ ${FAIL_COUNT} section(s) FAILED visual comparison."
  echo "For each FAIL, read the diff image:"
  for REF_IMG in "${REF_IMGS[@]}"; do
    NAME=$(basename "$REF_IMG" .png)
    DIFF_IMG="$DIR/sections/diff/${NAME}.png"
    if [ -f "$DIFF_IMG" ]; then
      echo "  Read $DIFF_IMG"
    fi
  done

  # ── Context injection: Root Cause guidance ──
  SKILL_DIR="$(cd "$(dirname "$0")/../../ui-reverse-engineering" && pwd 2>/dev/null || echo "")"
  DIAGNOSIS="$SKILL_DIR/diagnosis.md"
  SKIP_ZONES="$SKILL_DIR/skip-zones.md"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ DIAGNOSIS GUIDE — pick the matching root cause:"
  echo ""
  echo "  Layout/structure wrong?    → Root Cause A (DOM Mismatch)"
  echo "  Color/font/weight wrong?   → Root Cause B (CSS Cascade Conflict)"
  echo "  Spacing/shadow wrong?      → Root Cause C (Missing Wrapper)"
  echo "  Element type wrong?        → Root Cause D (Wrong Element Type)"
  echo "  Animation doesn't animate? → Root Cause E (Animation)"
  echo ""
  if [ -f "$SKIP_ZONES" ]; then
    echo "▶ ZONE 5 VERIFICATION RULES (what was skipped):"
    awk '/^## ZONE 5:/,/^---/' "$SKIP_ZONES" | head -25
    echo ""
  fi
  if [ -f "$DIAGNOSIS" ]; then
    echo "▶ ROOT CAUSE DIAGNOSIS COMMANDS:"
    awk '/^## Root Cause/,/^---/' "$DIAGNOSIS" | head -50
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  exit 1
fi

# ── All sections passed ──
# The Stop hook (section_gate.py) owns WIP marker cleanup — it removes .ui-re-active
# after calling mark_passed("section-compare") and recording "done" in pipeline-state.json.
# section-compare.sh intentionally does NOT remove the marker here, so the Stop hook
# can still fire once more to record the completed state.
if [ "$FAIL_COUNT" -eq 0 ] && [ "$SKIP_COUNT" -eq 0 ]; then
  echo "  ✓ Section-compare passed — Stop hook will record completion on next write."
elif [ "$SKIP_COUNT" -gt 0 ]; then
  echo "  ⚠  $SKIP_COUNT section(s) missing from impl — implement them and re-run section-compare.sh."
fi

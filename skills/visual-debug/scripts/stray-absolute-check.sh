#!/usr/bin/env bash
# stray-absolute-check.sh — Find elements styled `position: absolute` whose
# nearest non-static ancestor is <body> or <html>.
#
# Why it matters:
#   `position: absolute` offsets work ONLY when an ancestor is positioned.
#   When the intended wrapper is `static` (or the element is a sibling of it
#   instead of a descendant), the offset resolves against <body> instead —
#   parking the element near the top of the document where it overlaps
#   unrelated sections (or scrolls past viewport on shorter pages, making it
#   look "missing"). Root cause behind "footer disappeared on mobile",
#   "modal anchored to wrong corner", "watermark in wrong place", etc.
#
#   AE/SSIM/section-compare don't catch this — the element renders SOMEWHERE on
#   the page, so a partial-viewport screenshot may look fine. The structural
#   smoking gun is in computed style + ancestor walk.
#
# Usage: bash stray-absolute-check.sh <session> <impl-url> [viewport-w] [viewport-h]
#
# Exit: 0 = no stray absolutes, 1 = stray absolutes found, 2 = setup error
#
# Output: Markdown table of suspect elements with selector, computed offset,
#         and the rendered y-coordinate vs DOM-order siblings.

set -uo pipefail

if ! command -v agent-browser &>/dev/null; then
  echo "ERROR: agent-browser not found. Install: npm i -g agent-browser"
  exit 2
fi

SESSION="${1:?Usage: stray-absolute-check.sh <session> <impl-url> [w] [h]}"
URL="${2:?Missing impl-url}"
VIEW_W="${3:-${VIEW_W:-1440}}"
VIEW_H="${4:-${VIEW_H:-900}}"
WAIT_MS="${WAIT_MS:-3000}"

cleanup() {
  agent-browser --session "$SESSION" close 2>/dev/null
}
trap cleanup EXIT

agent-browser --session "$SESSION" set viewport "$VIEW_W" "$VIEW_H" >/dev/null 2>&1
agent-browser --session "$SESSION" navigate "$URL" >/dev/null 2>&1
sleep $((WAIT_MS / 1000))

# Walk every absolute/fixed element. Find nearest non-static ancestor.
# Flag if it's <body>/<html> AND the element has a non-zero top/bottom/left/right.
RAW=$(agent-browser --session "$SESSION" eval '(() => {
  const all = document.querySelectorAll("*");
  const stray = [];
  const SKIP_TAGS = new Set(["SCRIPT","STYLE","META","LINK","HEAD","TITLE","NOSCRIPT","NEXT-ROUTE-ANNOUNCER"]);
  for (const el of all) {
    if (SKIP_TAGS.has(el.tagName)) continue;
    const cs = getComputedStyle(el);
    if (cs.position !== "absolute") continue;
    // Skip invisible elements (display:none / 0-size).
    if (cs.display === "none" || cs.visibility === "hidden") continue;
    const r0 = el.getBoundingClientRect();
    if (r0.width < 1 && r0.height < 1) continue;

    // Find nearest positioned ancestor.
    let p = el.parentElement;
    let anchor = null;
    while (p && p !== document.documentElement) {
      const pcs = getComputedStyle(p);
      if (pcs.position !== "static") { anchor = p; break; }
      p = p.parentElement;
    }
    const anchorTag = anchor ? anchor.tagName : "BODY/HTML";
    const anchorCls = anchor ? (anchor.className || "").toString().slice(0, 40) : "";

    // Only flag when anchor is body/html AND a positioning offset is set.
    if (anchor) continue;
    const hasOffset =
      cs.top !== "auto" ||
      cs.bottom !== "auto" ||
      cs.left !== "auto" ||
      cs.right !== "auto";
    if (!hasOffset) continue;

    const r = el.getBoundingClientRect();
    const cls = (el.className || "").toString().slice(0, 60);
    const id = el.id || "";

    // Identify DOM-order: which sibling index is this in its parent, and is the
    // rendered y monotonically increasing with DOM order? If LAST DOM child but
    // rendered Y is well above the median sibling Y, that is suspicious.
    const sibs = el.parentElement ? [...el.parentElement.children] : [];
    const idx = sibs.indexOf(el);
    const sibY = sibs.map(s => s.getBoundingClientRect().top + window.scrollY);
    const myY = r.top + window.scrollY;
    const lastSibY = sibY.length ? sibY[sibY.length - 1] : 0;
    const isLastDom = idx === sibs.length - 1;
    const visualOutOfOrder = isLastDom && myY < (sibY[Math.max(0, idx - 1)] || 0);

    stray.push({
      tag: el.tagName,
      id,
      cls,
      top: cs.top,
      bottom: cs.bottom,
      left: cs.left,
      right: cs.right,
      width: cs.width,
      height: cs.height,
      renderedY: Math.round(myY),
      domIndex: idx,
      siblingCount: sibs.length,
      isLastDom,
      visualOutOfOrder,
    });
  }
  return JSON.stringify(stray);
})()' 2>/dev/null)

# Unwrap agent-browser quoting.
DATA=$(echo "$RAW" | sed 's/^"//;s/"$//' | sed 's/\\"/"/g')

if [ -z "$DATA" ] || [ "$DATA" = "[]" ] || [ "$DATA" = "null" ]; then
  echo "✅ No stray absolute elements found."
  exit 0
fi

echo "═══ Stray Absolute Positioning ═══"
echo "URL: $URL"
echo "Viewport: ${VIEW_W}x${VIEW_H}"
echo ""
echo "Elements with \`position: absolute\` and NO positioned ancestor"
echo "(offset resolves against <body>/<html> — almost always a bug)."
echo ""

node -e "
const data = JSON.parse(process.argv[1]);
if (!data.length) { console.log('✅ none'); process.exit(0); }
console.log('| # | tag | class/id | top | bottom | rendered y | DOM idx | flags |');
console.log('|---|-----|----------|-----|--------|------------|---------|-------|');
data.forEach((s, i) => {
  const idCls = s.id ? ('#' + s.id) : (s.cls ? ('.' + s.cls.split(' ')[0]) : '');
  const flags = [];
  if (s.isLastDom && s.visualOutOfOrder) flags.push('⛔ last-DOM-child rendered above prior sibling');
  if (s.visualOutOfOrder) flags.push('⚠️ visual order ≠ DOM order');
  console.log('| ' + i + ' | ' + s.tag + ' | ' + idCls + ' | ' + s.top + ' | ' + s.bottom + ' | ' + s.renderedY + ' | ' + s.domIndex + '/' + (s.siblingCount - 1) + ' | ' + (flags.join('; ') || '—') + ' |');
});
console.log('');
console.log('Fix patterns:');
console.log('  1. Move the element INSIDE the ancestor it should anchor to.');
console.log('  2. Add \`position: relative\` to the intended ancestor.');
console.log('  3. If the element is a footer/sticky bar, switch to \`position: relative\`');
console.log('     (or \`position: fixed; bottom: 0\`) so it flows at the document end.');
console.log('');
console.log('See diagnosis.md → Root Cause H: Stray Absolute Positioning.');
process.exit(1);
" "$DATA"

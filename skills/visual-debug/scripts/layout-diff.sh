#!/usr/bin/env bash
# layout-diff.sh — Compare section bounding boxes between two URLs
#
# Usage: bash layout-diff.sh <session> <orig-url> <impl-url>
#
# Extracts bounding boxes of all major sections (section, header, footer, main, nav)
# from both URLs, then diffs them structurally.
#
# Catches: missing sections, wrong section order, collapsed elements, 
# extreme height differences — things AE and DSSIM miss because they 
# compare rendered pixels, not semantic structure.

set -uo pipefail

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not installed. Run: brew install jq"
  exit 2
fi

SESSION="${1:?Usage: layout-diff.sh <session> <orig-url> <impl-url>}"
ORIG="${2:?}"
IMPL="${3:?}"

EXTRACT_SCRIPT='(() => {
  const els = document.querySelectorAll("section, header, footer, main, nav, [role=banner], [role=main], [role=contentinfo]");
  const result = [];
  els.forEach(el => {
    const r = el.getBoundingClientRect();
    if (r.height < 10) return;
    const text = el.querySelector("h1,h2,h3,h4")?.textContent?.trim().slice(0,50) || "";
    result.push({
      tag: el.tagName,
      id: el.id || "",
      landmark: text,
      y: Math.round(r.top + window.scrollY),
      h: Math.round(r.height),
      w: Math.round(r.width)
    });
  });
  return JSON.stringify(result);
})()'

echo "═══ Layout Diff ═══"
echo "Original: $ORIG"
echo "Implementation: $IMPL"
echo ""

# Extract from original
agent-browser open "$ORIG" --session "${SESSION}-layout-orig" 2>/dev/null
agent-browser set viewport 1440 900 --session "${SESSION}-layout-orig" 2>/dev/null
agent-browser wait 5000 --session "${SESSION}-layout-orig" 2>/dev/null
ORIG_LAYOUT=$(agent-browser eval "$EXTRACT_SCRIPT" --session "${SESSION}-layout-orig" 2>/dev/null | tail -1)
agent-browser close --session "${SESSION}-layout-orig" 2>/dev/null

# Extract from implementation
agent-browser open "$IMPL" --session "${SESSION}-layout-impl" 2>/dev/null
agent-browser set viewport 1440 900 --session "${SESSION}-layout-impl" 2>/dev/null
agent-browser wait 5000 --session "${SESSION}-layout-impl" 2>/dev/null
IMPL_LAYOUT=$(agent-browser eval "$EXTRACT_SCRIPT" --session "${SESSION}-layout-impl" 2>/dev/null | tail -1)
agent-browser close --session "${SESSION}-layout-impl" 2>/dev/null

# Parse and compare — single jq call merges both arrays and produces TSV
echo "| # | Tag | Landmark | Orig H | Impl H | Ratio | Status |"
echo "|---|-----|----------|--------|--------|-------|--------|"

ORIG_COUNT=$(echo "$ORIG_LAYOUT" | jq 'length' 2>/dev/null || echo "0")
IMPL_COUNT=$(echo "$IMPL_LAYOUT" | jq 'length' 2>/dev/null || echo "0")
FAIL=0

# Merge both arrays into tab-separated rows in one jq invocation
jq -r --argjson orig "$ORIG_LAYOUT" --argjson impl "$IMPL_LAYOUT" -n '
  ([($orig | length), ($impl | length)] | max) as $max |
  range($max) | . as $i |
  [
    $i,
    ($orig[$i].tag // "—"),
    ($orig[$i].landmark // ""),
    ($orig[$i].h // 0),
    ($impl[$i].tag // "—"),
    ($impl[$i].landmark // ""),
    ($impl[$i].h // 0)
  ] | @tsv
' 2>/dev/null | while IFS=$'\t' read -r i OTAG OLAND OH ITAG ILAND IH; do
  LANDMARK="${OLAND:-$ILAND}"
  [ -z "$LANDMARK" ] && LANDMARK="(no heading)"

  if [ "$OTAG" = "—" ]; then
    echo "| $i | — | $LANDMARK | — | ${IH}px | — | ⚠️ EXTRA in impl |"
    FAIL=$((FAIL + 1))
  elif [ "$ITAG" = "—" ]; then
    echo "| $i | $OTAG | $LANDMARK | ${OH}px | — | — | ⛔ MISSING in impl |"
    FAIL=$((FAIL + 1))
  else
    if [ "$OH" -gt 0 ] 2>/dev/null && [ "$IH" -gt 0 ] 2>/dev/null; then
      RATIO=$(awk "BEGIN {printf \"%.2f\", $IH/$OH}")
      if awk "BEGIN {exit ($RATIO >= 0.7 && $RATIO <= 1.5) ? 0 : 1}"; then
        echo "| $i | $OTAG | $LANDMARK | ${OH}px | ${IH}px | ${RATIO}x | ✅ |"
      else
        echo "| $i | $OTAG | $LANDMARK | ${OH}px | ${IH}px | ${RATIO}x | ⚠️ |"
        FAIL=$((FAIL + 1))
      fi
    else
      echo "| $i | $OTAG | $LANDMARK | ${OH}px | ${IH}px | — | ⚠️ |"
      FAIL=$((FAIL + 1))
    fi
  fi
  # Write FAIL count to temp file (subshell can't update parent var)
  echo "$FAIL" > /tmp/layout-diff-fail-count
done

# Read FAIL count from subshell
FAIL=$(cat /tmp/layout-diff-fail-count 2>/dev/null || echo "0")
rm -f /tmp/layout-diff-fail-count

echo ""
echo "Sections: orig=$ORIG_COUNT impl=$IMPL_COUNT"
if [ "$FAIL" -gt 0 ]; then
  echo "⚠️  $FAIL structural differences found"
  exit 1
else
  echo "✅ Layout structure matches"
  exit 0
fi

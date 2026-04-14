#!/usr/bin/env bash
# computed-diff.sh — Compare getComputedStyle between original and implementation
# Usage: bash computed-diff.sh <session> <orig-url> <impl-url> <selector1> [selector2] ...
#
# For each selector, extracts key CSS properties from both sites and reports differences.
# Catches sub-pixel mismatches that AE/SSIM might miss (wrong font-size, padding, etc.)
#
# Output: Markdown table of mismatches. Empty = perfect match.

set -uo pipefail

SESSION="${1:?Usage: computed-diff.sh <session> <orig-url> <impl-url> <selector1> ...}"
ORIG_URL="${2:?}"
IMPL_URL="${3:?}"
shift 3
SELECTORS=("$@")

if [ ${#SELECTORS[@]} -eq 0 ]; then
  echo "ERROR: provide at least one CSS selector"
  exit 1
fi

PROPS='["display","position","width","height","padding","margin","fontSize","fontWeight","fontFamily","lineHeight","letterSpacing","color","backgroundColor","borderRadius","border","boxShadow","opacity","transform","zIndex","gap","flexDirection","alignItems","justifyContent","gridTemplateColumns"]'

# Build JS that extracts styles for all selectors
EXTRACT_JS="(() => {
  const props = ${PROPS};
  const selectors = $(printf '%s\n' "${SELECTORS[@]}" | jq -R . | jq -s .);
  const result = {};
  selectors.forEach(sel => {
    const el = document.querySelector(sel);
    if (!el) { result[sel] = null; return; }
    const s = getComputedStyle(el);
    const vals = {};
    props.forEach(p => { vals[p] = s[p]; });
    result[sel] = vals;
  });
  return JSON.stringify(result);
})()"

echo "═══ Computed Style Diff ═══"
echo ""

# Extract from original
agent-browser --session "$SESSION" open "$ORIG_URL" 2>&1 > /dev/null
agent-browser --session "$SESSION" set viewport 1440 900 2>&1 > /dev/null
agent-browser --session "$SESSION" wait 5000 2>&1 > /dev/null

ORIG_STYLES=$(agent-browser --session "$SESSION" eval "$EXTRACT_JS" 2>&1)

# Extract from implementation
agent-browser --session "$SESSION" open "$IMPL_URL" 2>&1 > /dev/null
agent-browser --session "$SESSION" set viewport 1440 900 2>&1 > /dev/null
agent-browser --session "$SESSION" wait 5000 2>&1 > /dev/null

IMPL_STYLES=$(agent-browser --session "$SESSION" eval "$EXTRACT_JS" 2>&1)

# Compare with Python
python3 << PYEOF
import json, sys

def parse(raw):
    raw = raw.strip()
    return json.loads(json.loads(raw)) if raw.startswith('"') else json.loads(raw)

try:
    orig = parse('''$ORIG_STYLES''')
    impl = parse('''$IMPL_STYLES''')
except Exception as e:
    print(f"Parse error: {e}")
    sys.exit(1)

mismatches = 0
print("| Selector | Property | Original | Implementation |")
print("|----------|----------|----------|----------------|")

for sel in orig:
    if orig[sel] is None:
        print(f"| \`{sel}\` | — | NOT FOUND | — |")
        mismatches += 1
        continue
    if impl.get(sel) is None:
        print(f"| \`{sel}\` | — | — | NOT FOUND |")
        mismatches += 1
        continue

    for prop in orig[sel]:
        ov = orig[sel][prop]
        iv = impl.get(sel, {}).get(prop, "")
        if ov != iv:
            # Skip trivial differences
            if ov in ("", "none", "normal", "auto") and iv in ("", "none", "normal", "auto"):
                continue
            # Skip font-family ordering differences
            if prop == "fontFamily" and ov.split(",")[0].strip().strip('"') == iv.split(",")[0].strip().strip('"'):
                continue
            print(f"| \`{sel}\` | {prop} | \`{ov[:50]}\` | \`{iv[:50]}\` |")
            mismatches += 1

print(f"\n**{mismatches} mismatches found**")
sys.exit(0 if mismatches == 0 else 1)
PYEOF

#!/usr/bin/env bash
# transition-compare.sh — Compare hover/transition behavior between original and implementation
#
# Usage: bash transition-compare.sh <orig-url> <impl-url> <session> [output-dir]
#
# For each element with CSS transitions on both sites:
# 1. Captures idle state (screenshot + computedStyle)
# 2. Simulates hover (mouseenter dispatch)
# 3. Captures hover state (screenshot + computedStyle)
# 4. Diffs idle/hover computedStyle between ref and impl
# 5. Compares transition timing (duration, easing, delay)
#
# Output: <dir>/transitions/report.json
#         <dir>/transitions/{ref,impl}/{element}-{idle,hover}.png

set -euo pipefail

VIEW_W="${VIEW_W:-1440}"
VIEW_H="${VIEW_H:-900}"

ORIG_URL="${1:?Usage: transition-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
IMPL_URL="${2:?Usage: transition-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
SESSION="${3:?Usage: transition-compare.sh <orig-url> <impl-url> <session> [output-dir]}"
DIR="${4:-tmp/ref/visual-debug}"

SESSION_REF="${SESSION}-tc-ref"
SESSION_IMPL="${SESSION}-tc-impl"

cleanup_browsers() {
  agent-browser --session "$SESSION_REF" close 2>/dev/null || true
  agent-browser --session "$SESSION_IMPL" close 2>/dev/null || true
}
trap cleanup_browsers EXIT

mkdir -p "$DIR/transitions/ref" "$DIR/transitions/impl"

echo "═══ Transition Comparison ═══"
echo "Original: $ORIG_URL"
echo "Implementation: $IMPL_URL"
echo ""

# ── Open both sites ──
echo "▸ Opening both sites..."
agent-browser --session "$SESSION_REF" open "$ORIG_URL" 2>&1 | head -1
agent-browser --session "$SESSION_IMPL" open "$IMPL_URL" 2>&1 | head -1

agent-browser --session "$SESSION_REF" set viewport "$VIEW_W" "$VIEW_H" > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" set viewport "$VIEW_W" "$VIEW_H" > /dev/null 2>&1

agent-browser --session "$SESSION_REF" wait 8000 > /dev/null 2>&1
agent-browser --session "$SESSION_IMPL" wait 6000 > /dev/null 2>&1

# Remove overlays
DISMISS='(() => {
  document.querySelectorAll("[class*=popup], [class*=modal], [class*=signup]").forEach(el => {
    const s = getComputedStyle(el);
    if (s.position === "fixed" || s.position === "absolute") el.remove();
  });
  document.body.style.overflow = "";
  document.documentElement.style.overflow = "";
  return "ok";
})()'
agent-browser --session "$SESSION_REF" eval "$DISMISS" 2>&1 > /dev/null
agent-browser --session "$SESSION_IMPL" eval "$DISMISS" 2>&1 > /dev/null

# ── Step 1: Find elements with transitions on the original ──
echo "▸ Detecting transition elements..."

DETECT_TRANSITIONS='(() => {
  const results = [];
  const seen = new Set();
  const allEls = document.querySelectorAll("a, button, [role=button], img, .product-card, [class*=card], [class*=link], [class*=hover], [class*=btn], nav a, footer a, h1, h2, h3");

  allEls.forEach(el => {
    const cs = getComputedStyle(el);
    const hasTrans = cs.transitionDuration !== "0s" && cs.transitionProperty !== "none";
    const hasAnim = cs.animationName !== "none";

    if (!hasTrans && !hasAnim) return;

    const rect = el.getBoundingClientRect();
    if (rect.width < 10 || rect.height < 10) return;
    if (rect.top + window.scrollY > document.documentElement.scrollHeight) return;

    // Build a unique selector
    let selector = "";
    if (el.id) {
      selector = "#" + el.id;
    } else if (el.className && typeof el.className === "string") {
      const cls = el.className.split(" ").filter(c => c && !c.includes("hover") && c.length < 40)[0];
      if (cls) selector = "." + cls;
    }
    if (!selector) {
      selector = el.tagName.toLowerCase();
      if (el.parentElement) {
        const siblings = [...el.parentElement.children].filter(c => c.tagName === el.tagName);
        if (siblings.length > 1) {
          const idx = siblings.indexOf(el);
          selector += `:nth-child(${idx + 1})`;
        }
      }
    }

    if (seen.has(selector)) return;
    seen.add(selector);

    // Get transition properties
    const transProps = cs.transitionProperty.split(",").map(p => p.trim());
    const transDurs = cs.transitionDuration.split(",").map(d => d.trim());
    const transEase = cs.transitionTimingFunction.split(",").map(e => e.trim());

    results.push({
      selector,
      tag: el.tagName.toLowerCase(),
      text: (el.textContent || "").trim().substring(0, 40),
      rect: {
        top: Math.round(rect.top + window.scrollY),
        left: Math.round(rect.left),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      },
      transition: {
        properties: transProps,
        durations: transDurs,
        easings: transEase,
      },
      idleStyle: {
        opacity: cs.opacity,
        transform: cs.transform,
        backgroundColor: cs.backgroundColor,
        color: cs.color,
        scale: cs.scale || "none",
        filter: cs.filter,
        boxShadow: cs.boxShadow,
      },
    });
  });

  return results.slice(0, 30);
})()'

agent-browser --session "$SESSION_REF" eval "$DETECT_TRANSITIONS" > "$DIR/transitions/ref-elements.json" 2>&1
agent-browser --session "$SESSION_IMPL" eval "$DETECT_TRANSITIONS" > "$DIR/transitions/impl-elements.json" 2>&1

REF_TRANS=$(python3 -c "import json; print(len(json.loads(open('$DIR/transitions/ref-elements.json').read())))" 2>/dev/null || echo "0")
IMPL_TRANS=$(python3 -c "import json; print(len(json.loads(open('$DIR/transitions/impl-elements.json').read())))" 2>/dev/null || echo "0")

echo "  Ref:  $REF_TRANS transition elements"
echo "  Impl: $IMPL_TRANS transition elements"

# ── Step 2: For each ref transition element, capture idle + hover states ──
echo "▸ Capturing idle + hover states..."

# Build the hover capture script
HOVER_CAPTURE_SCRIPT='
import json, subprocess, sys, time

def capture_hover_state(session, elements_file, side, out_dir):
    elements = json.loads(open(elements_file).read())
    results = []

    for el in elements[:20]:  # Cap at 20 elements
        selector = el["selector"]
        safe_name = selector.replace("#", "id-").replace(".", "cls-").replace(":", "-").replace(" ", "_")[:30]

        # Scroll to element
        scroll_cmd = f"""agent-browser --session {session} eval "(() => {{
            const el = document.querySelector(\\"{selector}\\");
            if (!el) return \\"not found\\";
            el.scrollIntoView({{ block: \\"center\\" }});
            return \\"scrolled\\";
        }})()" """
        subprocess.run(scroll_cmd, shell=True, capture_output=True)
        time.sleep(0.3)

        # Capture idle screenshot
        ss_cmd = f"agent-browser --session {session} screenshot {out_dir}/{safe_name}-idle.png"
        subprocess.run(ss_cmd, shell=True, capture_output=True)

        # Dispatch mouseenter + wait for transition
        hover_cmd = f"""agent-browser --session {session} eval "(() => {{
            const el = document.querySelector(\\"{selector}\\");
            if (!el) return \\"not found\\";
            el.dispatchEvent(new MouseEvent(\\"mouseenter\\", {{ bubbles: true }}));
            el.dispatchEvent(new MouseEvent(\\"mouseover\\", {{ bubbles: true }}));
            // Also try CSS :hover via focus trick
            el.focus?.();
            return \\"hovered\\";
        }})()" """
        subprocess.run(hover_cmd, shell=True, capture_output=True)
        time.sleep(0.5)  # Wait for transition to complete

        # Capture hover screenshot
        ss_cmd = f"agent-browser --session {session} screenshot {out_dir}/{safe_name}-hover.png"
        subprocess.run(ss_cmd, shell=True, capture_output=True)

        # Capture hover computedStyle
        style_cmd = f"""agent-browser --session {session} eval "(() => {{
            const el = document.querySelector(\\"{selector}\\");
            if (!el) return JSON.stringify({{ error: \\"not found\\" }});
            const cs = getComputedStyle(el);
            return JSON.stringify({{
                opacity: cs.opacity,
                transform: cs.transform,
                backgroundColor: cs.backgroundColor,
                color: cs.color,
                scale: cs.scale || \\"none\\",
                filter: cs.filter,
                boxShadow: cs.boxShadow,
                borderColor: cs.borderColor,
            }});
        }})()" """
        result = subprocess.run(style_cmd, shell=True, capture_output=True, text=True)
        hover_style = result.stdout.strip().strip('"')

        # Dispatch mouseleave to reset
        leave_cmd = f"""agent-browser --session {session} eval "(() => {{
            const el = document.querySelector(\\"{selector}\\");
            if (!el) return \\"not found\\";
            el.dispatchEvent(new MouseEvent(\\"mouseleave\\", {{ bubbles: true }}));
            el.dispatchEvent(new MouseEvent(\\"mouseout\\", {{ bubbles: true }}));
            el.blur?.();
            return \\"left\\";
        }})()" """
        subprocess.run(leave_cmd, shell=True, capture_output=True)
        time.sleep(0.3)

        try:
            hs = json.loads(hover_style.replace("\\\\", "\\\\\\\\")) if hover_style else {}
        except:
            hs = {}

        results.append({
            "selector": selector,
            "name": safe_name,
            "hoverStyle": hs,
        })

        sys.stdout.write(f"  ✓ {side}/{safe_name}\n")
        sys.stdout.flush()

    return results
'

python3 -c "
$HOVER_CAPTURE_SCRIPT

ref_results = capture_hover_state('$SESSION_REF', '$DIR/transitions/ref-elements.json', 'ref', '$DIR/transitions/ref')
impl_results = capture_hover_state('$SESSION_IMPL', '$DIR/transitions/impl-elements.json', 'impl', '$DIR/transitions/impl')

import json
json.dump({'ref': ref_results, 'impl': impl_results}, open('$DIR/transitions/hover-states.json', 'w'), indent=2)
" 2>&1

# ── Step 3: Diff transitions ──
echo ""
echo "▸ Comparing transitions..."

python3 -c "
import json

ref_els = json.loads(open('$DIR/transitions/ref-elements.json').read())
impl_els = json.loads(open('$DIR/transitions/impl-elements.json').read())
hover_states = json.loads(open('$DIR/transitions/hover-states.json').read())

# Match by selector similarity
def find_impl_match(ref_sel, impl_list):
    # Exact match
    for im in impl_list:
        if im['selector'] == ref_sel:
            return im
    # Partial match (same class name)
    ref_cls = ref_sel.replace('.', '').replace('#', '')
    for im in impl_list:
        im_cls = im['selector'].replace('.', '').replace('#', '')
        if ref_cls and im_cls and (ref_cls in im_cls or im_cls in ref_cls):
            return im
    return None

report = []
pass_count = 0
fail_count = 0

for ref_el in ref_els:
    impl_el = find_impl_match(ref_el['selector'], impl_els)

    entry = {
        'selector': ref_el['selector'],
        'text': ref_el.get('text', ''),
        'issues': [],
    }

    if not impl_el:
        entry['issues'].append('MISSING: no matching element in impl')
        entry['status'] = 'FAIL'
        fail_count += 1
        report.append(entry)
        continue

    # Compare transition timing
    ref_durs = ref_el['transition']['durations']
    impl_durs = impl_el['transition']['durations']
    ref_ease = ref_el['transition']['easings']
    impl_ease = impl_el['transition']['easings']

    if ref_durs != impl_durs:
        entry['issues'].append(f'DURATION_MISMATCH: ref={ref_durs}, impl={impl_durs}')

    if ref_ease != impl_ease:
        entry['issues'].append(f'EASING_MISMATCH: ref={ref_ease}, impl={impl_ease}')

    # Compare idle styles
    for prop in ['opacity', 'transform', 'backgroundColor', 'color']:
        ref_val = ref_el['idleStyle'].get(prop, '')
        impl_val = impl_el['idleStyle'].get(prop, '')
        if ref_val != impl_val and ref_val and impl_val:
            # Allow minor color differences
            if prop in ['backgroundColor', 'color']:
                if ref_val.replace(' ', '') == impl_val.replace(' ', ''):
                    continue
            entry['issues'].append(f'IDLE_{prop.upper()}_MISMATCH: ref={ref_val}, impl={impl_val}')

    # Compare hover styles from captured states
    ref_hover = next((r for r in hover_states.get('ref', []) if r['selector'] == ref_el['selector']), None)
    impl_hover = next((r for r in hover_states.get('impl', []) if r['selector'] == (impl_el or {}).get('selector', '')), None)

    if ref_hover and impl_hover and ref_hover.get('hoverStyle') and impl_hover.get('hoverStyle'):
        for prop in ['opacity', 'transform', 'scale', 'backgroundColor', 'color']:
            ref_hv = ref_hover['hoverStyle'].get(prop, '')
            impl_hv = impl_hover['hoverStyle'].get(prop, '')
            ref_idle = ref_el['idleStyle'].get(prop, '')

            # Check if property changes on hover in ref but not in impl
            if ref_hv and ref_idle and ref_hv != ref_idle:
                if impl_hv == impl_el['idleStyle'].get(prop, ''):
                    entry['issues'].append(f'HOVER_{prop.upper()}_NOT_APPLIED: ref changes {prop} on hover ({ref_idle} -> {ref_hv}), impl stays same')

    if entry['issues']:
        entry['status'] = 'FAIL'
        fail_count += 1
    else:
        entry['status'] = 'PASS'
        pass_count += 1

    report.append(entry)

json.dump(report, open('$DIR/transitions/report.json', 'w'), indent=2)

# Print summary
print('')
print('| Element | Status | Issues |')
print('|---------|--------|--------|')
for r in report:
    issues = '; '.join(r['issues'][:2]) if r['issues'] else '—'
    print(f'| {r[\"selector\"][:30]} | {r[\"status\"]} | {issues[:60]} |')

print(f'')
print(f'**Result: {pass_count} PASS, {fail_count} FAIL**')
" 2>&1

echo ""
echo "═══ Transition Compare Complete ═══"
echo "  Report: $DIR/transitions/report.json"
echo "  States: $DIR/transitions/{ref,impl}/"

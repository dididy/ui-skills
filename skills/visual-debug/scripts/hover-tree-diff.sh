#!/usr/bin/env bash
# hover-tree-diff.sh — Per-element hover/transition diff between ref and impl
#
# Walks every visible impl element with hover-capable transitions
# (transitionDuration > 0, cursor:pointer, or interactive tag), pairs each
# with the ref element at the same screen-center via elementFromPoint, then
# for each pair:
#   1. Capture idle computed style (transition meta + visual props)
#   2. Trigger CDP-level :hover (NOT synthetic events — those don't fire :hover)
#   3. Wait for transition to settle
#   4. Capture hover computed style
#   5. Reset
#   6. Diff: timing (property/duration/easing/delay) + idle→hover delta per side
#
# Catches:
#   - Hover style not applied at all (impl missing :hover rule)
#   - Different easing/duration (stutters vs smooth glide)
#   - Different delta (ref opacity 1→.5 vs impl 1→.7)
#
# Usage: bash hover-tree-diff.sh <session> <orig-url> <impl-url> [out-dir]
#
# Env:
#   VIEW_W=1440 VIEW_H=900    Viewport
#   WAIT_MS=4000              Settle time after open
#   MIN_SIZE=16               Skip elements smaller than NxN px
#   MAX_ELEMENTS=40           Cap candidates (hover loop is slow)
#   PAIR_TOLERANCE=10         Max center-distance for valid pair (px)
#   HOVER_WAIT=600            ms after hover before capturing style
#   RESET_WAIT=200            ms after un-hover before next element
#
# Output:
#   <dir>/hover-tree-diff.md   — Severity-sorted markdown
#   <dir>/hover-tree-diff.json — Raw pair data
# Exit 0 if no critical/major mismatches; 1 otherwise.

set -uo pipefail

if ! command -v agent-browser &>/dev/null; then
  echo "ERROR: agent-browser not found"; exit 2
fi
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found"; exit 2
fi

SESSION="${1:?Usage: hover-tree-diff.sh <session> <orig-url> <impl-url> [out-dir]}"
ORIG_URL="${2:?Missing orig-url}"
IMPL_URL="${3:?Missing impl-url}"
OUT_DIR="${4:-tmp/hover-tree-diff}"

VIEW_W="${VIEW_W:-1440}"
VIEW_H="${VIEW_H:-900}"
WAIT_MS="${WAIT_MS:-4000}"
MIN_SIZE="${MIN_SIZE:-16}"
MAX_ELEMENTS="${MAX_ELEMENTS:-40}"
PAIR_TOLERANCE="${PAIR_TOLERANCE:-10}"
HOVER_WAIT="${HOVER_WAIT:-600}"
RESET_WAIT="${RESET_WAIT:-200}"

mkdir -p "$OUT_DIR"

REF_SESS="${SESSION}-htd-ref"
IMPL_SESS="${SESSION}-htd-impl"

TMP_IMPL=$(mktemp /tmp/htd-impl-XXXXXX.json)
TMP_REF=$(mktemp /tmp/htd-ref-XXXXXX.json)

cleanup() {
  agent-browser --session "$REF_SESS" close >/dev/null 2>&1 || true
  agent-browser --session "$IMPL_SESS" close >/dev/null 2>&1 || true
  rm -f "$TMP_IMPL" "$TMP_REF"
}
trap cleanup EXIT

echo "═══ Hover Tree Diff (per-element :hover pairing) ═══"
echo "  orig: $ORIG_URL"
echo "  impl: $IMPL_URL"
echo "  viewport: ${VIEW_W}x${VIEW_H}, max: $MAX_ELEMENTS, hover wait: ${HOVER_WAIT}ms"
echo ""

# ── Open both sessions ──
agent-browser --session "$REF_SESS" open "$ORIG_URL" >/dev/null 2>&1
agent-browser --session "$IMPL_SESS" open "$IMPL_URL" >/dev/null 2>&1
agent-browser --session "$REF_SESS"  set viewport "$VIEW_W" "$VIEW_H" >/dev/null 2>&1 || true
agent-browser --session "$IMPL_SESS" set viewport "$VIEW_W" "$VIEW_H" >/dev/null 2>&1 || true
agent-browser --session "$REF_SESS"  wait "$WAIT_MS" >/dev/null 2>&1
agent-browser --session "$IMPL_SESS" wait "$WAIT_MS" >/dev/null 2>&1

# ── Step 1: walk impl tree, collect hover candidates ──
echo "  ▸ Walking impl for hover candidates..."
WALK_JS=$(cat <<JSEOF
(() => {
  const SKIP_TAGS = new Set(['SCRIPT','STYLE','META','LINK','HEAD','TITLE','NOSCRIPT','BR','HR']);
  const INTERACTIVE = new Set(['A','BUTTON','INPUT','SELECT','TEXTAREA','LABEL','SUMMARY']);
  const minSize = ${MIN_SIZE};
  const maxN    = ${MAX_ELEMENTS};
  const visualProps = ['color','backgroundColor','opacity','transform','filter',
                       'borderTopColor','borderBottomColor','textDecorationLine',
                       'textDecorationColor','fontStyle','fontWeight','letterSpacing',
                       'boxShadow','scale','translate','rotate'];
  const transProps = ['transitionProperty','transitionDuration','transitionTimingFunction','transitionDelay'];
  const out = [];
  const all = document.querySelectorAll('body *');
  for (const el of all) {
    if (SKIP_TAGS.has(el.tagName)) continue;
    const r = el.getBoundingClientRect();
    if (r.width < minSize || r.height < minSize) continue;
    if (r.bottom < 0 || r.top > window.innerHeight) continue;
    if (r.right  < 0 || r.left > window.innerWidth)  continue;
    const s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none' || parseFloat(s.opacity) === 0) continue;

    // Hover candidate filter
    const dur = s.transitionDuration || '0s';
    const hasTrans = dur !== '0s' && dur !== '0s, 0s' && s.transitionProperty !== 'none' && s.transitionProperty !== 'all 0s ease 0s';
    const cursor = s.cursor;
    const isInteractive = INTERACTIVE.has(el.tagName) || el.getAttribute('role') === 'button' || cursor === 'pointer';
    if (!hasTrans && !isInteractive) continue;

    const cx = Math.max(1, Math.min(window.innerWidth  - 1, r.left + r.width  / 2));
    const cy = Math.max(1, Math.min(window.innerHeight - 1, r.top  + r.height / 2));
    const txt = (el.textContent || '').trim().replace(/\s+/g,' ').slice(0, 30);
    const idle = {};
    visualProps.forEach(p => idle[p] = s[p]);
    const trans = {};
    transProps.forEach(p => trans[p] = s[p]);
    out.push({
      tag: el.tagName,
      cls: (el.className && el.className.toString) ? el.className.toString().slice(0, 60) : '',
      txt,
      x: +cx.toFixed(1), y: +cy.toFixed(1),
      w: +r.width.toFixed(1), h: +r.height.toFixed(1),
      area: +(r.width * r.height).toFixed(0),
      cursor,
      hasTrans,
      idle,
      trans,
    });
  }
  // Prefer transition-having elements; tie-break by area
  out.sort((a,b) => (b.hasTrans - a.hasTrans) * 1e9 + (b.area - a.area));
  return JSON.stringify(out.slice(0, maxN));
})()
JSEOF
)
agent-browser --session "$IMPL_SESS" eval "$WALK_JS" > "$TMP_IMPL" 2>&1
if [ ! -s "$TMP_IMPL" ]; then
  echo "ERROR: impl walk returned empty"; exit 2
fi

CANDIDATE_COUNT=$(python3 -c "
import json
with open('$TMP_IMPL') as f: raw = f.read().strip()
if raw.startswith('\"'): raw = json.loads(raw)
print(len(json.loads(raw)))
" 2>/dev/null || echo "0")
echo "  ▸ Hover candidates: $CANDIDATE_COUNT"

if [ "$CANDIDATE_COUNT" = "0" ]; then
  echo "  No hover candidates found. Exiting."
  exit 0
fi

# ── Step 2: capture hover state for each impl candidate ──
# JS helper: tag element at xy, return its tag/cls; we hover via CDP using attribute selector
echo "  ▸ Capturing impl hover states (CDP-level :hover)..."

_HTD_PY=$(mktemp /tmp/htd-hover-XXXXXX.py)
cat > "$_HTD_PY" << 'PYEOF'
import json, subprocess, sys, time, os

SESSION  = os.environ["_HTD_SESSION"]
SRC_FILE = os.environ["_HTD_SRC"]
DST_FILE = os.environ["_HTD_DST"]
HOVER_WAIT = float(os.environ.get("HOVER_WAIT", "600")) / 1000
RESET_WAIT = float(os.environ.get("RESET_WAIT", "200")) / 1000

VISUAL_PROPS = ['color','backgroundColor','opacity','transform','filter',
                'borderTopColor','borderBottomColor','textDecorationLine',
                'textDecorationColor','fontStyle','fontWeight','letterSpacing',
                'boxShadow','scale','translate','rotate']

def parse(raw):
    raw = raw.strip()
    if raw.startswith('"') and raw.endswith('"'):
        return json.loads(json.loads(raw))
    return json.loads(raw)

with open(SRC_FILE) as f:
    elements = parse(f.read())

def br_eval(js):
    return subprocess.run(
        ["agent-browser", "--session", SESSION, "eval", js],
        capture_output=True, text=True
    ).stdout.strip()

def br_hover(sel):
    return subprocess.run(
        ["agent-browser", "--session", SESSION, "hover", sel],
        capture_output=True, text=True
    )

# Mark element at xy with data-htd-i={i}, return ok/miss
TAG_JS = """(() => {
  const x = %f, y = %f, i = %d;
  const el = document.elementFromPoint(x, y);
  if (!el) return 'miss';
  el.setAttribute('data-htd-i', String(i));
  return 'ok-' + el.tagName;
})()"""

# Capture hover-state computed style for marked element
CAP_JS = """(() => {
  const i = %d;
  const el = document.querySelector('[data-htd-i="' + i + '"]');
  if (!el) return JSON.stringify({miss: true});
  const s = getComputedStyle(el);
  const out = {};
  %s
  return JSON.stringify(out);
})()"""
prop_lines = "\n  ".join([f"out['{p}'] = s['{p}'];" for p in VISUAL_PROPS])

# Reset: remove attribute and hover off-screen
RESET_JS = """(() => {
  document.querySelectorAll('[data-htd-i]').forEach(el => el.removeAttribute('data-htd-i'));
  return 'ok';
})()"""

results = []
for i, el in enumerate(elements):
    x, y = el["x"], el["y"]
    # Tag the element
    tag_result = br_eval(TAG_JS % (x, y, i))
    if "miss" in tag_result:
        results.append({"i": i, "miss": True})
        continue

    # Hover via CDP (real :hover)
    sel = f'[data-htd-i="{i}"]'
    br_hover(sel)
    time.sleep(HOVER_WAIT)

    # Capture style
    cap = br_eval(CAP_JS % (i, prop_lines))
    try:
        if cap.startswith('"') and cap.endswith('"'):
            cap = json.loads(cap)
        hover_style = json.loads(cap) if isinstance(cap, str) else cap
    except Exception:
        hover_style = {"err": "parse"}

    # Move hover off element (hover body or off-screen)
    subprocess.run(["agent-browser", "--session", SESSION, "hover", "body"],
                   capture_output=True, text=True)
    time.sleep(RESET_WAIT)

    results.append({
        "i": i,
        "hover": hover_style,
    })
    if (i + 1) % 5 == 0:
        sys.stdout.write(f"    ✓ {i + 1}/{len(elements)}\n")
        sys.stdout.flush()

# Cleanup attributes
br_eval(RESET_JS)

with open(DST_FILE, "w") as f:
    json.dump(results, f)
PYEOF

# Capture impl hover states
TMP_IMPL_HOVER=$(mktemp /tmp/htd-impl-hover-XXXXXX.json)
_HTD_SESSION="$IMPL_SESS" _HTD_SRC="$TMP_IMPL" _HTD_DST="$TMP_IMPL_HOVER" \
  HOVER_WAIT="$HOVER_WAIT" RESET_WAIT="$RESET_WAIT" \
  python3 "$_HTD_PY"

# ── Step 3: pair on ref via elementFromPoint, capture ref idle + hover ──
echo "  ▸ Pairing on ref + capturing ref hover states..."

PAIR_JS=$(python3 - "$TMP_IMPL" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f: raw = f.read().strip()
if raw.startswith('"'): raw = json.loads(raw)
impl_list = json.loads(raw)
points = [{"i": i, "x": e["x"], "y": e["y"]} for i, e in enumerate(impl_list)]
points_json = json.dumps(points)
js = """
(() => {
  const points = %s;
  const visualProps = ['color','backgroundColor','opacity','transform','filter',
                       'borderTopColor','borderBottomColor','textDecorationLine',
                       'textDecorationColor','fontStyle','fontWeight','letterSpacing',
                       'boxShadow','scale','translate','rotate'];
  const transProps = ['transitionProperty','transitionDuration','transitionTimingFunction','transitionDelay'];
  const out = [];
  for (const p of points) {
    const el = document.elementFromPoint(p.x, p.y);
    if (!el) { out.push({ i: p.i, miss: true }); continue; }
    el.setAttribute('data-htd-i', String(p.i));
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    const idle = {}; visualProps.forEach(k => idle[k] = s[k]);
    const trans = {}; transProps.forEach(k => trans[k] = s[k]);
    const cx = r.left + r.width / 2;
    const cy = r.top  + r.height / 2;
    out.push({
      i: p.i,
      tag: el.tagName,
      cls: (el.className && el.className.toString) ? el.className.toString().slice(0, 60) : '',
      txt: (el.textContent || '').trim().replace(/\\s+/g,' ').slice(0, 30),
      x: +cx.toFixed(1), y: +cy.toFixed(1),
      w: +r.width.toFixed(1), h: +r.height.toFixed(1),
      idle, trans,
    });
  }
  return JSON.stringify(out);
})()
""" % points_json
print(js)
PYEOF
)
agent-browser --session "$REF_SESS" eval "$PAIR_JS" > "$TMP_REF" 2>&1
if [ ! -s "$TMP_REF" ]; then
  echo "ERROR: ref pairing returned empty"; exit 2
fi

# Now capture ref hover for each i
TMP_REF_HOVER=$(mktemp /tmp/htd-ref-hover-XXXXXX.json)

# Build a stripped impl-list for hover-capture (only points for ref, but we need refs that paired ok)
TMP_REF_PAIRED=$(mktemp /tmp/htd-ref-paired-XXXXXX.json)
python3 - "$TMP_REF" "$TMP_REF_PAIRED" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f: raw = f.read().strip()
if raw.startswith('"'): raw = json.loads(raw)
ref_list = json.loads(raw)
# write as "elements" list with x,y so the hover-py can iterate
out = []
for r in ref_list:
    if r.get("miss"):
        out.append({"x": -1, "y": -1, "miss": True})
    else:
        out.append({"x": r["x"], "y": r["y"]})
with open(sys.argv[2], "w") as f:
    json.dump(out, f)
PYEOF

_HTD_SESSION="$REF_SESS" _HTD_SRC="$TMP_REF_PAIRED" _HTD_DST="$TMP_REF_HOVER" \
  HOVER_WAIT="$HOVER_WAIT" RESET_WAIT="$RESET_WAIT" \
  python3 "$_HTD_PY"

# ── Step 4: diff ──
echo "  ▸ Diffing pairs..."
echo ""

python3 - "$TMP_IMPL" "$TMP_IMPL_HOVER" "$TMP_REF" "$TMP_REF_HOVER" "$OUT_DIR" "$PAIR_TOLERANCE" <<'PYEOF'
import json, sys, os

def parse(path):
    with open(path) as f: raw = f.read().strip()
    if raw.startswith('"') and raw.endswith('"'):
        return json.loads(json.loads(raw))
    return json.loads(raw)

impl       = parse(sys.argv[1])
impl_hover = parse(sys.argv[2])
ref        = parse(sys.argv[3])
ref_hover  = parse(sys.argv[4])
out_dir    = sys.argv[5]
tol        = float(sys.argv[6])

ref_by_i  = {r.get("i", idx): r for idx, r in enumerate(ref)}
impl_hov_by_i = {h.get("i", idx): h for idx, h in enumerate(impl_hover)}
ref_hov_by_i  = {h.get("i", idx): h for idx, h in enumerate(ref_hover)}

VISUAL_PROPS = ['color','backgroundColor','opacity','transform','filter',
                'borderTopColor','borderBottomColor','textDecorationLine',
                'textDecorationColor','fontStyle','fontWeight','letterSpacing',
                'boxShadow','scale','translate','rotate']
TRANS_PROPS = ['transitionProperty','transitionDuration','transitionTimingFunction','transitionDelay']

CRITICAL_TIMING = {"transitionDuration", "transitionTimingFunction"}

def changed(a, b):
    if not a or not b: return False
    a, b = str(a).strip(), str(b).strip()
    if a == b: return False
    if a in ("", "none", "normal", "auto") and b in ("", "none", "normal", "auto"):
        return False
    return True

rows = []
for i, ie in enumerate(impl):
    re = ref_by_i.get(i)
    row = {
        "i": i,
        "impl_tag": ie["tag"], "impl_cls": ie["cls"], "txt": ie["txt"],
        "impl_xy": (ie["x"], ie["y"]),
        "issues": [],
    }
    if not re or re.get("miss"):
        row["sev"] = "unpaired"
        row["issues"].append("ref miss at xy")
        rows.append(row); continue

    dx = abs(ie["x"] - re["x"]); dy = abs(ie["y"] - re["y"])
    row["ref_tag"] = re["tag"]; row["ref_cls"] = re["cls"]; row["ref_txt"] = re["txt"]
    row["ref_xy"] = (re["x"], re["y"]); row["dx"] = dx; row["dy"] = dy

    if dx > tol or dy > tol:
        row["sev"] = "unpaired"
        row["issues"].append(f"pair offset Δ{dx:.0f},{dy:.0f}")
        rows.append(row); continue

    # ── Diff transition timing ──
    timing_diffs = []
    for p in TRANS_PROPS:
        iv = ie["trans"].get(p, ""); rv = re["trans"].get(p, "")
        if changed(iv, rv):
            timing_diffs.append((p, iv, rv))

    # ── Diff idle→hover delta ──
    ih = impl_hov_by_i.get(i, {}).get("hover") or {}
    rh = ref_hov_by_i.get(i, {}).get("hover") or {}
    delta_diffs = []
    for p in VISUAL_PROPS:
        i_idle = ie["idle"].get(p, ""); i_hov = ih.get(p, "")
        r_idle = re["idle"].get(p, ""); r_hov = rh.get(p, "")
        i_changes = changed(i_idle, i_hov)
        r_changes = changed(r_idle, r_hov)
        if r_changes and not i_changes:
            delta_diffs.append((p, "no-change", f"{r_idle}→{r_hov}", "missing-hover-effect"))
        elif i_changes and not r_changes:
            delta_diffs.append((p, f"{i_idle}→{i_hov}", "no-change", "extra-hover-effect"))
        elif i_changes and r_changes:
            if changed(i_hov, r_hov):
                delta_diffs.append((p, f"{i_idle}→{i_hov}", f"{r_idle}→{r_hov}", "different-target"))

    sev = "ok"
    if delta_diffs: sev = "major"
    if any(p in CRITICAL_TIMING for p, *_ in timing_diffs): sev = "critical"
    elif timing_diffs and sev != "critical": sev = "major"
    if any(d[3] == "missing-hover-effect" for d in delta_diffs): sev = "critical"

    row["sev"] = sev
    row["timing_diffs"] = timing_diffs
    row["delta_diffs"] = delta_diffs
    rows.append(row)

SEV_RANK = {"critical": 4, "unpaired": 3, "major": 2, "minor": 1, "ok": 0}
counts = {"critical": 0, "major": 0, "minor": 0, "ok": 0, "unpaired": 0}
for r in rows: counts[r["sev"]] += 1
rows.sort(key=lambda r: -SEV_RANK[r["sev"]])

# ── Markdown ──
md = os.path.join(out_dir, "hover-tree-diff.md")
with open(md, "w") as f:
    f.write("# Hover Tree Diff Report\n\n")
    f.write(f"**Walked**: {len(impl)} hover candidates  ")
    f.write(f"**Critical**: {counts['critical']}  ")
    f.write(f"**Major**: {counts['major']}  ")
    f.write(f"**Unpaired**: {counts['unpaired']}  ")
    f.write(f"**Match**: {counts['ok']}\n\n")
    f.write("| # | Sev | Impl tag.cls | Text | Timing diffs | Hover delta diffs |\n")
    f.write("|---|---|---|---|---|---|\n")
    for r in rows:
        if r["sev"] == "ok": continue
        sev_label = {"critical": "🔴", "major": "🟠", "minor": "🟡", "unpaired": "⚪"}[r["sev"]]
        impl_id = f"{r['impl_tag']}.{r['impl_cls'][:25]}".rstrip(".")
        txt = r["txt"][:24]
        td = r.get("timing_diffs", [])
        td_str = "; ".join(f"`{p}`: {a[:14]}→{b[:14]}" for p, a, b in td[:2])
        if len(td) > 2: td_str += f" (+{len(td)-2})"
        if not td_str: td_str = "—"
        dd = r.get("delta_diffs", [])
        dd_str = "; ".join(f"`{p}`[{kind}]" for p, _, _, kind in dd[:3])
        if len(dd) > 3: dd_str += f" (+{len(dd)-3})"
        if not dd_str:
            dd_str = "(unpaired)" if r["sev"] == "unpaired" else "—"
        f.write(f"| {r['i']} | {sev_label} | `{impl_id}` | {txt} | {td_str} | {dd_str} |\n")

# ── JSON ──
js = os.path.join(out_dir, "hover-tree-diff.json")
with open(js, "w") as f:
    json.dump(rows, f, indent=2, default=str)

print(f"  Walked {len(impl)} hover candidates")
print(f"  🔴 critical: {counts['critical']}   🟠 major: {counts['major']}   ⚪ unpaired: {counts['unpaired']}   ✓ ok: {counts['ok']}")
print(f"  Report: {md}")
print(f"  Raw:    {js}")
print()
if counts["critical"] or counts["major"]:
    print("Top critical/major:")
    for r in rows[:6]:
        if r["sev"] in ("ok",): continue
        sev_label = {"critical": "🔴", "major": "🟠", "minor": "🟡", "unpaired": "⚪"}[r["sev"]]
        impl_id = f"{r['impl_tag']}.{r['impl_cls'][:30]}"
        txt = (r["txt"] or "")[:20]
        bits = []
        for p, a, b in (r.get("timing_diffs") or [])[:2]:
            bits.append(f"{p}: {str(a)[:12]}→{str(b)[:12]}")
        for p, _, _, kind in (r.get("delta_diffs") or [])[:2]:
            bits.append(f"{p}[{kind}]")
        d = "; ".join(bits) or "(unpaired)"
        print(f"  {sev_label} #{r['i']}  {impl_id}  '{txt}'  | {d}")

sys.exit(1 if (counts["critical"] or counts["major"]) else 0)
PYEOF
EXIT=$?

rm -f "$_HTD_PY" "$TMP_IMPL_HOVER" "$TMP_REF_HOVER" "$TMP_REF_PAIRED"
exit $EXIT

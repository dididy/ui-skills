# Visual Verification & Bug Diagnosis

**Never re-capture from original site.** Compare implementation against saved references.

```
ref frames (saved ONCE) → implement → capture impl frames → visual compare → adjust → repeat
```

## Frame Comparison — scope: element

Cropped to element bounds:

| Frame | Time | Ref | Impl | Match? | Issue |
|-------|------|-----|------|--------|-------|
| 01 | 0ms | frames/ref/frame-01.png | frames/impl/frame-01.png | ✅/❌ | |
| 08 | 50% | frames/ref/frame-08.png | frames/impl/frame-08.png | ✅/❌ | |
| 15 | 100% | frames/ref/frame-15.png | frames/impl/frame-15.png | ✅/❌ | |

For each ❌: identify exact property → targeted fix → re-capture impl only → compare.

## Frame Comparison — scope: fullpage

Full-page screenshot comparison across the entire transition window:

| Frame | Time | Ref | Impl | Match? | Issue |
|-------|------|-----|------|--------|-------|
| 01 | 0ms (before) | frames/ref/frame-01.png | frames/impl/frame-01.png | ✅/❌ | |
| 02 | ~100ms | frames/ref/frame-02.png | frames/impl/frame-02.png | ✅/❌ | |
| ... | every 100ms | ... | ... | | |
| N | end (settled) | frames/ref/frame-N.png | frames/impl/frame-N.png | ✅/❌ | |

**Additional checks for fullpage:**
- Any frame where ref shows content but impl shows blank/loading/white → ❌ FAIL
- Any frame where ref shows smooth transition but impl shows layout jump → ❌ FAIL
- Intermediate frames (not just start/end) must match — do not skip mid-transition frames

For each ❌: write one sentence naming the root cause before touching code. If you cannot name it, run `agent-browser eval` to inspect computed styles at the exact failing frame. Only after root cause is confirmed → fix → re-capture impl only → compare.

## Bug Diagnosis Protocol

When a visual bug is reported (white flash, wrong timing, layout jump, etc.):

**Before writing any fix:**
1. Name the root cause in one sentence: _"The white flash happens because X"_
2. If you cannot name it, instrument first:
   ```bash
   agent-browser eval "
   (() => {
     const panes = document.querySelectorAll('[class*=pane], [class*=slot]');
     return JSON.stringify([...panes].map(el => {
       const s = getComputedStyle(el);
       return { cls: (typeof el.className === 'string' ? el.className : el.className?.baseVal || ''), opacity: s.opacity, visibility: s.visibility, zIndex: s.zIndex, position: s.position, height: el.offsetHeight };
     }));
   })()"
   ```
3. Only after root cause is confirmed → write the fix
4. After fix → re-capture impl frames → verify the specific bug frame is gone

**Do not iterate on the same approach more than twice.** If two fixes in the same direction don't work, the diagnosis was wrong — re-instrument and re-diagnose.

## Pixel-Perfect Static State Diff (MANDATORY)

> **Read and execute `../pixel-perfect-diff.md` Phase 1 (Visual Gate) AND Phase 2 (Numerical Diagnosis) for the element's resting states — both always run.**

Frame comparison verifies timing and motion but CANNOT verify:
- Whether resting-state `font-size` / `font-weight` / `color` are numerically correct
- Whether spacing, padding, and border-radius are exact matches

Run the Visual Gate for all relevant states (triggerType determines which):
1. **idle** — element before any interaction (all elements)
2. **active / after** — element in settled end state (css-hover, js-class, intersection)
3. **before / mid / after** — scroll-driven transitions at trigger_y-50, mid_y, settled_y+50

```bash
# Measure rect in each state, then clip screenshot — example for hover/js-class:
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"

# idle state
agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<effect-name>/frames/ref/idle.png
agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<effect-name>/frames/impl/idle.png

# trigger active state, re-measure rect, then capture
# (see pixel-perfect-diff.md Phase 1 Step V2 for state activation patterns by triggerType)
agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<effect-name>/frames/ref/active.png
agent-browser screenshot --clip <x>,<y>,<w>,<h> tmp/ref/<effect-name>/frames/impl/active.png

# diff
compare -metric AE tmp/ref/<effect-name>/frames/ref/idle.png tmp/ref/<effect-name>/frames/impl/idle.png /dev/null 2>&1
compare -metric AE tmp/ref/<effect-name>/frames/ref/active.png tmp/ref/<effect-name>/frames/impl/active.png /dev/null 2>&1
```

Phase 1 and Phase 2 always both run — Phase 2 catches sub-pixel mismatches that pass the Visual Gate. If either fails → fix CSS → re-run both.

Gate: `pixel-perfect-diff.json` must exist with all elements `"status": "pass"` AND `mismatches = 0` for all captured states.

## "Is This Done?" Checklist

- [ ] `measurements.json` saved (11-point multi-property measurement from measurement.md)
- [ ] Non-linear curves / phase boundaries identified and documented
- [ ] `extracted.json` saved
- [ ] Implementation written (using measured values, NOT guessed values)
- [ ] Impl frames captured (localhost, same trigger sequence as ref)
- [ ] Comparison table filled — every frame has ✅ or ❌
- [ ] All ❌ rows fixed and re-verified
- [ ] No white flash / blank frame / layout jump in any impl frame where ref shows content
- [ ] **`pixel-perfect-diff.json` exists with all elements `"status": "pass"` AND `mismatches = 0` (all captured states — idle, active/after, or before/mid/after by triggerType)**
- [ ] Entry points verified: CSS imports loaded (`body { margin: 0 }` etc. in effect), no missing `import` in main entry file
- [ ] **Scroll transitions: reverse direction verified** — scroll back through trigger zone, confirm animation reverses to initial state
- [ ] **Post-implementation full-page capture** — after all transitions are implemented, do a full-page scroll capture (top → bottom → top) on both original and implementation, compare side by side

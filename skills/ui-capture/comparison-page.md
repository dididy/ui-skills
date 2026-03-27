# ui-capture — Comparison Page

Generate `tmp/ref/capture/compare.html` for side-by-side human review of original vs clone.

## Phase 4A: Pixel-Perfect Numerical Diff (MANDATORY — run BEFORE generating compare.html)

> **Read and execute `../pixel-perfect-diff.md` Steps P1–P6 for each major section of the page.**
> Screenshot comparison is subjective. Numerical diff is objective. Do numerical diff first.

For each section in `regions.json` plus any static-only sections (header, footer, hero):
1. Follow `../pixel-perfect-diff.md` to measure ref and impl using `getComputedStyle`
2. Produce `tmp/ref/capture/pixel-perfect-diff.json` with `"result": "pass"`

The diff JSON must be embedded in the compare.html output (see HTML structure below).

Gate before generating compare.html:
```
□ pixel-perfect-diff.json exists at tmp/ref/capture/pixel-perfect-diff.json
□ "result": "pass"
□ "mismatches": 0
```

If mismatches exist → fix CSS → re-measure → get to 0 mismatches → THEN generate compare.html.

---

## HTML structure

```html
<!DOCTYPE html>
<html>
<head>
  <title>UI Capture — Original vs Clone</title>
  <style>
    body { background: #0a0a0a; color: #fff; font-family: system-ui; padding: 20px; }
    .pair { display: flex; gap: 8px; margin-bottom: 32px; }
    .side { flex: 1; position: relative; }
    .side img, .side video { width: 100%; border: 1px solid #333; border-radius: 4px; }
    .tag { position: absolute; top: 8px; left: 8px; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
    .tag.original { background: rgba(0,180,0,0.8); }
    .tag.clone { background: rgba(0,100,255,0.8); }
    /* Pixel-perfect diff table */
    .diff-table { width: 100%; border-collapse: collapse; font-size: 12px; margin-bottom: 32px; }
    .diff-table th, .diff-table td { padding: 6px 12px; border: 1px solid #333; text-align: left; }
    .diff-table th { background: #1a1a1a; }
    .diff-pass td { color: #4caf50; }
    .diff-fail td { color: #f44336; background: rgba(244,67,54,0.1); }
    .diff-summary { font-size: 18px; font-weight: bold; margin-bottom: 12px; }
    .diff-summary.pass { color: #4caf50; }
    .diff-summary.fail { color: #f44336; }
  </style>
</head>
<body>
  <h1>Original vs Clone</h1>

  <h2>Pixel-Perfect Diff (Numerical)</h2>
  <!-- Embed pixel-perfect-diff.json results as table -->
  <!-- Show: element, property, ref value, impl value, status -->
  <!-- Summary line: "N mismatches found" in red if any, "0 mismatches — pixel perfect" in green if none -->

  <button id="play-all">▶ Play All</button>

  <h2>Full Page (visual baseline)</h2>
  <!-- Side-by-side full page screenshots -->

  <h2>Scroll Transitions</h2>
  <!-- Paired videos with sync — one per scroll region in regions.json -->

  <h2>Hover Transitions</h2>
  <!-- Paired videos — one per hover region -->

  <h2>Cursor-Reactive (mousemove)</h2>
  <!-- Paired raster-path videos — one per mousemove region -->

  <h2>Auto-Timer</h2>
  <!-- Paired videos — one per timer region -->

  <script>
  // Sync paired videos
  // Rules:
  // 1. play/seek sync: when one plays or seeks, the other follows
  // 2. pause sync: only sync user-initiated pauses (not buffering/ended)
  // 3. different durations: when the shorter video ends, let the longer one finish
  // 4. busy flag: prevents recursive sync loops
  document.querySelectorAll('.pair').forEach(pair => {
    const videos = pair.querySelectorAll('video');
    if (videos.length !== 2) return;
    const [a, b] = videos;
    let busy = false;

    a.addEventListener('play',   () => { if (busy) return; busy = true; b.currentTime = a.currentTime; b.play().catch(()=>{}).finally(()=>{ busy = false; }); });
    b.addEventListener('play',   () => { if (busy) return; busy = true; a.currentTime = b.currentTime; a.play().catch(()=>{}).finally(()=>{ busy = false; }); });
    a.addEventListener('pause',  () => { if (!busy && !a.ended) b.pause(); });
    b.addEventListener('pause',  () => { if (!busy && !b.ended) a.pause(); });
    a.addEventListener('seeked', () => { if (!busy) b.currentTime = a.currentTime; });
    b.addEventListener('seeked', () => { if (!busy) a.currentTime = b.currentTime; });
    // ended: do NOT pause the other — let it finish
  });

  document.getElementById('play-all')?.addEventListener('click', () => {
    document.querySelectorAll('video').forEach(v => { v.currentTime = 0; v.play(); });
  });
  </script>
</body>
</html>
```

## Cursor-reactive (mousemove) section

For each cursor-reactive element, two raster-path videos side by side (same as other paired sections):

```html
<div class="pair">
  <div class="side">
    <span class="tag original">Original</span>
    <video src="transitions/ref/mousemove-<name>.mp4" controls loop></video>
  </div>
  <div class="side">
    <span class="tag clone">Clone</span>
    <video src="transitions/impl/mousemove-<name>.mp4" controls loop></video>
  </div>
</div>
```

The raster-path video sweeps all 100 grid points in sequence — no separate PNG grid needed. The video shows movement across the full element, making parallax/tilt response visible throughout.

## Serve

```bash
# Copy to project public dir if available
cp -r tmp/ref/capture public/ui-capture-compare

# Or standalone
npx serve tmp/ref/capture -p 3002
```

Present URL to user and wait for feedback. Do not proceed autonomously.

# ui-capture — Comparison Page

Generate `tmp/ref/capture/compare.html` for side-by-side human review of original vs clone.

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
    .matrix-grid { display: grid; grid-template-columns: repeat(10, 1fr); gap: 2px; }
    .matrix-grid img { width: 100%; border: 1px solid #222; }
  </style>
</head>
<body>
  <h1>Original vs Clone</h1>
  <button id="play-all">▶ Play All</button>

  <h2>Full Page (pixel-perfect baseline)</h2>
  <!-- Side-by-side full page screenshots -->

  <h2>Scroll Transitions</h2>
  <!-- Paired videos with sync — one per scroll region in regions.json -->

  <h2>Hover Transitions</h2>
  <!-- Paired videos — one per hover region -->

  <h2>Cursor-Reactive (mousemove)</h2>
  <!-- Paired videos + 10×10 matrix grids — one per mousemove region -->

  <h2>Auto-Timer</h2>
  <!-- Paired videos — one per timer region -->

  <script>
  // Sync paired videos
  document.querySelectorAll('.pair').forEach(pair => {
    const videos = pair.querySelectorAll('video');
    if (videos.length === 2) {
      videos[0].addEventListener('play', () => { videos[1].currentTime = videos[0].currentTime; videos[1].play(); });
      videos[1].addEventListener('play', () => { videos[0].currentTime = videos[1].currentTime; videos[0].play(); });
      videos[0].addEventListener('pause', () => videos[1].pause());
      videos[1].addEventListener('pause', () => videos[0].pause());
    }
  });

  document.getElementById('play-all')?.addEventListener('click', () => {
    document.querySelectorAll('video').forEach(v => { v.currentTime = 0; v.play(); });
  });
  </script>
</body>
</html>
```

## Matrix comparison section

For each cursor-reactive element, two 10×10 grids side by side:

```html
<div class="pair">
  <div class="side">
    <span class="tag original">Original</span>
    <div class="matrix-grid">
      <!-- 100 images: r0c0.png through r9c9.png -->
    </div>
  </div>
  <div class="side">
    <span class="tag clone">Clone</span>
    <div class="matrix-grid">
      <!-- 100 images: r0c0.png through r9c9.png -->
    </div>
  </div>
</div>
```

## Serve

```bash
# Copy to project public dir if available
cp -r tmp/ref/capture public/ui-capture-compare

# Or standalone
npx serve tmp/ref/capture -p 3002
```

Present URL to user and wait for feedback. Do not proceed autonomously.

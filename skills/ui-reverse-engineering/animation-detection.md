# Animation Detection — Step 6

Detect ALL motion on the page: splash/intro animations, auto-playing elements, scroll-driven transitions, and parallax effects. Uses **high-framerate video capture** + **per-element tracking**.

> This step runs AFTER interaction-detection.md (Step 5) and supplements it.
> Step 5 catches hover/click/intersection transitions.
> Step 6 catches everything that MOVES — with or without user input.

## Strategy: 3-Phase Motion Detection

```
Phase A: IDLE CAPTURE (no interaction)
  Record 8-10s video at page load. No scrolling, no mouse movement.
  → Detects: splash/intro animation, auto-timers, CSS animations, video autoplay

Phase B: SCROLL CAPTURE (scroll top to bottom)
  Record full scroll video at 60fps. Consistent scroll speed.
  → Detects: scroll-driven parallax, scale transitions, sticky elements,
             clip-path reveals, opacity fades, position changes

Phase C: PER-ELEMENT TRACKING (targeted)
  For each section/element identified in Phase A or B:
  Capture element-specific video + extract computed style at multiple scroll positions.
  → Produces: exact transform/opacity/scale values at each scroll %
```

---

## Phase A: Idle Capture (Splash + Auto-timers)

**Purpose:** Find everything that moves WITHOUT user interaction.

```bash
# 1. Open page and immediately start recording
agent-browser --session <project> open <url>
agent-browser --session <project> set viewport 1440 900
agent-browser --session <project> record start tmp/ref/<component>/idle-capture.webm

# 2. Wait 10 seconds — capture splash, intro, auto-playing elements
agent-browser --session <project> wait 10000

agent-browser --session <project> record stop

# 3. Extract frames at 10fps (sufficient for splash detection)
ffmpeg -i tmp/ref/<component>/idle-capture.webm -vf fps=10 tmp/ref/<component>/idle-frames/frame-%04d.png -y
```

### Analyze idle frames

Read consecutive frame pairs to identify what changed:

1. **Frames 1-10 (0-1s):** Loading state — spinner, skeleton, blank screen
2. **Frames 10-30 (1-3s):** Splash/intro animation — logo reveal, curtain open, text stagger
3. **Frames 30-50 (3-5s):** Site visible — identify splash→content transition point
4. **Frames 50-100 (5-10s):** Auto-timers — carousel rotation, text cycling, video playback

**For each detected motion region, record:**

```json
{
  "phase": "idle",
  "type": "splash | auto-timer | css-animation | video-autoplay",
  "frameRange": [1, 30],
  "description": "White screen → logo center → fade out → hero video reveal",
  "duration_ms": 3000
}
```

### Splash vs. actual site boundary

Find the frame where the site's actual content first appears:
- Splash = overlay/loading screen that covers the entire viewport
- Content = first frame where hero/navigation is visible underneath

```bash
# Check if an overlay element exists and when it disappears
agent-browser --session <project> eval "(() => {
  const overlays = document.querySelectorAll('[class*=load], [class*=intro], [class*=splash], [class*=preload], [class*=curtain], [class*=overlay]');
  return JSON.stringify(Array.from(overlays).map(el => ({
    cls: el.className?.toString?.().slice(0, 60),
    display: getComputedStyle(el).display,
    opacity: getComputedStyle(el).opacity,
    visibility: getComputedStyle(el).visibility,
    zIndex: getComputedStyle(el).zIndex,
    position: getComputedStyle(el).position,
  })));
})()"
```

### Splash end-state verification (MANDATORY if splash detected)

After implementation, verify the splash sequence **terminates cleanly**:

1. Record impl splash (same as Phase A — open page, record 10s)
2. Extract frames at 10fps
3. Compare key frames (at same timestamps) between ref and impl:

| Timestamp | Check | Ref frame | Impl frame | Pass? |
|-----------|-------|-----------|------------|-------|
| Last splash frame | All animated elements fully hidden/removed | ? | ? | ? |
| First content frame | Main content visible, no splash remnants | ? | ? | ? |
| +2s after splash | No leftover elements (check DOM for splash nodes with display/opacity) | ? | ? | ? |

**Common splash failures:**
- Animated elements (3D objects, logos) remain visible after splash ends — missing opacity/visibility transition to terminal state
- Overlay z-index not reset — splash overlay blocks interaction after animation completes
- Content scale/opacity animation not triggered — content stays at initial state (e.g., `scale(0.8)`)

```bash
# Post-splash DOM check — run after splash should have completed
agent-browser --session <project> wait 8000
agent-browser --session <project> eval "(() => {
  const remnants = document.querySelectorAll('[class*=intro], [class*=splash], [class*=overlay], [class*=preload]');
  return JSON.stringify(Array.from(remnants).map(el => ({
    cls: el.className?.toString?.().slice(0, 40),
    display: getComputedStyle(el).display,
    opacity: getComputedStyle(el).opacity,
    pointerEvents: getComputedStyle(el).pointerEvents,
    note: el.offsetHeight > 0 ? 'STILL VISIBLE — should be removed or hidden' : 'hidden/removed ✓',
  })));
})()"
```

---

## Phase B: Scroll Capture (Scroll-driven motion)

**Purpose:** Find everything that moves DURING scroll.

### B-1: Record full scroll video at native framerate

```bash
# Scroll to top first
agent-browser --session <project> eval "(() => {
  const lenis = document.querySelector('[class*=lenis], [class*=scroll]');
  if (lenis && lenis.scrollTop !== undefined) lenis.scrollTop = 0;
  window.scrollTo(0, 0);
})()"
agent-browser --session <project> wait 2000

# Start recording
agent-browser --session <project> record start tmp/ref/<component>/scroll-capture.webm

# Wait for recording to start
agent-browser --session <project> wait 500

# Scroll through entire page — SLOW and CONSISTENT
# Method 1: Lenis/custom scroll container
agent-browser --session <project> eval "(() => {
  const lenis = document.querySelector('[class*=lenis], [class*=scroll]');
  const container = lenis || document.documentElement;
  const maxScroll = container.scrollHeight - window.innerHeight;
  let pos = 0;
  const speed = 80; // px per step
  const interval = 50; // ms between steps
  const step = () => {
    pos = Math.min(pos + speed, maxScroll);
    if (lenis) lenis.scrollTop = pos;
    else window.scrollTo(0, pos);
    if (pos < maxScroll) setTimeout(step, interval);
  };
  step();
  return 'scrolling ' + maxScroll + 'px';
})()"

# Wait for scroll to complete (pageHeight / speed * interval + buffer)
agent-browser --session <project> wait 12000

agent-browser --session <project> wait 1000
agent-browser --session <project> record stop

# Extract at 60fps for precise motion analysis
ffmpeg -i tmp/ref/<component>/scroll-capture.webm -vf fps=60 tmp/ref/<component>/scroll-frames/frame-%06d.png -y
```

### B-2: Track elements across scroll positions

**Instead of just comparing frames visually**, track specific elements' computed styles at multiple scroll positions. This catches parallax, scale, sticky, clip-path that screenshots miss.

```bash
agent-browser --session <project> eval "(() => {
  const lenis = document.querySelector('[class*=lenis], [class*=scroll]');
  const container = lenis || document.documentElement;
  const maxScroll = container.scrollHeight - window.innerHeight;

  // Target elements: all sections + key visual elements
  const targets = [];
  document.querySelectorAll('section, [class*=banner], [class*=hero], [class*=asset], [class*=project], [class*=review], footer').forEach(el => {
    const cn = typeof el.className === 'string' ? el.className : '';
    targets.push({ el, selector: el.tagName.toLowerCase() + '.' + cn.trim().split(/\s+/)[0] });
  });

  // Also track images and videos inside sections
  document.querySelectorAll('section img, section video, [class*=background]').forEach(el => {
    const cn = typeof el.className === 'string' ? el.className : '';
    targets.push({ el, selector: el.tagName.toLowerCase() + '.' + cn.trim().split(/\s+/)[0] });
  });

  // Sample at 10 scroll positions (0%, 10%, 20%, ... 100%)
  const samples = [];
  const positions = Array.from({ length: 11 }, (_, i) => Math.round(maxScroll * i / 10));

  let posIndex = 0;
  const capture = () => {
    if (posIndex >= positions.length) {
      window.__elementTracking = samples;
      return;
    }

    const scrollPos = positions[posIndex];
    if (lenis) lenis.scrollTop = scrollPos;
    else window.scrollTo(0, scrollPos);

    // Wait a tick for paint, then measure
    requestAnimationFrame(() => {
      const snapshot = { scrollY: scrollPos, scrollPct: Math.round(scrollPos / maxScroll * 100), elements: [] };

      targets.forEach(({ el, selector }) => {
        const s = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        snapshot.elements.push({
          selector,
          inViewport: r.bottom > 0 && r.top < window.innerHeight,
          top: Math.round(r.top),
          transform: s.transform !== 'none' ? s.transform.slice(0, 80) : null,
          opacity: s.opacity !== '1' ? s.opacity : null,
          scale: s.scale !== 'none' ? s.scale : null,
          clipPath: s.clipPath !== 'none' ? s.clipPath : null,
          position: s.position === 'sticky' || s.position === 'fixed' ? s.position : null,
        });
      });

      samples.push(snapshot);
      posIndex++;
      setTimeout(capture, 200);
    });
  };

  capture();
  return 'tracking ' + targets.length + ' elements across ' + positions.length + ' scroll positions';
})()"

# Wait for tracking to complete
agent-browser --session <project> wait 5000

# Retrieve results
agent-browser --session <project> eval "(() => JSON.stringify(window.__elementTracking || [], null, 2))()"
```

**Save to** `tmp/ref/<component>/element-tracking.json`

### B-3: Classify detected animations

For each element in `element-tracking.json`, compare values across scroll positions:

| Pattern | Classification | What to look for |
|---------|---------------|-----------------|
| `transform` changes with scroll | **parallax** | translateY value changes but at different rate than scrollY |
| `transform: scale()` changes | **scroll-zoom** | scale increases as element enters viewport |
| `opacity` goes 0→1 | **scroll-reveal** | Element fades in when entering viewport |
| `clipPath` changes | **clip-reveal** | Clipping area expands on scroll |
| `position: sticky` at some positions | **sticky/pinned** | Element stays fixed during scroll range |
| `top` stays constant while scroll moves | **fixed-in-section** | Image fixed while container scrolls past |
| Element visible but `transform` has large translateY | **parallax offset** | Image moves slower than container |

---

## Phase C: Per-Element Deep Capture

For each animation detected in Phase B, capture a **targeted video** of just that element:

```bash
# 1. Scroll to just before the element triggers
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  const rect = el.getBoundingClientRect();
  const scrollPos = rect.top + window.scrollY - window.innerHeight;
  window.scrollTo(0, Math.max(0, scrollPos));
})()"
agent-browser --session <project> wait 500

# 2. Record while scrolling through the element
agent-browser --session <project> record start tmp/ref/<component>/element-<name>.webm

agent-browser --session <project> eval "(() => {
  // Scroll slowly through the element's range
  const el = document.querySelector('<selector>');
  const rect = el.getBoundingClientRect();
  const startPos = window.scrollY;
  const endPos = startPos + rect.height + window.innerHeight;
  let pos = startPos;
  const step = () => {
    pos += 40;
    window.scrollTo(0, pos);
    if (pos < endPos) setTimeout(step, 50);
  };
  step();
})()"

agent-browser --session <project> wait 5000
agent-browser --session <project> record stop

# 3. Extract at 60fps
ffmpeg -i tmp/ref/<component>/element-<name>.webm -vf fps=60 tmp/ref/<component>/element-<name>-frames/frame-%06d.png -y
```

### Extract exact values at key frames

For each element video, extract computed style at: before trigger, 25%, 50%, 75%, after trigger.

```bash
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  const s = getComputedStyle(el);
  return JSON.stringify({
    transform: s.transform,
    opacity: s.opacity,
    scale: s.scale,
    clipPath: s.clipPath,
    position: s.position,
    top: s.top,
    width: s.width,
    height: s.height,
  });
})()"
```

---

## Save: animations-detected.json

Combine all findings from Phase A, B, C:

```json
{
  "splash": {
    "type": "splash",
    "phases": [
      { "name": "loading", "duration_ms": 600, "description": "White screen + spinner/loader" },
      { "name": "logo", "duration_ms": 1400, "description": "Brand logo + wordmark reveal" },
      { "name": "reveal", "duration_ms": 800, "description": "Overlay fades out, main content visible" }
    ],
    "totalDuration_ms": 2800
  },
  "autoTimers": [
    { "selector": ".carousel", "interval_ms": 4000, "type": "slideshow" }
  ],
  "scrollAnimations": [
    {
      "selector": "section.product-collection .block",
      "type": "parallax",
      "scrollRange": { "start": 1200, "end": 2800 },
      "properties": {
        "translateY": { "from": 200, "to": 0 }
      },
      "ease": "linear (scroll-driven)"
    },
    {
      "selector": "section.banner-showroom .background",
      "type": "scroll-zoom",
      "scrollRange": { "start": 3000, "end": 4200 },
      "properties": {
        "scale": { "from": 0.55, "to": 1.0 }
      }
    },
    {
      "selector": ".border",
      "type": "scroll-reveal",
      "scrollRange": { "start": 3500, "end": 4000 },
      "properties": {
        "scaleX": { "from": 0, "to": 1 }
      }
    },
    {
      "selector": ".column",
      "type": "scroll-converge",
      "scrollRange": { "start": 3500, "end": 4500 },
      "properties": {
        "translateX": { "from": "±58.5px", "to": "0px" }
      }
    },
    {
      "selector": "section.assets-duo img",
      "type": "parallax",
      "scrollRange": { "start": 5000, "end": 6000 },
      "properties": {
        "translateY": { "speeds": ["slow", "fast"], "delta": [80, 120] }
      }
    }
  ],
  "textReveals": [
    {
      "selector": ".text-cta p",
      "type": "word-stagger",
      "triggerType": "intersection",
      "params": { "stagger_ms": 30, "duration_ms": 800, "ease": "power3.inOut", "translateY": "110%" }
    }
  ]
}
```

---

## Integration with Step 7 (Generation)

When generating components, for each animation in `animations-detected.json`:

| Animation type | Implementation |
|---------------|----------------|
| `splash` | `IntroOverlay` component with phased setTimeout |
| `auto-timer` | `setInterval` + state cycling |
| `parallax` | `useScroll` + `useTransform` from @beyond/react |
| `scroll-zoom` | `useScroll` + `useTransform` for scale |
| `scroll-reveal` | `ScrollReveal` or `LineReveal` component |
| `scroll-converge` | `useScroll` + `useTransform` for translateX |
| `word-stagger` | `WordReveal` component |
| `sticky/pinned` | CSS `position: sticky` with appropriate `top` value |
| `clip-reveal` | `useScroll` + `useTransform` for clipPath |

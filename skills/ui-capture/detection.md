# ui-capture — Transition Detection

Detect all interactive regions on the page and filter to a manageable set for capture.

## Step 2A: Run detection script

```bash
agent-browser eval "(() => {
  const results = { scroll: [], hover: [], mousemove: [], timer: [] };

  // --- Scroll transitions ---
  const allElements = document.querySelectorAll('*');
  const scrollCandidates = [];
  for (const el of allElements) {
    const s = getComputedStyle(el);
    if (s.willChange !== 'auto' ||
        s.transform !== 'none' ||
        s.transition !== 'all 0s ease 0s' ||
        el.style.cssText.includes('scroll')) {
      const rect = el.getBoundingClientRect();
      if (rect.width > 50 && rect.height > 50) {
        scrollCandidates.push({
          selector: genSelector(el),
          y: rect.top + window.scrollY,
          height: rect.height
        });
      }
    }
  }
  results.scroll = scrollCandidates;

  // --- Hover transitions ---
  for (const el of allElements) {
    const s = getComputedStyle(el);
    if (s.transitionDuration !== '0s' || s.transitionProperty !== 'all') {
      const rect = el.getBoundingClientRect();
      if (rect.width > 20 && rect.height > 20) {
        results.hover.push({
          selector: genSelector(el),
          y: rect.top + window.scrollY,
          width: rect.width,
          height: rect.height
        });
      }
    }
  }

  // --- Mousemove listeners (class/attribute heuristic) ---
  const movePatterns = ['parallax', 'tilt', 'magnetic', 'cursor', 'mouse', 'follow'];
  for (const el of allElements) {
    const classes = el.className.toString().toLowerCase();
    const id = (el.id || '').toLowerCase();
    if (movePatterns.some(p => classes.includes(p) || id.includes(p))) {
      const rect = el.getBoundingClientRect();
      results.mousemove.push({
        selector: genSelector(el),
        y: rect.top + window.scrollY,
        width: rect.width,
        height: rect.height
      });
    }
  }

  // --- Auto-timer (carousels, slideshows) ---
  const timerPatterns = ['carousel', 'slider', 'slide', 'swiper', 'autoplay'];
  for (const el of allElements) {
    const classes = el.className.toString().toLowerCase();
    if (timerPatterns.some(p => classes.includes(p))) {
      const rect = el.getBoundingClientRect();
      results.timer.push({
        selector: genSelector(el),
        y: rect.top + window.scrollY,
        width: rect.width,
        height: rect.height
      });
    }
  }

  function genSelector(el) {
    if (el.id) return '#' + el.id;
    if (el.dataset.testid) return '[data-testid=\"' + el.dataset.testid + '\"]';
    const path = [];
    let cur = el;
    while (cur && cur !== document.body) {
      let seg = cur.tagName.toLowerCase();
      if (cur.className && typeof cur.className === 'string') {
        const cls = cur.className.trim().split(/\s+/).slice(0, 2).join('.');
        if (cls) seg += '.' + cls;
      }
      path.unshift(seg);
      cur = cur.parentElement;
      if (path.length >= 3) break;
    }
    return path.join(' > ');
  }

  return JSON.stringify(results, null, 2);
})()"
```

**Scroll-based detection (more reliable):** Scroll top to bottom and compare computed styles at each step — elements whose `transform`/`opacity`/`clipPath` change are scroll-triggered.

```bash
agent-browser eval "(() => {
  const transitions = [];
  const vh = window.innerHeight;
  const total = document.body.scrollHeight;
  const steps = Math.ceil(total / (vh * 0.5));
  let prevStyles = {};

  for (let i = 0; i <= steps; i++) {
    const y = Math.min(i * vh * 0.5, total - vh);
    window.scrollTo(0, y);

    const visible = document.elementsFromPoint(720, 450);
    const curStyles = {};
    for (const el of visible.slice(0, 20)) {
      const s = getComputedStyle(el);
      const key = el.tagName + (el.id ? '#' + el.id : '') + '.' + (el.className || '').toString().slice(0, 30);
      curStyles[key] = {
        transform: s.transform,
        opacity: s.opacity,
        clipPath: s.clipPath,
        scale: s.scale
      };
      if (prevStyles[key]) {
        const p = prevStyles[key];
        if (p.transform !== s.transform || p.opacity !== s.opacity || p.clipPath !== s.clipPath || p.scale !== s.scale) {
          transitions.push({ element: key, scrollY: y, changed: Object.keys(p).filter(k => p[k] !== curStyles[key][k]) });
        }
      }
    }
    prevStyles = { ...prevStyles, ...curStyles };
  }
  return JSON.stringify(transitions);
})()"
```

**Mousemove listener check (DevTools protocol):**

```bash
agent-browser eval "(() => {
  const found = [];
  const walk = (el) => {
    if (typeof getEventListeners === 'function') {
      const listeners = getEventListeners(el);
      if (listeners.mousemove && listeners.mousemove.length > 0) {
        const rect = el.getBoundingClientRect();
        found.push({
          selector: el.tagName + (el.id ? '#' + el.id : ''),
          y: rect.top + window.scrollY,
          width: rect.width,
          height: rect.height,
          listenerCount: listeners.mousemove.length
        });
      }
    }
    for (const child of el.children) walk(child);
  };
  walk(document.body);
  return JSON.stringify(found);
})()"
```

## Step 2A-2: Filter & deduplicate

Raw detection returns too many elements. Apply these rules before capturing:

1. **Parent absorbs children** — if parent and descendants share the same transition type, keep only the parent
2. **Sibling grouping** — if 5+ siblings have identical transition properties, group under parent
3. **Size threshold** — discard elements smaller than 50×50px (unless only interactive element in section)
4. **Actual change verification** — hover each candidate and compare `getComputedStyle` before/after; discard if nothing changes

```bash
agent-browser eval "(() => {
  const candidates = <hover-candidates-from-2A>;
  const verified = [];
  for (const c of candidates) {
    const el = document.querySelector(c.selector);
    if (!el) continue;
    const before = getComputedStyle(el);
    const beforeSnap = {
      transform: before.transform, opacity: before.opacity,
      backgroundColor: before.backgroundColor, color: before.color,
      boxShadow: before.boxShadow, borderColor: before.borderColor, scale: before.scale
    };
    el.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
    const after = getComputedStyle(el);
    const changed = Object.keys(beforeSnap).some(k => beforeSnap[k] !== after[k]);
    el.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true }));
    if (changed) verified.push(c);
  }
  return JSON.stringify(verified);
})()"
```

**Target: ≤20 total regions** across all types. If more, prioritize:
1. Unique effects > repeated
2. Large visual area > small
3. Complex animation > simple color change

## Save regions.json

```json
{
  "url": "<reference-url>",
  "capturedAt": "<ISO timestamp>",
  "page": { "totalHeight": 14886, "viewportWidth": 1440, "viewportHeight": 900 },
  "scroll": [
    { "name": "hero-zoom", "from": 0, "to": 1800, "elements": ["selector1"], "changedProperties": ["transform", "opacity"] }
  ],
  "hover": [
    { "name": "nav-links", "selector": ".nav a", "y": 0, "bounds": { "width": 200, "height": 40 }, "transitionDuration": "300ms" }
  ],
  "mousemove": [
    { "name": "hero-parallax", "selector": ".hero-bg", "y": 0, "bounds": { "width": 1440, "height": 900 }, "matrix": "10x10", "patterns": ["horizontal", "diagonal", "circular"] }
  ],
  "timer": [
    { "name": "carousel", "selector": ".carousel", "y": 3600, "interval_ms": 5000 }
  ]
}
```

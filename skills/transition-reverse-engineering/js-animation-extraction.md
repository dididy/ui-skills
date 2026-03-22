# JS-Driven Animation — Bundle Extraction Reference

**Critical: `getComputedStyle()` only shows the CURRENT value of a property. It does NOT reveal animation from/to values, interpolation ranges, easing curves, or scroll progress mappings. For JS-driven animations, you MUST extract the actual code from JS bundles.**

## When to use this path

Use JS bundle extraction when ANY of these are true:
- Animation is scroll-driven (scroll-linked zoom, parallax, sticky animations)
- `getComputedStyle()` returns `transform: none` even though the element visually transforms
- `el.getAnimations()` returns empty (scroll-driven animations via Motion/GSAP don't use WAAPI)
- `willChange` includes `transform` or `opacity` but `transition` is `0s` and `animation` is `none`
- Element uses Motion (`motion.div`, `E.div`), GSAP (`gsap.to`), or rAF-based animation
- Values change only during scroll (not on hover/click/load)

## Step 1: Find the relevant JS chunk

```bash
agent-browser eval "(() => {
  const scripts = document.querySelectorAll('script[src]');
  return [...scripts].map(s => s.src);
})()"
```

## Step 2: Search ALL chunks for animation keywords

```js
// Search each chunk for animation-related code
agent-browser eval "(() => {
  const scripts = document.querySelectorAll('script[src]');
  const findings = [];

  // Use the known CSS class names as search anchors
  const CLASS_NAMES = ['gridWrapper', 'featuredWrapper', 'cardStack']; // from DOM inspection
  const ANIM_PATTERNS = [
    'useTransform', 'useScroll', 'scrollYProgress', 'scrollXProgress',
    'animateTo', 'ViewTimeline', 'ScrollTimeline',
    'gsap.to', 'gsap.from', 'gsap.timeline',
    'useMotionValue', 'useSpring',
    'requestAnimationFrame',
    'scale(', 'opacity:', 'translateY', 'translateX',
  ];

  return Promise.all([...scripts].map(async (script) => {
    try {
      const resp = await fetch(script.src);
      const text = await resp.text();
      const patterns = [...CLASS_NAMES, ...ANIM_PATTERNS];
      const matches = [];
      for (const p of patterns) {
        if (text.includes(p)) matches.push(p);
      }
      if (matches.length >= 2) {
        return { src: script.src.split('/').pop(), matches, size: text.length };
      }
    } catch(e) {}
    return null;
  })).then(r => r.filter(Boolean));
})()"
```

## Step 3: Extract the animation function

Once you identify the chunk, extract a **wide context** (500+ chars) around each class name anchor:

```js
agent-browser eval "(async () => {
  const resp = await fetch('https://site.com/_next/static/chunks/CHUNK_ID.js');
  const text = await resp.text();

  // Search for the component that uses scrollYProgress / animation
  const ANCHORS = ['scrollYProgress', 'gridWrapper', 'useTransform'];
  const snippets = {};

  for (const anchor of ANCHORS) {
    let idx = -1;
    const occurrences = [];
    while ((idx = text.indexOf(anchor, idx + 1)) !== -1 && occurrences.length < 3) {
      occurrences.push(text.substring(Math.max(0, idx - 200), idx + 500));
    }
    if (occurrences.length > 0) snippets[anchor] = occurrences;
  }

  return JSON.stringify(snippets);
})()"
```

## Step 4: Decode minified animation patterns

### Motion (Framer Motion) patterns

| Minified pattern | Original API | What to extract |
|-----------------|-------------|-----------------|
| `(0,a.H)(e,[0,.5,1],[0,0,1])` | `useTransform(scrollProgress, [0,.5,1], [0,0,1])` | Input range, output range |
| `(0,r.v)({target:m,offset:[...]})` | `useScroll({target:ref, offset:[...]})` | Scroll offset (e.g. `"start start"`, `"end end"`) |
| `(0,o.E.div,{style:{scale:u}})` | `<motion.div style={{scale}}>` | Which property is animated |
| `(0,a.H)(j,[0,.5,1],["16px",R,R])` | `useTransform(progress, [0,.5,1], ["16px", R, R])` | String interpolation (borderRadius, width, etc.) |

### Key: identify `useTransform` calls

`useTransform(progress, inputRange, outputRange)` is the core interpolation API.
- 2-point: `[0, 1], [startVal, endVal]` — linear
- 3-point: `[0, 0.5, 1], [a, b, c]` — two-segment piecewise linear
- The input range maps to `scrollYProgress` (0 = scroll start, 1 = scroll end)

### Key: identify `useScroll` offset

```
offset: ["start start", "end end"]
```
- First value = element edge (start=top, end=bottom)
- Second value = viewport edge (start=top, end=bottom)
- `"start start"` to `"end end"` = progress 0 when element top hits viewport top, progress 1 when element bottom hits viewport bottom
- Scroll distance = `containerHeight - viewportHeight`

### GSAP patterns

| Minified | Original | Extract |
|----------|----------|---------|
| `gsap.to(el, {attr:{"stroke-dashoffset":0}})` | SVG stroke draw | from/to dashoffset |
| `ScrollTrigger.create({trigger:el})` | Scroll-linked | start/end positions |
| `timeline.to(el, {y:0}, "<")` | Timeline sequence | keyframes + positions |

### CSS-in-JS patterns

Also extract the **CSS module mappings** — they tell you which hashed class corresponds to which semantic name:

```js
// Look for the CSS module object
// e.g.: e.exports={scrollcontainer:"style_scrollcontainer__Vup4r",sticky:"style_sticky__o3IHf",...}
```

## Step 5: Extract CSS stylesheets for layout values

`getComputedStyle()` gives resolved pixel values but NOT the original CSS expressions. For responsive layouts you need the actual CSS:

```js
agent-browser eval "(async () => {
  const links = document.querySelectorAll('link[rel=\"stylesheet\"]');
  const results = [];
  for (const link of links) {
    try {
      const resp = await fetch(link.href);
      const text = await resp.text();
      // Search for your target class
      if (text.includes('TARGET_CLASS')) {
        const idx = text.indexOf('.TARGET_CLASS');
        results.push(text.substring(idx, idx + 500));
      }
    } catch(e) {}
  }
  return results;
})()"
```

**Why this matters:**
- `width: 1216px` (computed) vs `width: calc(100vw - 64px)` (actual CSS) — the computed value is only correct for the current viewport
- `inset: -720px` (computed) vs `inset: -100%` (actual) — percentage-based inset is responsive, pixel value is not
- `width: 213px` (computed) vs `width: calc(100cqw / var(--num-items))` (actual) — container query units are essential for responsiveness

## Common pitfalls

### 1. "Computed values match but animation looks wrong"
`getComputedStyle()` captures ONE frame. A 3-point `useTransform([0,.5,1], [0,0,1])` means the value stays at 0 for the first 50% of scroll then ramps to 1. You can't detect this timing from a single computed value.

### 2. "transform: none" even though element moves
Scroll-driven animations via Motion's `useTransform` set `style.transform` reactively. Between scroll events, `getComputedStyle().transform` may read as `none`. The actual values only exist in Motion's reactive system.

### 3. "Scale on wrapper" vs "Scale on children"
Often the visible zoom effect is NOT on the wrapper div — individual child elements scale independently from their centers. The wrapper provides the oversized positioning space. Always check both wrapper AND children transforms.

### 4. "once: true" vs toggle
Check whether an IntersectionObserver-based trigger fires once or toggles by scrolling to/away/back in the extracted code. Look for `observer.disconnect()` (once) vs continued observation (toggle).

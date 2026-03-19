# Interaction Detection — Steps 5 & 6

> All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.

## Step 5: Detect Interactions

### Classify interaction type

```bash
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({
    hasTransition: s.transitionDuration !== '0s',
    transition: s.transition,
    hasAnimation: s.animationName !== 'none',
    animation: s.animationName,
    canvases: document.querySelectorAll('canvas').length,
    willChange: s.willChange,
  });
})()
"
```

| Signal | Next step |
|--------|-----------|
| `hasTransition: true` | Capture hover states — see below |
| `hasAnimation: true` | Extract keyframes — see below |
| `canvases > 0` | **Invoke `transition-reverse-engineering` skill now** |
| Scroll-triggered transitions | Detect & extract — see below |
| Complex JS interactions | Step 6: Bundle analysis |

### Detect scroll-triggered transitions

```bash
# 1. Set up recorder before scrolling
agent-browser eval "
(() => {
  window.__scrollTransitions = [];
  const candidates = document.querySelectorAll('[class*=fade], [class*=slide], [class*=reveal], [class*=animate], [data-aos]');
  const allEls = candidates.length > 0 ? candidates : document.querySelectorAll('section, h1, h2, h3, p, img, .card');
  const props = ['opacity', 'transform', 'filter', 'clipPath'];
  Array.from(allEls).slice(0, 30).forEach((el, i) => {
    const before = {};
    props.forEach(p => before[p] = getComputedStyle(el)[p]);
    const observer = new IntersectionObserver(entries => {
      entries.forEach(e => {
        const after = {};
        props.forEach(p => after[p] = getComputedStyle(e.target)[p]);
        const changed = props.filter(p => after[p] !== before[p]);
        if (changed.length > 0) {
          window.__scrollTransitions.push({
            index: i,
            selector: el.tagName.toLowerCase() + (el.className ? '.' + el.className.toString().trim().split(' ')[0].replace(/[^a-zA-Z0-9_-]/g, '') : ''),
            ratio: e.intersectionRatio,
            changed,
            before: Object.fromEntries(changed.map(p => [p, before[p]])),
            after: Object.fromEntries(changed.map(p => [p, after[p]])),
            transition: getComputedStyle(e.target).transition,
          });
        }
        props.forEach(p => before[p] = after[p]);
      });
    }, { threshold: [0, 0.1, 0.5, 1.0] });
    observer.observe(el);
  });
  return 'Observing ' + allEls.length + ' elements';
})()
"

# 2. Scroll through the page
agent-browser scroll down 300
agent-browser wait 800
agent-browser scroll down 300
agent-browser wait 800
agent-browser scroll down 300
agent-browser wait 800
agent-browser scroll down 300
agent-browser wait 800

# 3. Retrieve results
agent-browser eval "(() => JSON.stringify(window.__scrollTransitions || [], null, 2))()"
```

**Save results to** `tmp/ref/<component>/scroll-transitions.json`

| Result | Next step |
|--------|-----------|
| Empty `[]` | No scroll-triggered transitions — continue |
| CSS transition values | Implement with `IntersectionObserver` + CSS transitions |
| Complex WAAPI / stagger | **Invoke `transition-reverse-engineering` skill now.** Resume at Step 7 after `extracted.json` is saved. |

### Capture hover state delta

```bash
# Before hover — record baseline
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  window.__before = {
    opacity: s.opacity, transform: s.transform,
    backgroundColor: s.backgroundColor, boxShadow: s.boxShadow,
    color: s.color, filter: s.filter,
  };
  return JSON.stringify(window.__before);
})()
"

agent-browser hover .target
agent-browser wait 600

# After hover — compute delta
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  const after = {
    opacity: s.opacity, transform: s.transform,
    backgroundColor: s.backgroundColor, boxShadow: s.boxShadow,
    color: s.color, filter: s.filter,
  };
  const delta = {};
  Object.keys(after).forEach(k => {
    if (after[k] !== window.__before[k]) delta[k] = { from: window.__before[k], to: after[k] };
  });
  return JSON.stringify({ transition: s.transition, delta }, null, 2);
})()
"
```

### Extract CSS keyframes

```bash
agent-browser eval "
(() => {
  const keyframes = {};
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSKeyframesRule) {
          keyframes[rule.name] = Array.from(rule.cssRules).map(kf => ({
            offset: kf.keyText,
            style: kf.style.cssText,
          }));
        }
      }
    } catch(e) {}
  }
  return JSON.stringify(keyframes, null, 2);
})()
"
```

> **Complex animations (character stagger, canvas/WebGL, WAAPI, page-load):**
> Invoke the `transition-reverse-engineering` skill now.
> Resume here at Step 7 after `tmp/ref/<effect-name>/extracted.json` is saved.

---

## Step 6: JS Bundle Analysis (if needed)

For interactions driven by JavaScript (not CSS transitions), analyze the bundle.

```bash
# Get script URLs
agent-browser eval "
(() => {
  return JSON.stringify(
    Array.from(document.querySelectorAll('script[src]')).map(s => s.src)
  );
})()
"

# Download relevant chunk — replace <bundle-url> with actual URL (HTTPS only)
BUNDLE_URL="<bundle-url>"
if ! [[ "$BUNDLE_URL" =~ ^https:// ]]; then
  echo "Error: bundle URL must use HTTPS" >&2
  exit 1
fi
mkdir -p tmp/ref/<component>/bundles
# --max-filesize 10485760 = 10 MB limit. If bundle is larger, remove this flag or download manually.
curl -s --max-time 30 --max-filesize 10485760 --fail --location \
  -o tmp/ref/<component>/bundles/main.js \
  -- "$BUNDLE_URL" || { echo "Failed to download bundle (may exceed 10 MB limit)" >&2; exit 1; }

# Find interaction logic
grep -E 'addEventListener|onClick|onMouseEnter|useEffect|motion\.|animate\(' \
  tmp/ref/<component>/bundles/main.js | head -40
```

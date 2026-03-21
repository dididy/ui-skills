# CSS Path — Extraction Reference

**Save all extracted data to `tmp/ref/<effect-name>/` — CSS values, computed styles, keyframes. Never re-extract from the live site.**

> All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.

> **CRITICAL: Before extracting individual properties, run the multi-point measurement pass (Step -1 in SKILL.md → `measurement.md`).** The 11-point measurement reveals multi-phase timing and property-specific phase boundaries that start/end extraction alone will miss.

## Static state extraction

```bash
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  const props = [
    'opacity', 'transform', 'transformOrigin', 'clipPath',
    'filter', 'boxShadow', 'backgroundColor', 'color',
    'borderRadius', 'width', 'height', 'maxWidth', 'maxHeight',
    'scale', 'translate', 'maskImage', 'perspective',
  ];
  const result = {};
  props.forEach(p => result[p] = s[p]);
  return JSON.stringify(result, null, 2);
})()"
```

## Detect trigger type

```bash
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({
    hasTransition: s.transitionDuration !== '0s',
    transitionProps: s.transitionProperty,
    transitionDuration: s.transitionDuration,
    transitionEasing: s.transitionTimingFunction,
    animationName: s.animationName,
    animationDuration: s.animationDuration,
    currentState: { opacity: s.opacity, transform: s.transform, clipPath: s.clipPath },
  });
})()"
```

## Extract CSS keyframes

```bash
agent-browser eval "
(() => {
  const keyframes = {};
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSKeyframesRule) {
          const frames = [];
          for (const kf of rule.cssRules) {
            frames.push({ offset: kf.keyText, style: kf.style.cssText });
          }
          keyframes[rule.name] = frames;
        }
      }
    } catch(e) {} // cross-origin stylesheet — use curl fallback below
  }
  return JSON.stringify(keyframes, null, 2);
})()"
```

If cross-origin blocks access:
```bash
# Get stylesheet URLs
agent-browser eval "
(() => {
  return JSON.stringify(
    Array.from(document.querySelectorAll('link[rel=stylesheet]')).map(l => l.href)
  );
})()"
# Then download and grep for @keyframes and transition rules (HTTPS only)
# Replace <stylesheet-url> with actual URL — must start with https://
if ! [[ "<stylesheet-url>" =~ ^https:// ]]; then echo "Error: stylesheet URL must be HTTPS" >&2; exit 1; fi
curl -s --max-time 30 --max-filesize 10485760 --fail -- "<stylesheet-url>" | grep -E '@keyframes|transition'
```

## Children state capture

Transitions often cascade to children:

```bash
agent-browser eval "
(() => {
  const parent = document.querySelector('.target');
  if (!parent) return JSON.stringify({ error: 'selector not found' });
  return JSON.stringify(
    Array.from(parent.querySelectorAll('*')).slice(0, 20).map((el, i) => {
      const s = getComputedStyle(el);
      return {
        index: i, tag: el.tagName, class: (typeof el.className === 'string' ? el.className : el.className?.baseVal || '').slice(0, 50),
        opacity: s.opacity, transform: s.transform,
        transition: s.transition, transitionDelay: s.transitionDelay,
      };
    })
  );
})()"
```

## Frame capture — hover transitions

```bash
# 1. Set up frame recorder (clears any previous __frames data)
agent-browser eval "
(() => {
  window.__frames = [];
  const el = document.querySelector('.target');
  if (!el) return 'selector not found';
  const props = ['opacity','transform','clipPath','filter','boxShadow','width','height','backgroundColor'];
  const start = performance.now();
  const id = setInterval(() => {
    const s = getComputedStyle(el);
    const frame = { t: performance.now() - start };
    props.forEach(p => frame[p] = s[p]);
    window.__frames.push(frame);
    if (performance.now() - start > 2000) clearInterval(id);
  }, 16);
  return 'Recording...';
})()"

# 2. Trigger hover
agent-browser hover .target
agent-browser wait 2500

# 3. Retrieve frames
agent-browser eval "(() => JSON.stringify(window.__frames, null, 2))()"
```

## Frame capture — page-load animations

```bash
agent-browser open https://target-site.com

agent-browser eval "
(() => {
  window.__frames = [];
  const el = document.querySelector('.target');
  if (!el) return 'Element not found';
  const props = ['opacity','transform','filter','clipPath'];
  const start = performance.now();
  const id = setInterval(() => {
    const s = getComputedStyle(el);
    const frame = { t: performance.now() - start };
    props.forEach(p => frame[p] = s[p]);
    window.__frames.push(frame);
    if (performance.now() - start > 5000) clearInterval(id);
  }, 16);
  return 'Recording load animation...';
})()"

agent-browser wait 5500
agent-browser eval "(() => JSON.stringify(window.__frames, null, 2))()"
```

## Frame capture — scroll-triggered

```bash
agent-browser eval "
(() => {
  window.__scrollFrames = [];
  const el = document.querySelector('.target');
  if (!el) return 'selector not found';
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      const s = getComputedStyle(e.target);
      window.__scrollFrames.push({
        t: performance.now(), ratio: e.intersectionRatio,
        opacity: s.opacity, transform: s.transform,
      });
    });
  }, { threshold: Array.from({ length: 20 }, (_, i) => i / 19) });
  observer.observe(el);
  return 'Observing scroll...';
})()"

agent-browser scroll down 800
agent-browser wait 2000
agent-browser eval "(() => JSON.stringify(window.__scrollFrames, null, 2))()"
```

## Analyze captured frames

```bash
agent-browser eval "
(() => {
  const frames = window.__frames;
  if (!frames?.length) return 'No frames captured';
  const first = frames[0], last = frames[frames.length - 1];
  const duration = last.t - first.t;
  const changed = {};
  Object.keys(first).forEach(key => {
    if (key === 't') return;
    if (first[key] !== last[key]) changed[key] = { from: first[key], to: last[key] };
  });

  Object.keys(changed).forEach(prop => {
    const numericValues = frames.map(f => parseFloat(f[prop])).filter(v => !isNaN(v));
    if (numericValues.length > 1) {
      const min = numericValues[0], max = numericValues[numericValues.length - 1];
      const range = max - min;
      const sampled = numericValues.filter((_, i) => i % 3 === 0);
      changed[prop].easingCurve = sampled
        .map((v, i) => ({ t: sampled.length > 1 ? i / (sampled.length - 1) : 0, v: range ? (v - min) / range : 0 }));
    }
  });

  return JSON.stringify({ duration: Math.round(duration) + 'ms', changedProperties: changed }, null, 2);
})()"
```

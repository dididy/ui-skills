# Multi-Point Measurement — Step -1

> **Before writing ANY implementation code, measure ALL animated properties at 11 progress points (0%, 10%, 20%, …, 100%) on the original site. This is non-negotiable.**

## Why

Real animations use multi-phase timing (e.g., fast 0→50%, slow 50→100%), stepped opacity, or different properties animating in different phases. A linear interpolation between start and end is almost always wrong. The multi-point measurement catches this.

## Hover/CSS transitions

Record computed style values at ~16ms intervals during the transition, then sample 11 equally-spaced points:

```bash
agent-browser open https://target-site.com
agent-browser set viewport 1440 900

# 1. Set up recorder — adapt '.target' and props to your animation
agent-browser eval "
(() => {
  window.__frames = [];
  const el = document.querySelector('.target');
  if (!el) return 'selector not found';
  const props = ['opacity','transform','filter','clipPath','boxShadow','width','height','backgroundColor'];
  const start = performance.now();
  const id = setInterval(() => {
    const s = getComputedStyle(el);
    const frame = { t: Math.round(performance.now() - start) };
    props.forEach(p => frame[p] = s[p]);
    window.__frames.push(frame);
    if (performance.now() - start > 2000) clearInterval(id);
  }, 16);
  return 'Recording...';
})()"

# 2. Trigger hover
agent-browser hover .target
agent-browser wait 2500

# 3. Sample 11 equally-spaced points from the recorded frames
agent-browser eval "
(() => {
  const frames = window.__frames;
  if (!frames?.length) return 'No frames captured';
  const sampled = [];
  for (let i = 0; i <= 10; i++) {
    const idx = Math.min(Math.round(i * (frames.length - 1) / 10), frames.length - 1);
    sampled.push(frames[idx]);
  }
  return JSON.stringify(sampled, null, 2);
})()"
```

Save to `tmp/ref/<effect-name>/measurements.json`.

## Page-load animations

Same approach, but start recording immediately after page open:

```bash
agent-browser open https://target-site.com

# Start recording right away — page-load animations fire on load
agent-browser eval "
(() => {
  window.__frames = [];
  const el = document.querySelector('.target');
  if (!el) return 'selector not found';
  const props = ['opacity','transform','filter','clipPath'];
  const start = performance.now();
  const id = setInterval(() => {
    const s = getComputedStyle(el);
    const frame = { t: Math.round(performance.now() - start) };
    props.forEach(p => frame[p] = s[p]);
    window.__frames.push(frame);
    if (performance.now() - start > 3000) clearInterval(id);
  }, 16);
  return 'Recording load animation...';
})()"

agent-browser wait 3500

# Sample 11 points
agent-browser eval "
(() => {
  const frames = window.__frames;
  if (!frames?.length) return 'No frames captured';
  const sampled = [];
  for (let i = 0; i <= 10; i++) {
    const idx = Math.min(Math.round(i * (frames.length - 1) / 10), frames.length - 1);
    sampled.push(frames[idx]);
  }
  return JSON.stringify(sampled, null, 2);
})()"
```

Save to `tmp/ref/<effect-name>/measurements.json`.

## Scroll-driven animations

> **Adapt all selectors below to your target.** Replace `<section-selector>` and the animated element selectors with the actual selectors identified during extraction.

```bash
agent-browser open https://target-site.com
agent-browser set viewport 1440 900

# Scroll to 11 positions (0%–100%) and measure animated properties at each
agent-browser eval "
(() => {
  // Replace with the scroll section that contains the animation
  const section = document.querySelector('<section-selector>');
  if (!section) return JSON.stringify({ error: 'section not found' });
  const rect = section.getBoundingClientRect();
  const sectionTop = rect.top + window.scrollY;
  const scrollRange = rect.height - window.innerHeight;

  // Replace with the actual animated elements in your target
  const targets = [
    { selector: '<animated-el-1>', label: 'el1' },
    { selector: '<animated-el-2>', label: 'el2' },
  ];
  const props = ['opacity', 'transform', 'filter', 'clipPath', 'width', 'height'];

  const results = [];
  for (let pct = 0; pct <= 100; pct += 10) {
    window.scrollTo(0, sectionTop + scrollRange * pct / 100);
    document.body.getBoundingClientRect(); // force layout

    const measurements = {};
    targets.forEach(({ selector, label }) => {
      const el = document.querySelector(selector);
      if (!el) return;
      const s = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      measurements[label] = {};
      props.forEach(p => measurements[label][p] = s[p]);
      measurements[label]._bounds = {
        w: Math.round(r.width * 10) / 10,
        h: Math.round(r.height * 10) / 10,
      };
    });

    results.push({ pct, ...measurements });
  }
  return JSON.stringify(results, null, 2);
})()"
```

## What to look for

- **Non-linear curves**: Values that don't decrease/increase uniformly → apply matching curve, not linear lerp
- **Phase boundaries**: Properties that stay constant for some range then change → multi-phase animation
- **Different phase timings per property**: e.g., wrapper shrinks 0→50%, opacity changes 50→100%, scales change 50→100% → each needs its own phase logic
- **Stepped values**: Property jumps from 0 to non-zero at a specific point → use conditional, not continuous interpolation

Save the raw measurement data to `tmp/ref/<effect-name>/measurements.json` before proceeding.

**GATE: `measurements.json` must exist and contain 11 data points before writing implementation code. If missing → repeat Step -1.**

---
name: ui-reverse-engineering
description: Reverse-engineer any website into production-ready React + Tailwind code. Triggers on "clone this site", "copy this UI", "replicate this page", "turn this into code", "reverse-engineer this", "make it look like X". Extracts DOM structure, computed CSS, JS interactions, responsive breakpoints, and animations from a live URL — then generates a working component. Use transition-reverse-engineering sub-skill for precise animation extraction.
allowed-tools: Bash(agent-browser:open|close|screenshot|snapshot|eval|wait|hover|click|scroll|record|set),Bash(curl:--max-filesize|--max-time|--fail|--location|--compressed|-s|-o),Bash(grep:-E|-e|-c|--include)
---

# UI Reverse Engineering

Reverse-engineer a live website into a **React + Tailwind** component.

**Core principle:** Extract actual values from the live site. Never guess at layout, colors, spacing, timing, or easing.

## Dependencies

**`agent-browser`** is required for all browser automation.

```bash
brew install agent-browser        # macOS
npm install -g agent-browser      # any platform

agent-browser --version           # verify
```

## Process Overview

```
Input (URL / screenshot / video)
  ↓
1. Open & Snapshot        — DOM tree, screenshots
  ↓
2. Extract Structure      — HTML hierarchy, component boundaries
  ↓
3. Extract Styles         — computed CSS, colors, typography, spacing
  ↓
4. Extract Responsive     — breakpoint-by-breakpoint styles
  ↓
5. Detect Interactions    — hover/click/scroll, transitions, animations
     ↓ complex animation?
     → invoke transition-reverse-engineering skill, then resume at Step 7
  ↓
6. Analyze JS (if needed) — bundle grep for complex interactions
  ↓
7. Generate Component     — React + Tailwind
  ↓
8. Visual Verification    — screenshot comparison, iterate until matched
```

## Input Modes

| Mode | When to use | How |
|------|-------------|-----|
| **URL** (primary) | Live site — gets actual CSS/DOM/JS | `agent-browser open <url>` |
| **Screenshot** | Design mockup, Figma export, inaccessible site | Pass image to Claude Vision for layout analysis |
| **Video / screen recording** | Captures interactions and state changes | Extract frames, analyze per-frame state transitions |
| **Multiple screenshots** | Different pages or breakpoints | Treat as separate views; link or scaffold together |

**Screenshot / Video fallback prompt:**
> "Analyze this [screenshot/video] and extract: layout structure, colors (exact hex), typography (size/weight/family), spacing, and any visible interactions or state changes. Output as structured JSON matching the `extracted.json` format."

---

## Step 1: Open & Snapshot

```bash
agent-browser open https://target-site.com
agent-browser screenshot tmp/ref/<component>/full.png
agent-browser snapshot
```

**If site shows blank or bot detection:**

> **Legal notice:** Only use on sites you own or have explicit written permission to access. Automated access may violate the target site's Terms of Service and applicable law (e.g. CFAA). Do not use on sites you do not control.

```bash
agent-browser close
agent-browser --headed open "https://target-site.com"
```

---

## Step 2: Extract DOM Structure

Identify the target component boundary first, then extract its hierarchy.

```bash
agent-browser eval "
(() => {
  const target = document.querySelector('.target-selector');
  if (!target) return JSON.stringify({ error: 'selector not found' });
  const extract = (el, depth = 0) => {
    if (depth > 4) return null;
    const s = getComputedStyle(el);
    return {
      tag: el.tagName.toLowerCase(),
      class: el.className?.toString().slice(0, 80),
      display: s.display,
      position: s.position,
      children: Array.from(el.children).map(c => extract(c, depth + 1)).filter(Boolean),
    };
  };
  return JSON.stringify(extract(target), null, 2);
})()
"
```

**Save output to** `tmp/ref/<component>/structure.json`

---

## Step 3: Extract Computed Styles

### Key element styles

```bash
agent-browser eval "
(() => {
  const selectors = ['.target', '.target h1', '.target p', '.target button'];
  const props = [
    'display', 'flexDirection', 'alignItems', 'justifyContent', 'gap',
    'gridTemplateColumns', 'gridTemplateRows',
    'width', 'height', 'maxWidth', 'minHeight',
    'padding', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
    'margin', 'marginTop', 'marginRight', 'marginBottom', 'marginLeft',
    'fontSize', 'fontWeight', 'fontFamily', 'lineHeight', 'letterSpacing',
    'color', 'backgroundColor', 'backgroundImage',
    'borderRadius', 'border', 'boxShadow',
    'opacity', 'transform', 'filter',
    'position', 'top', 'right', 'bottom', 'left', 'zIndex',
  ];
  const result = {};
  selectors.forEach(sel => {
    const el = document.querySelector(sel);
    if (!el) return;
    const s = getComputedStyle(el);
    result[sel] = {};
    props.forEach(p => {
      const v = s[p];
      if (v && v !== 'none' && v !== 'normal' && v !== 'auto' && v !== '0px') {
        result[sel][p] = v;
      }
    });
  });
  return JSON.stringify(result, null, 2);
})()
"
```

### Extract CSS custom properties (design tokens)

```bash
agent-browser eval "
(() => {
  const vars = {};
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule.selectorText === ':root') {
          const matches = rule.cssText.matchAll(/--([\w-]+):\s*([^;]+)/g);
          for (const m of matches) vars['--' + m[1]] = m[2].trim();
        }
      }
    } catch(e) {}
  }
  return JSON.stringify(vars, null, 2);
})()
"
```

**Save output to** `tmp/ref/<component>/styles.json`

---

## Step 4: Extract Responsive Styles

Extract actual breakpoints from CSS first, then capture at each:

```bash
agent-browser eval "
(() => {
  const breakpoints = [];
  for (const sheet of document.styleSheets) {
    try {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSMediaRule) breakpoints.push(rule.conditionText);
      }
    } catch(e) {}
  }
  return JSON.stringify([...new Set(breakpoints)], null, 2);
})()
"
```

Capture styles and screenshots at each breakpoint:

```bash
# Mobile (375px)
agent-browser set viewport 375 812
agent-browser screenshot tmp/ref/<component>/mobile.png
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({ viewport: window.innerWidth, display: s.display, flexDirection: s.flexDirection, fontSize: s.fontSize, padding: s.padding, width: s.width });
})()
"

# Tablet (768px)
agent-browser set viewport 768 1024
agent-browser screenshot tmp/ref/<component>/tablet.png
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({ viewport: window.innerWidth, display: s.display, flexDirection: s.flexDirection, fontSize: s.fontSize, padding: s.padding, width: s.width });
})()
"

# Desktop (1440px)
agent-browser set viewport 1440 900
agent-browser screenshot tmp/ref/<component>/desktop.png
agent-browser eval "
(() => {
  const el = document.querySelector('.target');
  if (!el) return JSON.stringify({ error: 'selector not found' });
  const s = getComputedStyle(el);
  return JSON.stringify({ viewport: window.innerWidth, display: s.display, flexDirection: s.flexDirection, fontSize: s.fontSize, padding: s.padding, width: s.width });
})()
"
```

---

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
            selector: el.tagName + (el.className ? '.' + el.className.toString().trim().split(' ')[0] : ''),
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
agent-browser eval "(() => JSON.stringify(window.__scrollTransitions, null, 2))()"
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

# Download relevant chunk (replace <bundle-url> with actual URL from above)
mkdir -p tmp/ref/<component>/bundles
curl -s --max-time 30 --max-filesize 10485760 --fail --location \
  -o tmp/ref/<component>/bundles/main.js \
  -- "<bundle-url>" || { echo "Failed to download bundle" >&2; exit 1; }

# Find interaction logic
grep -E 'addEventListener|onClick|onMouseEnter|useEffect|motion\.|animate\(' \
  tmp/ref/<component>/bundles/main.js | head -40
```

---

## Step 7: Generate Component

### Input checklist before generating

- [ ] `structure.json` — DOM hierarchy
- [ ] `styles.json` — computed styles per element
- [ ] Breakpoint styles (mobile / tablet / desktop)
- [ ] Interaction delta (hover/click states + transition values)
- [ ] Keyframes or `extracted.json` from transition-reverse-engineering (if any)

### Generation prompt

Use extracted values directly — no guessing:

```
Generate a React + Tailwind component based on these extracted values:

Structure: [structure.json content]
Styles: [styles.json content]
Responsive: mobile={...} tablet={...} desktop={...}
Interactions: hover delta={...}, transition="..."
Keyframes / animations: [extracted.json or keyframes if any]

Rules:
- Use Tailwind utility classes, not inline styles
- Use CSS variables for design tokens
- Use the EXACT text from the original (copy-paste, do not paraphrase)
- Preserve exact colors, spacing, font sizes from extracted values
- Implement hover states with Tailwind group/peer or CSS variables
- Implement animations with Tailwind animate-* or @keyframes in globals.css
- Make interactions FUNCTIONAL — do not stub click/hover handlers
- For images: use descriptive placeholder if original is inaccessible
- If functionality requires backend data, mock it inline
- Component must be self-contained (no external data dependencies)
```

### Iteration (update, not rewrite)

When refining after visual verification, make **targeted edits** — do not regenerate the entire component. Identify the specific mismatched property and fix only that.

---

## Step 8: Visual Verification Loop

> **Security note:** Screenshots and DOM snapshots may contain sensitive data visible on the page (auth tokens in DOM attributes, form inputs, user info). Clean up `tmp/ref/` after extraction: `rm -rf tmp/ref/<component>`

**Reference recordings are captured ONCE from the original site. Never re-visit the original site after initial capture.**

### Dependencies

```bash
ffmpeg -version   # required for frame extraction
# macOS: brew install ffmpeg
```

### Shared scroll sequence (use identically in Phase A and B)

```bash
# Slow scroll through full page
agent-browser eval "
(() => {
  const h = document.body.scrollHeight;
  let pos = 0;
  const step = () => {
    pos += 120;
    window.scrollTo(0, pos);
    if (pos < h) setTimeout(step, 80);
  };
  step();
})()"
agent-browser wait 4000
```

### Phase A: Record Reference (ONCE)

```bash
mkdir -p tmp/ref/<component>/frames/{ref,impl}
mkdir -p tmp/ref/<component>/responsive

agent-browser open https://target-site.com
agent-browser set viewport 1440 900
agent-browser record start tmp/ref/<component>/ref.webm

# 1. Static pause
agent-browser wait 1000

# 2. Scroll (use shared sequence above)

# 3. Hover interactive elements
agent-browser eval "window.scrollTo(0, 0)"
agent-browser wait 500
agent-browser eval "
(() => {
  const els = Array.from(document.querySelectorAll('a, button, [role=button], .card, nav a'));
  return JSON.stringify(els.slice(0, 10).map((el, i) => ({
    i,
    tag: el.tagName,
    text: el.textContent?.trim().slice(0, 30),
    class: el.className?.toString().trim().split(' ')[0],
  })));
})()"
# Fill in selectors from output above, then hover each:
agent-browser hover <selector-1>
agent-browser wait 600
agent-browser hover <selector-2>
agent-browser wait 600

agent-browser record stop

# 4. Responsive screenshots (separate — viewport changes can't be mid-session)
agent-browser set viewport 375 812
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/ref-mobile.png
agent-browser set viewport 768 1024
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/ref-tablet.png
agent-browser set viewport 1440 900
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/ref-desktop.png

# 5. Extract frames
ffmpeg -i tmp/ref/<component>/ref.webm -vf fps=2 tmp/ref/<component>/frames/ref/frame-%04d.png -y
```

### Phase B: Record Implementation (per iteration)

```bash
agent-browser open http://localhost:3000
agent-browser set viewport 1440 900
agent-browser record start tmp/ref/<component>/impl.webm

# Same sequence as Phase A: static pause → scroll → hover
agent-browser wait 1000

# Scroll (use shared sequence above)

agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser wait 500
agent-browser hover <selector-1>
agent-browser wait 600
agent-browser hover <selector-2>
agent-browser wait 600

agent-browser record stop

# Responsive screenshots
agent-browser set viewport 375 812
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/impl-mobile.png
agent-browser set viewport 768 1024
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/impl-tablet.png
agent-browser set viewport 1440 900
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser screenshot tmp/ref/<component>/responsive/impl-desktop.png

# Extract frames
ffmpeg -i tmp/ref/<component>/impl.webm -vf fps=2 tmp/ref/<component>/frames/impl/frame-%04d.png -y
```

### Phase C: Compare & Fix

Read corresponding ref and impl frames side-by-side using the Read tool. Same frame number = same point in the interaction sequence.

```
| Frame | Moment                     | Ref                        | Impl                        | Match? | Issue |
|-------|----------------------------|----------------------------|-----------------------------|--------|-------|
| 0001  | Static (top)               | frames/ref/frame-0001.png  | frames/impl/frame-0001.png  | ✅/❌  |       |
| 0003  | Scroll 25%                 | frames/ref/frame-0003.png  | frames/impl/frame-0003.png  | ✅/❌  |       |
| 0005  | Scroll 50% (mid-transition)| frames/ref/frame-0005.png  | frames/impl/frame-0005.png  | ✅/❌  |       |
| 0007  | Scroll 75%                 | frames/ref/frame-0007.png  | frames/impl/frame-0007.png  | ✅/❌  |       |
| 0009  | Scroll 100%                | frames/ref/frame-0009.png  | frames/impl/frame-0009.png  | ✅/❌  |       |
| 0011  | Hover: element 1           | frames/ref/frame-0011.png  | frames/impl/frame-0011.png  | ✅/❌  |       |
| 0013  | Hover: element 2           | frames/ref/frame-0013.png  | frames/impl/frame-0013.png  | ✅/❌  |       |
| —     | Mobile                     | responsive/ref-mobile.png  | responsive/impl-mobile.png  | ✅/❌  |       |
| —     | Tablet                     | responsive/ref-tablet.png  | responsive/impl-tablet.png  | ✅/❌  |       |
| —     | Desktop                    | responsive/ref-desktop.png | responsive/impl-desktop.png | ✅/❌  |       |
```

**For each ❌:** identify the exact CSS property → targeted fix → re-run Phase B only → compare affected frames.

**Stop when** all rows are ✅ or after 3 full iterations.

---

## Output

Save extracted data summary to `tmp/ref/<component>/extracted.json`:

```json
{
  "url": "https://target-site.com",
  "component": "HeroSection",
  "breakpoints": {
    "mobile": 375,
    "tablet": 768,
    "desktop": 1440
  },
  "tokens": {
    "colors": {},
    "spacing": {},
    "typography": {}
  },
  "interactions": {
    "hover": {},
    "scroll": [],
    "animations": []
  }
}
```

---

## Quick Reference

```bash
agent-browser open <url>                    # Navigate
agent-browser snapshot                      # Accessibility tree
agent-browser screenshot [path]             # Capture
agent-browser set viewport <w> <h>          # Resize viewport
agent-browser hover <selector>              # Trigger hover
agent-browser click <selector>              # Trigger click
agent-browser scroll <dir> [px]             # Scroll
agent-browser eval "<iife>"                 # Execute JS — must be IIFE: (() => { ... })()
agent-browser wait <sel|ms>                 # Wait for element or time
agent-browser close                         # Kill session
```

## Sub-skills

- **`transition-reverse-engineering`** — precise animation/transition extraction (WAAPI scrubbing, canvas/WebGL, character stagger, frame-by-frame comparison)

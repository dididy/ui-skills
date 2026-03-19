# DOM Extraction — Steps 1 & 2

> All `agent-browser eval` calls must use IIFE: `(() => { ... })()` — no top-level return.

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

## Step 2: Extract DOM Structure

Identify the target component boundary first, then extract its hierarchy.

```bash
agent-browser eval "
(() => {
  const target = document.querySelector('.target-selector');
  if (!target) return JSON.stringify({ error: 'selector not found' });
  // depth limit: increase to 6-8 for deep component trees (shadcn, MUI, etc.)
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

# Visual Verification — Step 8

> **Security note:** Screenshots and DOM snapshots may contain sensitive data visible on the page (auth tokens in DOM attributes, form inputs, user info). Clean up `tmp/ref/` after extraction: `rm -rf tmp/ref/<component>`

**Reference recordings are captured ONCE from the original site. Never re-visit the original site after initial capture.**

## Dependencies

```bash
ffmpeg -version   # required for frame extraction
# macOS: brew install ffmpeg
```

## Shared scroll sequence (use identically in Phase A and B)

```bash
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

## Phase A: Record Reference (ONCE)

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
agent-browser eval "(() => window.scrollTo(0, 0))()"
agent-browser wait 500
agent-browser eval "
(() => {
  const els = Array.from(document.querySelectorAll('a, button, [role=button], .card, nav a'));
  return JSON.stringify(els.slice(0, 10).map((el, i) => ({
    i,
    tag: el.tagName,
    text: el.textContent?.trim().slice(0, 30),
    class: el.className?.toString().trim().split(' ')[0].replace(/[^a-zA-Z0-9_-]/g, ''),
  })));
})()"
# Fill in selectors from output above, then hover each:
agent-browser hover <selector-1>
agent-browser wait 600
agent-browser hover <selector-2>
agent-browser wait 600

agent-browser record stop

# 4. Responsive screenshots — open a fresh session so viewport change doesn't affect the recording
# Use breakpoints extracted in style-extraction.md Step 4.
# Default fallback: 375/812, 768/1024, 1440/900
agent-browser open https://target-site.com
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

## Phase B: Record Implementation (per iteration)

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

# Responsive screenshots — open a fresh session (same reason as Phase A)
# Change <port> if your dev server runs on a different port (e.g. 3001, 4173, 5173)
agent-browser open http://localhost:3000
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

## Phase C: Compare & Fix

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

**For each ❌:**
1. Write one sentence naming the root cause before touching any code: _"The gap exists because X"_
2. If you cannot name it, run `agent-browser eval` to inspect computed styles at that moment
3. Targeted fix → re-run Phase B only → compare affected frames
4. If the same fix has been tried twice without result, the diagnosis was wrong — re-instrument

**Stop when** all rows are ✅ or after 3 full iterations.

**Before declaring done — entry point check:**
```bash
# Confirm global CSS is actually imported in the app entry file
# React/Vite: src/main.tsx or src/index.tsx
# Next.js: src/pages/_app.tsx or src/app/layout.tsx
# Plain HTML: index.html (look for <link rel="stylesheet">)
grep -r "import.*\.css\|import.*global" src/main.tsx src/index.tsx src/pages/_app.tsx src/app/layout.tsx 2>/dev/null \
  || grep -r "stylesheet" index.html 2>/dev/null \
  || echo "WARNING: no CSS entry point import found — check your framework's entry file"
```
Missing this is a silent failure: styles exist but have no effect.

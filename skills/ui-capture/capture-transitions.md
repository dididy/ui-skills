# ui-capture — Transition Capture

Capture each detected region type. Use `regions.json` from detection.md as input.

## Step 2B: Scroll transitions

For each scroll region:

```bash
agent-browser eval "(() => window.scrollTo(0, <from - 200>))()"
agent-browser wait 500
agent-browser record start tmp/ref/capture/transitions/ref/<name>.webm

agent-browser eval "(() => {
  let pos = <from - 200>;
  const target = <to + 200>;
  const step = () => {
    pos += 60;
    window.scrollTo(0, pos);
    if (pos < target) setTimeout(step, 50);
  };
  step();
})()"
agent-browser wait <calculated-duration>

agent-browser wait 500
agent-browser record stop
```

## Step 2C: Hover transitions

For each hover element:

```bash
agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({ block: 'center' }); })()"
agent-browser wait 500

agent-browser record start tmp/ref/capture/transitions/ref/hover-<name>.webm

# Before hover — static 1s
agent-browser wait 1000

# Hover in
agent-browser hover <selector>
agent-browser wait 1500

# Hover out
agent-browser eval "(() => { document.elementFromPoint(0, 0).dispatchEvent(new MouseEvent('mouseover')); })()"
agent-browser wait 1000

agent-browser record stop
```

## Step 2D: Mousemove / cursor-reactive transitions

Two captures per element: pattern videos + 10×10 matrix screenshots.

### Pattern movement videos

```bash
agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({ block: 'center' }); })()"
agent-browser wait 500

agent-browser record start tmp/ref/capture/transitions/ref/mousemove-<name>.webm

# Left-to-right sweep (20 steps)
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  const r = el.getBoundingClientRect();
  let i = 0;
  const step = () => {
    const x = r.left + (r.width * i / 19);
    const y = r.top + r.height / 2;
    el.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y, bubbles: true }));
    i++;
    if (i < 20) setTimeout(step, 150);
  };
  step();
})()"
agent-browser wait 3500

# Diagonal (top-left to bottom-right)
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  const r = el.getBoundingClientRect();
  let i = 0;
  const step = () => {
    const x = r.left + (r.width * i / 19);
    const y = r.top + (r.height * i / 19);
    el.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y, bubbles: true }));
    i++;
    if (i < 20) setTimeout(step, 150);
  };
  step();
})()"
agent-browser wait 3500

# Circular
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  const r = el.getBoundingClientRect();
  const cx = r.left + r.width / 2;
  const cy = r.top + r.height / 2;
  const rx = r.width * 0.4;
  const ry = r.height * 0.4;
  let i = 0;
  const step = () => {
    const angle = (2 * Math.PI * i) / 30;
    el.dispatchEvent(new MouseEvent('mousemove', { clientX: cx + rx * Math.cos(angle), clientY: cy + ry * Math.sin(angle), bubbles: true }));
    i++;
    if (i < 30) setTimeout(step, 120);
  };
  step();
})()"
agent-browser wait 4000

agent-browser record stop
```

### 10×10 matrix screenshots

```bash
mkdir -p tmp/ref/capture/matrix/ref/<name>
```

For row 0..9, col 0..9:

```bash
agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  const r = el.getBoundingClientRect();
  const x = r.left + r.width * (<col> + 0.5) / 10;
  const y = r.top + r.height * (<row> + 0.5) / 10;
  el.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y, bubbles: true }));
})()"
agent-browser wait 200
agent-browser screenshot tmp/ref/capture/matrix/ref/<name>/r<row>c<col>.png
```

100 screenshots total per element.

## Step 2E: Auto-timer transitions

```bash
agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({ block: 'center' }); })()"
agent-browser wait 500

agent-browser record start tmp/ref/capture/transitions/ref/timer-<name>.webm
agent-browser wait <interval_ms * 3>
agent-browser record stop
```

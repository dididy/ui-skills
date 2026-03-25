# ui-capture — Transition Capture

Capture each region from `regions.json`. Apply trigger type to choose the correct activation method.

## Critical: `record start` behavior

**`agent-browser record start` always creates a fresh browser context** — it navigates to the URL from scratch and resets scroll position to 0, regardless of where the current session is. This means:

- Pre-scrolling before `record start` has NO effect on the recording
- Any `eval` scroll commands issued AFTER `record start` DO work, but only appear in the recording after a delay while the page reloads (~3-5s)
- The recording viewport may differ from the regular session viewport — always call `agent-browser set viewport 1440 900` after `record start`

**Correct pattern for deep-page elements:**
```bash
agent-browser record start <path>.webm   # fresh context, page at y=0
agent-browser set viewport 1440 900
agent-browser wait 3000                  # wait for page to load in recording context
agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({block:'start'}); return window.scrollY; })()"
agent-browser wait 1000                  # wait for scroll to settle in recording
# verify with screenshot before proceeding
agent-browser screenshot /tmp/verify.png
# NOW the recording shows the correct position
```

**Blank start crop is always needed:** The first ~1-4s of every webm will show either blank or wrong state. After stopping, crop with:
```bash
# Find first content frame (stdev > 8 = has content)
python3 -c "
import subprocess, re
src = '<file>.webm'
for t in [x * 0.1 for x in range(0, 80)]:
    r = subprocess.run(['ffmpeg','-ss',str(t),'-i',src,'-vframes','1','-filter:v','showinfo','-f','null','-'], capture_output=True, text=True)
    m = re.search(r'stdev:(\d+\.\d+)', r.stderr)
    if m and float(m.group(1)) > 8.0:
        print(f'crop from: {t}s'); break
"
# Then crop:
ffmpeg -y -ss <crop_t> -i <file>.webm -c:v libx264 -preset fast -crf 23 -an <file>.mp4
```

If stdev detection returns nothing (white-bg pages), extract frames manually and inspect:
```bash
ffmpeg -y -ss 2.0 -i <file>.webm -vframes 1 -update 1 /tmp/frame.png
```
Read the frame image to determine correct crop point.

---

## Before every recording: Fresh state protocol

**Always** ensure clean state before hitting record:
1. Start recording first: `agent-browser record start <path>.webm`
2. Set viewport: `agent-browser set viewport 1440 900`
3. Wait for page load: `agent-browser wait 3000`
4. Scroll to target section via eval
5. Wait for scroll to settle: `agent-browser wait 1000`
6. Take a screenshot to verify the recording context shows correct content
7. Proceed with interaction/sweep
8. After stopping: crop blank start with ffmpeg (see above)

---

## Step 2B: Scroll transitions

```bash
agent-browser record start tmp/ref/capture/transitions/ref/<name>.webm
agent-browser set viewport 1440 900
agent-browser wait 3000

# Scroll to just above the transition range
agent-browser eval "(() => window.scrollTo(0, <from - 300>))()"
agent-browser wait 800

# Slow smooth scroll through the full transition range
agent-browser eval "(() => {
  let pos = <from - 300>;
  const target = <to + 300>;
  const step = () => {
    pos += 30;          // slow: 30px per tick
    window.scrollTo(0, pos);
    if (pos < target) setTimeout(step, 50);  // ~600px/s
  };
  step();
})()"

# Wait for scroll to finish: ((to - from + 600) / 30) * 50ms
agent-browser wait <duration_ms>
agent-browser wait 500
agent-browser record stop
```

**Validate:** `ffprobe -v quiet -show_entries format=duration -of csv=p=0 <file>` — must be > 2s and < 30s. If 0s or > 60s, re-record.

---

## Step 2C: Hover / interactive transitions

**Choose activation method based on `triggerType`:**

### css-hover

```bash
agent-browser record start tmp/ref/capture/transitions/ref/hover-<name>.webm
agent-browser set viewport 1440 900
agent-browser wait 3000

agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({block:'center'}); return window.scrollY; })()"
agent-browser wait 1000  # show idle state

# CDP-level hover (triggers CSS :hover)
agent-browser hover <unique-selector>
agent-browser wait <transitionDuration * 2>  # hold in hover state

# Move away
agent-browser hover body
agent-browser wait <transitionDuration>  # show return to idle

agent-browser record stop
```

**Note:** Use a selector that matches exactly ONE element. If `agent-browser hover` reports "matched N elements", use `:nth-child(1)` or a parent > child path to narrow it.

### js-class (e.g. flip card toggled by JS class)

```bash
agent-browser record start tmp/ref/capture/transitions/ref/hover-<name>.webm
agent-browser set viewport 1440 900
agent-browser wait 3000

agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({block:'center'}); return window.scrollY; })()"
agent-browser wait 1000  # idle state visible

# Add trigger class
agent-browser eval "(() => {
  document.querySelector('<selector>').classList.add('<triggerClass>');
})()"
agent-browser wait <transitionDuration * 2>

# Remove trigger class
agent-browser eval "(() => {
  document.querySelector('<selector>').classList.remove('<triggerClass>');
})()"
agent-browser wait <transitionDuration>

agent-browser record stop
```

### intersection (scroll-triggered entry animation)

```bash
agent-browser record start tmp/ref/capture/transitions/ref/<name>.webm
agent-browser set viewport 1440 900
agent-browser wait 3000

# Reset any in-view state so animation plays fresh
agent-browser eval "(() => {
  document.querySelectorAll('[data-in-view]').forEach(el => el.dataset.inView = 'false');
  document.querySelectorAll('.in-view, .is-visible, .animate').forEach(el => {
    el.classList.remove('in-view', 'is-visible', 'animate');
  });
})()"
agent-browser wait 300

# Scroll to just above the section (NOT from y=0 — that makes the scroll too long)
agent-browser eval "(() => window.scrollTo(0, <y - 500>))()"
agent-browser wait 500

# Smooth scroll into view — let IntersectionObserver fire naturally
agent-browser eval "(() => {
  let pos = <y - 500>;
  const target = <y + 300>;
  const step = () => {
    pos += 25;
    window.scrollTo(0, pos);
    if (pos < target) setTimeout(step, 40);
  };
  step();
})()"
agent-browser wait <scroll_duration + transitionDuration * 2>

agent-browser record stop
```

---

## Step 2D: Mousemove / cursor-reactive

**One video only** — no matrix screenshots. Record a continuous path that covers the whole element:

```bash
agent-browser record start tmp/ref/capture/transitions/ref/mousemove-<name>.webm
agent-browser set viewport 1440 900
agent-browser wait 3000

# Scroll to element — use scrollIntoView, check rect.top confirms it's in viewport
agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({block:'start'}); return window.scrollY; })()"
agent-browser wait 1000

# Verify recording shows the element (not blank/wrong page)
agent-browser screenshot /tmp/mousemove-verify.png
# Read the screenshot — if it shows the wrong content, the recording context hasn't caught up.
# In that case: agent-browser wait 2000 and re-verify.

agent-browser eval "(() => {
  const el = document.querySelector('<selector>');
  const r = el.getBoundingClientRect();

  // 10×10 grid raster path: top-left zigzag covering entire element
  const points = [];
  for (let row = 0; row < 10; row++) {
    for (let col = 0; col < 10; col++) {
      // Alternate row direction for raster scan
      const c = row % 2 === 0 ? col : 9 - col;
      points.push({
        x: r.left + r.width * (c + 0.5) / 10,
        y: r.top + r.height * (row + 0.5) / 10
      });
    }
  }

  // Also dispatch to document in case listener is on document/window
  let i = 0;
  const step = () => {
    const p = points[i];
    const evt = new MouseEvent('mousemove', { clientX: p.x, clientY: p.y, bubbles: true });
    el.dispatchEvent(evt);
    document.dispatchEvent(new MouseEvent('mousemove', { clientX: p.x, clientY: p.y, bubbles: true }));
    i++;
    if (i < points.length) setTimeout(step, 120);  // ~8s total for 100 points
  };
  step();
})()"

# 100 points × 120ms = ~12s
agent-browser wait 13000
agent-browser record stop
```

This single video shows the cursor sweeping the full element in a raster pattern — every region covered, movement visible throughout.

---

## Step 2E: Auto-timer transitions

Only record if the element visually changes on its own (no user interaction needed):

```bash
agent-browser record start tmp/ref/capture/transitions/ref/timer-<name>.webm
agent-browser set viewport 1440 900
agent-browser wait 3000

# Scroll to element (AFTER record start — record creates fresh context)
agent-browser eval "(() => { document.querySelector('<selector>').scrollIntoView({block:'center'}); return window.scrollY; })()"
agent-browser wait 1000

# Wait for 2-3 full cycles
agent-browser wait <interval_ms * 3>
agent-browser record stop
```

---

## Validation checklist after each recording

```
□ ffprobe duration > 1s
□ File size > 50KB
□ Read first frame: not blank/white
□ Duration matches expected: hover ~5s, scroll ~6s, mousemove ~13s, timer = interval×3
□ If duration is 0 or > 60s → re-record (recording got stuck or never started)
```

Convert to mp4 for browser compatibility:
```bash
ffmpeg -y -i <file>.webm -c:v libx264 -preset fast -crf 23 -an <file>.mp4
```

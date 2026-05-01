# Diagnosis → Fix: Root Cause Patterns

When a visual mismatch occurs, one of 5 root causes applies. **Identify the category first** — then apply the targeted fix. Random code tweaking without diagnosis wastes 10+ minutes.

---

## How to pick the right category

```
computed-diff shows diff?
  → YES: color/font/weight → Root Cause B (CSS Cascade)
  → YES: display/height/position → Root Cause C (Missing Wrapper) or A (DOM Mismatch)
  → NO: element renders but wrong shape/behavior → Root Cause D (Wrong Element Type)

Animation doesn't animate?
  → Root Cause E (Animation)

Layout looks structurally wrong (items in wrong order / missing container)?
  → Root Cause A (DOM Mismatch)
```

---

## Root Cause A: DOM Mismatch

**Symptoms:** Content present but layout wrong; items in wrong order; class names not matching CSS rules; elements unstyled despite CSS being loaded

**Diagnosis:**
```bash
# 1. Compare display/flexDirection/position
bash "$SCRIPTS/computed-diff.sh" <session> <orig> <impl> ".section" ".section > *" ".section > * > *"

# 2. Verify child order
agent-browser --session <ref> eval "[...document.querySelector('.inner').children].map(c => c.className)"

# 3. Verify wrapper presence
agent-browser --session <ref> eval "document.querySelector('.section').children[0].className"

# 4. Check inner class namespace (Swiper, carousels)
agent-browser --session <ref> eval "document.querySelector('.swiper-slide').innerHTML"
```

**Common patterns:**
- Missing `.main_inner` wrapper → CSS margin/padding on wrapper collapses, content has no breathing room
- CTA items in wrong DOM order (title→mascot vs mascot→title) — DOM order ≠ visual order when CSS positions elements
- Swiper slide inner class namespace mismatch (`ReviewList_*` vs `ReviewItem_*`) → all inner elements unstyled even though CSS is loaded
- Portal elements in wrong container (modal, dropdown outside target)

**Fix:** Always `agent-browser eval "document.querySelector('.target').outerHTML"` on ref BEFORE writing any JSX. Screenshot ref for structural reference. Never infer DOM order from screenshots.

---

## Root Cause B: CSS Cascade Conflict

**Symptoms:** CSS rule present in file, property not applied; `computed-diff.sh` shows different value despite correct class name; color/weight/font wrong

**Diagnosis:**
```bash
# 1. Check computed value on both — the diff is the fix target
bash "$SCRIPTS/computed-diff.sh" <session> <orig> <impl> ".footer_link" ".btn_lang" "a" "button"

# 2. Grep original CSS for the property
grep -E "\.footer_link|\.btn_lang" tmp/ref/<c>/css/app.css

# 3. Enumerate ALL host CSS resets (embedded projects)
grep -E "^button\b|^a\b|^button,|^a,|^select\b|^img\b|^body\b" /path/to/host.css
```

**Common patterns:**
- Host CSS `a { color: #1a1d24 }` beats `.footer_link { color: #fff }` — host rule in later stylesheet wins specificity
- Button reset missing `font-weight` when host rule is `button,a { font-weight: 400 }` — `a.Cls` not overridden
- `body { line-height }` not scoped to `[data-project]` in embedded project
- `img { display: block }` from host makes `text-align: center` ineffective on parent → fix: `margin: 0 auto` on `<img>`
- `@theme { --font-sans }` in separate CSS file silently ignored

**Fix:** Run `grep -E "^button\b|^a\b|^select\b|^img\b|body\b" host.css`. Inventory ALL resets. Add all overrides in one block in layout.tsx — not reactively one by one. One visible cascade conflict = there are more.

---

## Root Cause C: Missing Wrapper or Layout Container

**Symptoms:** Content present and styled, but spacing/alignment wrong; section height collapsed; shadow clipped; overflow unexpected

**Diagnosis:**
```bash
# 1. Is first child a wrapper?
agent-browser --session <ref> eval \
  "document.querySelector('.section').children[0].tagName + ' ' + document.querySelector('.section').children[0].className"

# 2. What does the wrapper's CSS define?
grep -A10 "\.main_inner\|\.wrapper\|\.inner" tmp/ref/<c>/css/app.css | head -20

# 3. Compare section heights ref vs impl
bash "$SCRIPTS/computed-diff.sh" <session> <orig> <impl> ".section" ".section > div"
```

**Common patterns:**
- `.main_inner` wrapper missing → inner content touches section edges directly; heading appears inside wrong visual container
- Overflow container missing → `box-shadow` clipped by `overflow: hidden` on parent (fix: `padding-bottom` on wrapper)
- Sticky sub-nav container wrong → `position: sticky` needs a direct scroll parent with `overflow: auto/scroll`
- Grid cell wrapper missing → images in `.card` without inner `<div>` that CSS targets

**Fix:** Never skip the wrapper. Verify structure BEFORE styling. Screenshot ref to see where wrapper boundaries are.

---

## Root Cause D: Wrong Element Type or Interaction Trigger

**Symptoms:** Element renders but doesn't behave right; width wrong; dropdown doesn't open; click/hover doesn't fire; interaction missing

**Diagnosis:**
```bash
# 1. Verify tag name and inner structure
agent-browser --session <ref> eval "document.querySelector('.btn_area').innerHTML"
agent-browser --session <ref> eval "document.querySelector('.btn_lang').tagName"

# 2. Check computed appearance (is it a styled native element?)
agent-browser --session <ref> eval "getComputedStyle(document.querySelector('.btn_lang')).appearance"

# 3. Test if interaction fires
agent-browser --session <impl> eval \
  "document.querySelector('.btn').dispatchEvent(new MouseEvent('mouseenter')); document.querySelector('.btn').getAnimations().length"
```

**Common patterns:**
- `<select>` styled with `appearance: none` + absolute SVG chevron looks identical to `<button>` in screenshots — but has different width, different CSS reset needs, native dropdown behavior
- `<a>` vs `<button>` — host CSS resets differ; override must match BOTH element types when host rule is `button,a {}`
- Hover JS event listener not firing: missing `mouseenter` dispatch; `mouseover` event wrong
- SVG rotation double-applied: CSS already rotates `.slider_prev svg { transform: rotate(180deg) }`, JSX adds another → 360° total (both arrows look identical)

**Fix:** Always verify tag name. Check ref HTML: `agent-browser eval "document.querySelector('.selector').outerHTML"`. Grep CSS for existing transforms before adding inline: `grep "\.slider_prev.*transform\|rotate" *.css`.

---

## Root Cause E: Animation / Transition Not Applied or Wrong Easing

**Symptoms:** Element renders static when it should animate; animation snaps instead of transitions; timing wrong; scroll effect doesn't update

**Diagnosis:**
```bash
# 1. Is CSS transition defined?
agent-browser --session <impl> eval \
  "getComputedStyle(document.querySelector('.target')).transitionDuration + ' ' + getComputedStyle(document.querySelector('.target')).transitionTimingFunction"

# 2. Are WAAPI animations registered?
agent-browser --session <impl> eval "document.querySelector('.target').getAnimations().length"

# 3. What library drives it?
grep -E "gsap|Lenis|ScrollTrigger|requestAnimationFrame|transition" tmp/ref/<c>/bundles/*.js | head -20

# 4. Compare timing
SCRIPTS="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/visual-debug/scripts}"
SCRIPTS="${SCRIPTS:-$(find ~/.claude/skills -name 'ae-compare.sh' -exec dirname {} \; 2>/dev/null | head -1)}"
bash "$SCRIPTS/transition-compare.sh" <orig-url> <impl-url> <session> tmp/ref/<c>
```

**Common patterns:**
- **RAF loop for class-toggle** → CSS `transition: height 1.06s` restarts every frame → snap instead of animate. Fix: use scroll event, not RAF, for class changes
- **Scroll event on smooth-scroll site** → Lenis/Locomotive absorbs scroll events → `addEventListener('scroll')` fires 0 times. Fix: RAF + `getBoundingClientRect()`
- **GSAP baked init styles** (`visibility: hidden`, `opacity: 0`) not reset → element stays invisible forever
- **Double-apply transform** → CSS already rotates, JSX adds another → wrong result
- **`.effect-data` IntersectionObserver missing** → section blank (all `opacity: 0` by CSS default, JS never adds `active` class)
- **Card stack height not pre-fixed** → `height: auto → 64px` not CSS-animatable; must set `item.style.height = item.offsetHeight + 'px'` before scroll handler runs

**Fix:** Check `transition-spec.json` for expected easing + duration. Run `transition-compare.sh`. Rule: **RAF drives transform values** (parallax progress); **scroll events drive class changes** (toggle animations). Never mix.

---

## Root Cause F: Legacy JS Bundle Conflict

**Symptoms:** Animation/scroll behavior broken *and* React component logic looks correct; class-toggle fires immediately instead of after delay (or never fires); no JS errors in console

**Trigger:** `layout.tsx` loads a `*.min.js` / `vendor.js` bundle alongside the React app.

**Diagnosis:**
```bash
# 1. Does the page load a legacy bundle?
grep -rn '\.min\.js\|vendor\.js\|bundle\.js' src/app/layout.tsx

# 2. What globals does the bundle expose? (its init classes / scroll engines)
agent-browser --session <s> eval "
  Object.keys(window).filter(k => /scroll|nav|swiper|lottie|animation|player/i.test(k))
"

# 3. What class selectors does the bundle querySelector?
grep -o "querySelector('[^']*')\|querySelector(\"[^\"]*\")" public/js/*.min.js \
  | grep -oE "['\"][.#][^'\"]+['\"]" | sort -u | head -30

# 4. Does the bundle define page-scoped init objects with hardcoded selectors?
# Look for patterns like: { el: '.page-wrap', mainEl: '.container', containerEl: '.inner' }
grep -o 'el:[[:space:]]*"[^"]*"\|el:[[:space:]]*'"'"'[^'"'"']*'"'"'' public/js/*.min.js | sort -u | head -20
```

**Common patterns:**
- **React component + bundle both manage the same DOM class** → bundle adds `is-active` on `window.load`, React component also adds it after a timeout → double-fire, wrong timing, or race condition. **Fix: remove the React component; let the bundle own it.**
- **Renamed class breaks bundle querySelector** → class renamed to avoid a CSS framework conflict (e.g. `.container` → `.nc-container`) → bundle's `querySelector('.container')` returns `null` → entire page init fails silently; all animations/scroll broken. **Fix: keep the original class, add the override class alongside** (`className="nc-override container"`), then use CSS to neutralize only the conflicting property.
- **Bundle init fails silently** → no console error, no warning; page just doesn't animate. Diagnose: check that the bundle's expected globals are populated after `window.load` (step 2 above).
- **CSS framework utility collides with bundle selector** → class names like `.container`, `.sticky` mean something in both Tailwind and the bundle. Renaming the Tailwind class away breaks the bundle. See `common-selectors.md` → "Tailwind Utility Class Collision Canaries".

**Fix:**
1. If `layout.tsx` loads a bundle: **the bundle owns class-toggle logic**. Do not re-implement scroll/reveal/sticky in React for the same elements.
2. When a CSS framework conflicts with a class the bundle queries: keep the original class, add the override class alongside, override only the conflicting CSS property with `!important`.
3. Rule: **one owner per DOM class**. If the bundle toggles it, React doesn't. If React toggles it, remove it from the bundle scope (or don't load the bundle on that page).

## Root Cause G: Pseudo-element Indicator Not Detected by computed-diff

**Symptoms:** Active tab/nav indicator visually wrong (wrong position, missing, or extra) even though `computedStyle` on the element looks correct. `computed-diff.sh` reports no mismatch.

**Root cause:** `computed-diff.sh` compares `getComputedStyle(el)` only — it does NOT check `::before` / `::after`. Sites often use pseudo-elements for active indicators (underline bars, dots, highlights).

**Diagnosis:**
```bash
# Check ::before and ::after on the suspicious element
agent-browser --session <s> eval "
var el = document.querySelector('[class*=tab_item], [class*=nav_item], [role=tab]');
['::before', '::after'].map(function(pseudo) {
  var s = window.getComputedStyle(el, pseudo);
  return { pseudo: pseudo, content: s.content, display: s.display, h: s.height, bg: s.backgroundColor, position: s.position, bottom: s.bottom, left: s.left, right: s.right, borderRadius: s.borderRadius };
});
"
```

**Common pattern (tab active indicator):**
```
::before {
  content: "";
  display: block;
  position: absolute;
  bottom: 0px;
  left: 5px;
  right: 5px;
  height: 3px;
  background-color: <brand-color>;
  border-radius: 2px;
}
```

**Fix:** In React, implement as a child `<span>` with `position: absolute` matching the pseudo-element's geometry. Ensure the parent has `position: relative`. Use the **measured** `bottom`, `left`, `right`, `height`, `border-radius` values exactly — do not guess or adjust visually.

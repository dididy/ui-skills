# Common Computed-Diff Selector Sets

Ready-to-use selector lists for `computed-diff.sh`.
These are **framework-agnostic** — they work on any site using class-based or semantic HTML.

## Usage

```bash
SCRIPTS="$HOME/Documents/ui-skills/skills/visual-debug/scripts"
bash "$SCRIPTS/computed-diff.sh" <session> <orig-url> <impl-url> \
  $(grep -v '^#' "$HOME/Documents/ui-skills/skills/visual-debug/common-selectors.md" \
    | grep '^  - ' | awk '{print $2}' | head -20)
```

Or paste selector groups directly:

```bash
bash computed-diff.sh my-session https://original.com http://localhost:3000 \
  "h1" "h2" "h3" "h4" \
  "body" "main" \
  "header" "footer" \
  "nav" "ul" "li" \
  "a" "button" "input" "select"
```

---

## Selector Groups

### Typography (headings + body)
Catches: fontWeight resets (Tailwind preflight), fontSize scaling, lineHeight

```
h1  h2  h3  h4  h5  h6
p  span  a  strong  em  label
```

### CSS Framework Reset Canaries
These specific combinations frequently break under Tailwind v3/v4 preflight:

```
h1  h2  h3
img
button  input  select  textarea
```

**Known Tailwind preflight resets that cause mismatches:**
| Element | Property reset | Symptom | Fix |
|---------|---------------|---------|-----|
| `h1–h6` | `font-weight: inherit` | Headings inherit body weight (500) instead of bold (700) | Add `h1,h2,h3,h4,h5,h6 { font-weight: bold }` to global CSS |
| `img` | `display: block; height: auto` | Inline images become block, HTML `height` attr ignored | Use `style={{ height: "Npx" }}` or `.class { display: inline !important; height: Npx !important }` |
| `button` | `background: transparent` | Buttons lose background color | Override explicitly |
| `a` | `color: inherit; text-decoration: inherit` | Links lose color + underline | Override per design |

### Layout Sections
Catches: margin/padding differences, width mismatches, box-sizing issues

```
header  main  footer  nav  aside  section  article
```

### Naver.com Specific
Common mismatches found during pixel-perfect clone work:

```
.notice_area .title
.partner_box .title
.list_corp
.addr
.news_logo
[class*=tab_text]
[class*=shortcut_item]
[class*=search_input]
[class*=content_header]
[class*=content_paging]
[class*=subscription_box]
[class*=media_area]
[class*=link_login]
[class*=weather_box]
[class*=stock_box]
[class*=vibe_box]
[class*=calendar_box]
```

### Navercorp.com Clone Specific
Selectors confirmed useful for navercorp clone (`localhost:3001` vs `navercorp.com`):

```
.header__logo
.header__inner
.nav__link
.main-title
.main-news
.masonry-grid-item
.btn-basic
.main-middle-banner
.footer__lottie
.footer__menu
```

**Known navercorp compound-selector traps** — these require `.navercorp.main` on the wrapper:
```
.navercorp.main .header__logo      → width:292px (desktop hero) → 104px on scroll
.navercorp.main .main-title        → font-size:32px (not 16px)
.navercorp.is-scroll-down.main .header .header__logo  → shrinks logo on scroll
```
Always verify wrapper div has BOTH `navercorp` AND `main` classes on the same element.

### General E-commerce / Portal
```
[class*=header]
[class*=footer]
[class*=nav]
[class*=logo]
[class*=search]
[class*=banner]
[class*=card]
[class*=price]
[class*=btn]
[class*=badge]
```

---

## OS Font Scaling Artifact

If fontSize/lineHeight/width/height all differ by the same ratio (e.g. orig=14.7px impl=14px, ratio=1.05),
this is caused by macOS system text size setting (105%), not a real bug.

Confirm with:
```bash
IGNORE_FONT_SIZE=1 bash computed-diff.sh <session> <orig> <impl> <selectors>
```

If mismatches drop to 0 → it's OS scaling. No fix needed.
If mismatches remain → real CSS differences exist.

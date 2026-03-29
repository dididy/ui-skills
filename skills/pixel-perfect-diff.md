# Pixel-Perfect Diff — Mandatory Numerical Verification

> **이 단계가 "비슷해 보임"과 "픽셀 퍼펙트"를 가른다.**
> 시각 게이트(Phase 1)가 pass/fail 기준이다. 수치 진단(Phase 2)은 항상 실행한다 — Visual Gate를 통과해도 서브픽셀 수준 오차(`font-size: 15px vs 16px`, `letter-spacing` 미세 차이 등)는 픽셀 diff로 잡히지 않기 때문이다.

---

## 흐름

```
Phase 1: Visual Gate (항상 실행)
  — DOM clip screenshot으로 요소 단위 픽셀 비교
  — pass / fail 기록

Phase 2: Numerical Diagnosis (항상 실행 — Phase 1 결과와 무관)
  — getComputedStyle로 모든 속성 수치 비교
  — Visual Gate pass여도 수치 불일치 항목을 보고
  — 수치 불일치 있으면 수정 후 Phase 1 재실행

Gate: Phase 1 all pass AND Phase 2 mismatches = 0
```

---

## Phase 1: Visual Gate

### Step V1: 비교할 요소 목록 정의

`regions.json`의 각 region + 정적 섹션(header, footer, hero)에서 핵심 요소를 선정한다:
- 레이아웃 정의 컨테이너
- 타이포그래피 캐리어 (heading, nav link, label)
- 시각적으로 구별되는 요소 (card, button, image)

각 요소에 대해 캡처할 **상태**도 함께 정의한다:

| triggerType | 탐색 | 검증 |
|---|---|---|
| 정적 (없음) | — | idle 1장 |
| `css-hover` | — | idle + active 2장 |
| `js-class` | — | idle + active 2장 |
| `intersection` | — | before + after 2장 |
| `scroll-driven` | 영상으로 변화 구간(trigger_y, mid_y, settled_y) 파악 | before + mid + after 3장 |
| `mousemove` | 영상 유지 (커서 좌표 연속 반응) | — |
| `auto-timer` | 영상 유지 (시간 기반 루프) | — |

> `scroll-driven`은 탐색 영상 없이 clip을 찍으면 어느 y에서 찍어야 하는지 알 수 없다. 영상으로 구간을 먼저 파악한 뒤 clip으로 검증한다.

### Step V2: ref 요소 rect 측정 + 상태별 캡처

요소마다 triggerType에 따라 상태를 만들고 rect을 측정한다.

**idle 상태 (모든 요소 공통):**

```bash
agent-browser --session <project> eval "(() => {
  const selectors = [
    'header',
    'nav a:first-child',
    /* ... */
  ];
  return JSON.stringify(
    selectors.map(sel => {
      const el = document.querySelector(sel);
      if (!el) return { sel, error: 'NOT FOUND' };
      el.scrollIntoView({ block: 'center' });
      const r = el.getBoundingClientRect();
      return { sel, x: r.x, y: r.y, width: r.width, height: r.height };
    })
  );
})()"
```

**active 상태 (css-hover / js-class / intersection 요소):**

상태를 eval로 적용한 직후 rect을 다시 측정한다 — hover 시 `transform: scale()` 등으로 rect이 바뀔 수 있음.

```bash
# css-hover: CDP hover 적용 후 측정
agent-browser --session <project> hover <selector>
agent-browser --session <project> wait <transitionDuration + 100>
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  const r = el.getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"

# js-class: classList.add 후 측정
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  el.classList.add('<triggerClass>');
  return new Promise(resolve => setTimeout(() => {
    const r = el.getBoundingClientRect();
    resolve(JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height }));
  }, <transitionDuration + 100>));
})()"

# intersection: 클래스 추가 후 측정
agent-browser --session <project> eval "(() => {
  const el = document.querySelector('<selector>');
  el.classList.add('in-view', 'is-visible');
  return new Promise(resolve => setTimeout(() => {
    const r = el.getBoundingClientRect();
    resolve(JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height }));
  }, <transitionDuration + 100>));
})()"

# scroll-driven: 탐색 영상에서 파악한 y값으로 각 상태 측정
# before (trigger_y - 50)
agent-browser --session <project> eval "(() => window.scrollTo(0, <trigger_y - 50>))()"
agent-browser --session <project> wait 500
agent-browser --session <project> eval "(() => {
  const r = document.querySelector('<selector>').getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"

# mid (mid_y)
agent-browser --session <project> eval "(() => window.scrollTo(0, <mid_y>))()"
agent-browser --session <project> wait 500
agent-browser --session <project> eval "(() => {
  const r = document.querySelector('<selector>').getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"

# after (settled_y + 50)
agent-browser --session <project> eval "(() => window.scrollTo(0, <settled_y + 50>))()"
agent-browser --session <project> wait 500
agent-browser --session <project> eval "(() => {
  const r = document.querySelector('<selector>').getBoundingClientRect();
  return JSON.stringify({ x: r.x, y: r.y, width: r.width, height: r.height });
})()"
```

### Step V3: 요소 단위 clip screenshot

ref와 impl 각각, 동일한 요소를 동일한 rect으로 캡처한다. **상태별로 각각 캡처.**

```bash
# idle (정적 요소 / css-hover / js-class / intersection 공통 — 상태 적용 전)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-idle.png

# active / after (css-hover → active, js-class → active, intersection → after)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-active.png

# scroll-driven: before / mid / after 각각
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-before.png  # trigger_y - 50
# (re-measure rect at mid_y, then:)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-mid.png     # mid_y
# (re-measure rect at settled_y + 50, then:)
agent-browser --session <project> screenshot \
  --clip <x>,<y>,<width>,<height> \
  tmp/ref/capture/clip/ref/<name>-after.png   # settled_y + 50
```

파일명 규칙:
- `css-hover` / `js-class`: `<name>-idle.png`, `<name>-active.png`
- `intersection`: `<name>-idle.png` (before-animate), `<name>-after.png` (after-animate)
- `scroll-driven`: `<name>-before.png`, `<name>-mid.png`, `<name>-after.png`
- 정적 요소: `<name>-idle.png`

impl도 동일하게 반복 (`ref` → `impl` 경로 변경).

> **주의:** ref와 impl의 class name이 다를 수 있음 (CSS Modules 해시). 동일한 *논리적* 요소를 찾아야 함.

### Step V4: 픽셀 diff 실행

상태별로 각각 diff를 실행한다.

캡처한 모든 상태 파일에 대해 각각 실행한다.

```bash
# ImageMagick (brew install imagemagick)
# triggerType에 따라 상태 파일명이 다름 — 아래 패턴을 적용
for STATE in idle active; do           # css-hover / js-class
  compare -metric AE \
    tmp/ref/capture/clip/ref/<name>-${STATE}.png \
    tmp/ref/capture/clip/impl/<name>-${STATE}.png \
    tmp/ref/capture/clip/diff/<name>-${STATE}.png 2>&1
done

for STATE in before after; do          # intersection
  compare -metric AE \
    tmp/ref/capture/clip/ref/<name>-${STATE}.png \
    tmp/ref/capture/clip/impl/<name>-${STATE}.png \
    tmp/ref/capture/clip/diff/<name>-${STATE}.png 2>&1
done

for STATE in before mid after; do      # scroll-driven
  compare -metric AE \
    tmp/ref/capture/clip/ref/<name>-${STATE}.png \
    tmp/ref/capture/clip/impl/<name>-${STATE}.png \
    tmp/ref/capture/clip/diff/<name>-${STATE}.png 2>&1
done
# → 출력값 = 다른 픽셀 수. 0이면 pass.

# ImageMagick 없으면 ffmpeg SSIM으로 대체:
ffmpeg -i tmp/ref/capture/clip/ref/<name>-<state>.png \
       -i tmp/ref/capture/clip/impl/<name>-<state>.png \
       -lavfi "ssim" -f null - 2>&1 | grep SSIM
# → All:1.000000 = 완전 일치
```

> idle이 pass여도 active/mid/after가 fail인 경우가 흔하다. 모든 상태를 빠짐없이 실행한다.

### Step V5: 판정

| 결과 | 기준 |
|------|------|
| ✅ PASS | AE = 0 또는 SSIM All ≥ 0.995 |
| ❌ FAIL | 그 외 |

> **"거의 같아 보임"은 FAIL이다.** Phase 2는 결과와 무관하게 항상 실행한다.

diff 이미지(`diff/<name>-<state>.png`)를 Read 도구로 열어 어느 영역이 다른지 육안으로도 확인한다.

### Step V6: Visual Gate JSON 저장

```json
{
  "component": "<name>",
  "measuredAt": "<ISO timestamp>",
  "viewport": { "width": 1440, "height": 900 },
  "result": "pass",
  "elements": [
    { "selector": "header", "state": "idle", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".btn", "state": "idle", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".btn", "state": "active", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".hero-text", "state": "before", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".hero-text", "state": "mid", "ae": 0, "ssim": 1.0, "status": "pass" },
    { "selector": ".hero-text", "state": "after", "ae": 0, "ssim": 1.0, "status": "pass" }
  ]
}
```

**Phase 1 결과와 무관하게 Phase 2를 항상 실행한다.**

---

## Phase 2: Numerical Diagnosis

> **Phase 1 결과와 무관하게 항상 실행한다.**
> Visual Gate pass여도 서브픽셀 오차는 잡히지 않는다. 수치 진단이 완전한 보고서를 만든다.

### What This Measures

| Property group | Properties |
|---|---|
| Typography | `fontSize`, `fontWeight`, `lineHeight`, `letterSpacing`, `fontFamily`, `textTransform`, `color` |
| Spacing | `paddingTop`, `paddingRight`, `paddingBottom`, `paddingLeft`, `marginTop`, `marginRight`, `marginBottom`, `marginLeft`, `gap`, `rowGap`, `columnGap` |
| Sizing | `width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight` |
| Layout | `display`, `flexDirection`, `alignItems`, `justifyContent`, `gridTemplateColumns`, `gridTemplateRows` |
| Visual | `backgroundColor`, `borderRadius`, `border`, `boxShadow`, `opacity`, `transform` |
| Position | `position`, `top`, `right`, `bottom`, `left` |

### Step P1: ref 측정

**idle 상태 측정:**

```bash
agent-browser --session <project> eval "(() => {
  const selectors = [
    /* Phase 1 FAIL 요소의 selector */
  ];

  const props = [
    'fontSize','fontWeight','lineHeight','letterSpacing','fontFamily',
    'color','backgroundColor','textTransform',
    'paddingTop','paddingRight','paddingBottom','paddingLeft',
    'marginTop','marginRight','marginBottom','marginLeft',
    'gap','rowGap','columnGap',
    'width','height','maxWidth','minWidth',
    'display','flexDirection','alignItems','justifyContent',
    'gridTemplateColumns','gridTemplateRows',
    'borderRadius','boxShadow','border','opacity','transform',
    'position','top','right','bottom','left'
  ];

  const result = {};
  for (const sel of selectors) {
    const el = document.querySelector(sel);
    if (!el) { result[sel] = 'NOT FOUND'; continue; }
    const cs = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    result[sel] = {
      _boundingRect: { width: Math.round(rect.width), height: Math.round(rect.height), top: Math.round(rect.top), left: Math.round(rect.left) }
    };
    for (const p of props) result[sel][p] = cs[p];
  }
  return JSON.stringify(result, null, 2);
})()"
```

`tmp/ref/<component>/ref-styles-idle.json`에 저장.

**active / mid / after 상태 측정:**

상태를 eval로 적용한 뒤 동일한 props를 측정한다.

```bash
# css-hover: CDP hover 적용
agent-browser --session <project> hover <selector>
agent-browser --session <project> wait <transitionDuration + 100>

# js-class: classList.add
agent-browser --session <project> eval "document.querySelector('<sel>').classList.add('<cls>')"
agent-browser --session <project> wait <transitionDuration + 100>

# scroll-driven: 탐색 영상에서 파악한 y값으로 각 상태 순서대로 측정
# before → mid → after 각각 scrollTo 후 wait 500 후 측정

agent-browser --session <project> eval "(() => {
  const sel = '<selector>';
  const props = ['color','backgroundColor','borderColor','boxShadow','transform','opacity','filter','fontSize','fontWeight','letterSpacing'];
  const el = document.querySelector(sel);
  if (!el) return JSON.stringify({ error: 'NOT FOUND' });
  const cs = getComputedStyle(el);
  const result = { _state: '<state>' };  // 'active' | 'mid' | 'after'
  for (const p of props) result[p] = cs[p];
  return JSON.stringify(result, null, 2);
})()"
```

상태별로 저장:
- `tmp/ref/<component>/ref-styles-active.json` (css-hover / js-class)
- `tmp/ref/<component>/ref-styles-before.json`, `ref-styles-mid.json`, `ref-styles-after.json` (scroll-driven)

> **CSS Modules 사이트 selector 탐색:**
> ```bash
> agent-browser eval "document.querySelector('header')?.className"
> ```

### Step P2: impl 측정

동일한 스크립트를 impl URL에서 실행. 저장 경로:
- idle → `tmp/ref/<component>/impl-styles-idle.json`
- active → `tmp/ref/<component>/impl-styles-active.json` (css-hover / js-class)
- before / mid / after → `tmp/ref/<component>/impl-styles-before.json`, `impl-styles-mid.json`, `impl-styles-after.json` (scroll-driven)

### Step P3: Diff Table 작성

state 컬럼을 포함해서 작성한다 — 같은 요소라도 idle/active/before/mid/after별로 값이 다름.

| Element | State | Property | Ref value | Impl value | Status |
|---|---|---|---|---|---|
| `.brand` | idle | `fontSize` | `24px` | `16px` | ❌ |
| `.brand` | idle | `color` | `#000` | `#000` | ✅ |
| `.btn` | active | `backgroundColor` | `#0070f3` | `#005cc5` | ❌ |
| `.hero-text` | mid | `transform` | `translateY(0px) scale(1)` | `translateY(12px) scale(0.95)` | ❌ |

**Rules:**
- `rgb()` vs `rgba()` alpha=1: rgb값 동일하면 ✅
- `width: 1349px` vs `1347px`: 2px 이내 ✅ (subpixel)
- `width: 72px` vs `810px`: ❌
- **반올림해서 같다고 선언 금지.** `16px ≠ 14px`

### Step P4: 수정

각 ❌ 행에 대해:
1. impl에서 해당 속성을 제어하는 CSS 파일/규칙 찾기
2. ref 값으로 수정
3. 해당 요소만 P2 재측정
4. ✅ 확인

**모든 ❌가 ✅ 될 때까지 반복.**

### Step P5: 수정 후 재실행

수정 완료 후 **Phase 1 Visual Gate + Phase 2 Numerical Diagnosis를 모두 다시 실행**한다.

Phase 1 all pass AND Phase 2 mismatches = 0 → 완료.
그 외 → 재진단.

---

## Gate

```
PIXEL-PERFECT GATE:
□ Phase 1 Visual Gate JSON 존재
□ 모든 elements의 status = "pass" (idle / active / before / mid / after — triggerType에 따라)
□ Phase 2 Numerical Diagnosis 완료
□ mismatches = 0

Phase 1 all pass AND mismatches = 0 → 완료.
둘 중 하나라도 미달 → 수정 후 재실행.
"거의 동일" = FAIL.
```

---

## Anti-patterns

| Anti-pattern | Why forbidden |
|---|---|
| "스크린샷이 비슷해 보임" | 눈으로는 2px font 차이, 10px spacing 오류를 못 잡음 |
| "Visual Gate pass니까 수치 진단 생략" | 서브픽셀 오차는 AE=0이어도 수치가 다를 수 있음. Phase 2는 항상 실행. |
| "충분히 가깝다" | 기준 없는 선언. 수치로 판정한다. |
| `offsetWidth` 사용 | 정수 반올림됨. `getComputedStyle` 사용. |
| FAIL 요소만 진단 | diff 이미지로 FAIL 범위를 먼저 확인하고 전체 측정. |

#!/usr/bin/env bash
# extract-assets.sh — Download video backgrounds, fonts, and other assets from original site
# Usage: bash extract-assets.sh <session> <output-dir> <public-dir>
#   session    = agent-browser session name (site must be open)
#   output-dir = e.g. tmp/ref/mysite
#   public-dir = e.g. apps/mysite/public
#
# Downloads:
#   1. Video backgrounds → <public-dir>/videos/
#   2. Font files (from Typekit, Google Fonts, CDN) → <public-dir>/fonts/
#   3. Produces font-faces.css with @font-face declarations
#
# Solves: "implementation uses static image but original has video background"
#         "lores-12 font not loaded because file wasn't downloaded"

set -euo pipefail

SESSION="${1:?Usage: extract-assets.sh <session> <output-dir> <public-dir>}"
DIR="${2:?Usage: extract-assets.sh <session> <output-dir> <public-dir>}"
PUBLIC="${3:?Usage: extract-assets.sh <session> <output-dir> <public-dir>}"

mkdir -p "$PUBLIC/videos" "$PUBLIC/fonts" "$DIR/assets"

echo "═══ Asset Extraction ═══"
echo ""

# ── 1. Video backgrounds ──
echo "── Extracting video sources ──"

VIDEOS_JSON=$(agent-browser --session "$SESSION" eval "(() => {
  const videos = document.querySelectorAll('video');
  const result = [];
  videos.forEach((v, i) => {
    const sources = [...v.querySelectorAll('source')].map(s => ({
      src: s.src, type: s.type
    }));
    const currentSrc = v.currentSrc || v.src;
    // Determine which section this video is in
    let section = 'unknown';
    let parent = v.parentElement;
    while (parent && parent !== document.body) {
      const cls = typeof parent.className === 'string' ? parent.className : '';
      if (cls.includes('hero')) { section = 'hero'; break; }
      if (cls.includes('showcase')) { section = 'showcase'; break; }
      if (cls.includes('feature')) { section = 'features'; break; }
      if (parent.tagName === 'SECTION') { section = 'section-' + i; break; }
      parent = parent.parentElement;
    }
    result.push({ index: i, section, currentSrc, sources });
  });
  return JSON.stringify(result);
})()" 2>/dev/null || echo "[]")

VIDEOS_JSON=$(echo "$VIDEOS_JSON" | sed 's/^"//;s/"$//' | sed 's/\\"/"/g')

VIDEO_COUNT=$(echo "$VIDEOS_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "  Found $VIDEO_COUNT videos"

if [ "$VIDEO_COUNT" -gt 0 ]; then
  echo "$VIDEOS_JSON" | python3 -c "
import json, sys, subprocess, os

videos = json.load(sys.stdin)
public_dir = '$PUBLIC'

for v in videos:
    section = v['section']
    # Prefer mp4, fallback to webm
    url = v['currentSrc']
    for s in v['sources']:
        if s['type'] == 'video/mp4':
            url = s['src']
            break

    if not url:
        continue

    ext = '.mp4' if 'mp4' in url else '.webm'
    filename = f'{section}-bg{ext}'
    out_path = os.path.join(public_dir, 'videos', filename)

    if os.path.exists(out_path):
        print(f'  ⏭️  {filename} (already exists)')
        continue

    print(f'  ⬇️  {filename} from {url[:80]}...')
    result = subprocess.run(['curl', '-sL', '-o', out_path, '--max-time', '30', url],
                           capture_output=True, timeout=35)
    if result.returncode == 0 and os.path.getsize(out_path) > 1000:
        size_mb = os.path.getsize(out_path) / 1024 / 1024
        print(f'  ✅ {filename} ({size_mb:.1f} MB)')
    else:
        print(f'  ❌ {filename} FAILED')
        os.remove(out_path) if os.path.exists(out_path) else None
" 2>/dev/null
fi

# ── 2. Font files ──
echo ""
echo "── Extracting font files ──"

# Get all font URLs from CSS resources
FONT_JSON=$(agent-browser --session "$SESSION" eval "(() => {
  const fontURLs = new Set();

  // From performance API
  performance.getEntriesByType('resource').forEach(e => {
    if (e.name.match(/\.(woff2?|ttf|otf|eot)(\?|$)/i)) {
      fontURLs.add(e.name);
    }
  });

  // From stylesheets - find @font-face src URLs
  try {
    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules) {
          if (rule.type === CSSRule.FONT_FACE_RULE) {
            const src = rule.style.getPropertyValue('src');
            const family = rule.style.getPropertyValue('font-family');
            const weight = rule.style.getPropertyValue('font-weight');
            const style = rule.style.getPropertyValue('font-style');
            // Extract woff2 URL
            const match = src.match(/url\\([\"']?([^\"')]+\\.woff2[^\"')]*)[\"']?\\)/);
            if (match) {
              fontURLs.add(JSON.stringify({
                url: match[1],
                family: family.replace(/[\"']/g, ''),
                weight: weight || '400',
                style: style || 'normal'
              }));
            }
          }
        }
      } catch(e) { /* cross-origin stylesheet */ }
    }
  } catch(e) {}

  return JSON.stringify([...fontURLs]);
})()" 2>/dev/null || echo "[]")

FONT_JSON=$(echo "$FONT_JSON" | sed 's/^"//;s/"$//' | sed 's/\\"/"/g')

# Download fonts and generate @font-face CSS
echo "$FONT_JSON" | python3 -c "
import json, sys, subprocess, os, re

entries = json.load(sys.stdin)
public_dir = '$PUBLIC'
font_faces = []

for entry in entries:
    # Entry is either a plain URL string or a JSON object string
    try:
        info = json.loads(entry)
        url = info['url']
        family = info.get('family', 'unknown')
        weight = info.get('weight', '400')
        style = info.get('style', 'normal')
    except (json.JSONDecodeError, TypeError):
        url = entry
        family = 'unknown'
        weight = '400'
        style = 'normal'

    if not url or not url.startswith('http'):
        continue

    # Generate filename
    safe_family = re.sub(r'[^a-zA-Z0-9]', '-', family).strip('-')
    ext = '.woff2' if 'woff2' in url else '.woff' if 'woff' in url else '.ttf'
    filename = f'{safe_family}-{weight}{ext}'
    out_path = os.path.join(public_dir, 'fonts', filename)

    if os.path.exists(out_path):
        print(f'  ⏭️  {filename} ({family} w{weight})')
    else:
        result = subprocess.run(['curl', '-sL', '-o', out_path, '--max-time', '15', url],
                               capture_output=True, timeout=20)
        if result.returncode == 0 and os.path.exists(out_path) and os.path.getsize(out_path) > 100:
            print(f'  ✅ {filename} ({family} w{weight})')
        else:
            print(f'  ❌ {filename} FAILED')
            continue

    font_faces.append(f'''@font-face {{
  font-family: \"{family}\";
  src: url(\"/fonts/{filename}\") format(\"woff2\");
  font-weight: {weight};
  font-style: {style};
  font-display: swap;
}}''')

# Write font-faces.css
if font_faces:
    css_path = os.path.join('$DIR', 'assets', 'font-faces.css')
    with open(css_path, 'w') as f:
        f.write('\n\n'.join(font_faces))
    print(f'\n  Generated: {css_path} ({len(font_faces)} @font-face rules)')
" 2>/dev/null

# ── 3. Also extract hero video frame as static fallback ──
echo ""
echo "── Extracting hero video frame ──"

if [ -f "$PUBLIC/videos/hero-bg.mp4" ] || [ -f "$PUBLIC/videos/hero-bg.webm" ]; then
  VIDEO_FILE=$(ls "$PUBLIC/videos/hero-bg."* 2>/dev/null | head -1)
  if [ -n "$VIDEO_FILE" ]; then
    ffmpeg -y -i "$VIDEO_FILE" -vframes 1 -ss 2 "$PUBLIC/images/hero-video-frame.jpg" 2>/dev/null
    if [ -f "$PUBLIC/images/hero-video-frame.jpg" ]; then
      echo "  ✅ hero-video-frame.jpg (frame at t=2s)"
    else
      echo "  ❌ Frame extraction failed"
    fi
  fi
else
  echo "  ⏭️  No hero video downloaded"
fi

echo ""
echo "═══ Done ═══"
echo "Videos: $PUBLIC/videos/"
echo "Fonts:  $PUBLIC/fonts/"
echo "CSS:    $DIR/assets/font-faces.css"

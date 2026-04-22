# WAAPI Scrubbing — Page-Load Animations

Problem: `agent-browser open` waits for full load — page-load animations are already done.

## Inject scrubber

> **Security note:** The scrubber script (`waapi-scrub-inject.js`) is injected into the **target site's page context** via `agent-browser eval`. This is intentional — it manipulates WAAPI animations on the remote page for measurement. The script is a local, trusted file from this skill's directory. Never inject untrusted or downloaded scripts this way.

```bash
agent-browser open https://target-site.com

# Inject scrubber — resolve skill directory
# Searches: CLAUDE_SKILLS_DIR env var → project-local → ~/.claude/skills
SKILL_DIR=""
for candidate in \
  "${CLAUDE_SKILLS_DIR:+$CLAUDE_SKILLS_DIR/skills/ui-reverse-engineering}" \
  "$(git rev-parse --show-toplevel 2>/dev/null)/skills/ui-reverse-engineering" \
  "$HOME/.claude/skills/ui-skills/skills/ui-reverse-engineering"; do
  [ -n "$candidate" ] && [ -f "$candidate/waapi-scrub-inject.js" ] && SKILL_DIR="$candidate" && break
done
if [ -z "$SKILL_DIR" ]; then
  echo "Error: waapi-scrub-inject.js not found. Set CLAUDE_SKILLS_DIR or run from project root." >&2
  exit 1
fi
agent-browser eval "$(cat "$SKILL_DIR/waapi-scrub-inject.js")"
```

## Set up animations to scrub

```bash
# selector must be a valid CSS selector string (e.g. '.hero', '#title span')
# Fill in keyframes extracted from css-extraction.md
agent-browser eval "
(() => {
  return window.__scrub.setup([
    {
      selector: '.hero',
      keyframes: [
        { opacity: '0', transform: 'translateY(43px)', filter: 'blur(16px)' },
        { opacity: '1', transform: 'translateY(0px)', filter: 'blur(0px)' }
      ],
      duration: 600,
      delay: 0
    }
  ]);
})()"
```

## Capture frames

```bash
# output-dir must be relative, alphanumeric/dash/slash only
"$SKILL_DIR/capture-frames.sh" tmp/ref/<effect-name>/frames 2000 15
```

## Recovery

If `window.__scrub` disappears mid-capture (page reloaded):

```bash
agent-browser eval "(() => typeof window.__scrub)()"
# If result is "undefined" — re-inject using the same SKILL_DIR from above
agent-browser eval "$(cat "$SKILL_DIR/waapi-scrub-inject.js")"
```

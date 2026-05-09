# Agent Environment Rules — load on first session, before Phase 0

These rules cover post-mortem failure modes that have surfaced in prior cloning sessions. They are environment-level (shell, CLI, paths) rather than pipeline-level. Read once at session start; the SKILL.md core rules cover token / I/O hygiene, this file covers the environment surface around them.

## Viewport ordering rule

Always run `agent-browser --session <s> open <url>` **before** `set viewport <w> <h>`, and add `wait` after. Calling `set viewport` *before* the page is open is silently dropped — the browser opens at the default 1280 wide and your width is lost. Correct order:

```
open → set viewport → wait
```

This matters most for mobile sweeps (375, 414, 768) where a wrong viewport silently passes desktop checks. The script `font-parity-check.sh`, `breakpoint-collision-check.sh`, and `section-compare.sh` all follow this order; reuse the pattern when writing new scripts.

## Shell-loop rule (zsh)

zsh does NOT word-split unquoted variables by default, so `set -- $vp; W=$1; H=$2` leaves `W` and `H` empty when iterating `"375 812"`-style strings.

Either:

```bash
# Option A: split with awk
W=$(echo "$vp" | awk '{print $1}')
H=$(echo "$vp" | awk '{print $2}')

# Option B: heredoc-style read
read -r W H <<< "$vp"

# Option C: run the loop in bash explicitly
#!/usr/bin/env bash
```

Silent empty-variable bugs are common when reusing scripts written in bash. Verify with `echo "W=$W H=$H"` once before relying on the values inside a long loop.

## Monorepo path resolution rule

When the user names a project with a space — *"X showcase"*, *"Y dashboard"*, *"Z app"* — do NOT treat that as a literal directory `~/Documents/X showcase/`.

Always check monorepo layouts first:

```bash
ls ~/Documents/<X>/apps/<showcase|dashboard|app>
ls ~/Documents/<X>/packages/
```

Only fall back to the literal-path interpretation if no monorepo match exists. Confirm with `pwd` after `cd`. Acting on the literal path silently puts every artifact in the wrong place and the pipeline gates pass against an empty repo — the worst failure mode because every check looks green.

## agent-browser CLI rule

Run `agent-browser --help` once at session start to confirm verb syntax.

Common mistakes from prior sessions:

- `agent-browser scrollTo 0 500` — **no such verb.** Use `agent-browser eval "window.scrollTo(0, 500)"` or `agent-browser scroll down 500`.
- The valid scroll verbs are `scroll <dir> [px]`, `scrollintoview <sel>`, `mouse wheel <dy> [dx]` — there is no `scrollTo`.

Unknown verbs typically exit with an error rather than silently no-op, but the error is easy to miss in long Bash chains; check exit codes when in doubt.

## Pipeline directory layout rule

`tmp/ref/<component>/` is **flat**. Sub-dirs live directly under it:

```
tmp/ref/<component>/
├── static/ref/         ← screenshots
├── scroll-video/ref/   ← scroll videos
├── transitions/ref/    ← transition recordings
├── frames/             ← extracted frames
├── bundles/            ← downloaded JS chunks
├── css/                ← downloaded CSS
├── sections/           ← section-compare output
├── verify/             ← post-implement verification frames
└── responsive/         ← boundary-collisions.json, sizing-expressions.json
```

Gate validators look for `tmp/ref/<c>/static/ref/`, NOT `tmp/ref/<c>/capture/static/ref/`. The `capture/` parent only exists in standalone `/ui-capture` runs without a `<component>` arg.

**Always invoke `/ui-capture` with the 3rd `[component]` arg** so it writes to `tmp/ref/<c>/` directly — `/ui-capture <url> "" <component>`. Pass `""` for the local-url slot when you only need ref capture.

`tmp/ref/` lives **inside the project root** that owns the component, not under `~/`. If you've `cd`'d to `~/Documents/<repo>/apps/<app>/`, that's where `tmp/ref/` should be. Verify with `pwd && ls tmp/ref/<c>/` before each gate run — gates have no opinion about which directory is "the right one"; they validate the path you pass in.

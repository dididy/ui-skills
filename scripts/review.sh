#!/usr/bin/env bash
# review.sh — Automated review checklist for ui-clone-skills
# Runs tests, security checks, and content consistency validation.
# Called by claude-post-push.sh after successful push, or manually.
#
# Usage: bash scripts/review.sh [--quiet]
# Exit: 0 = all pass, 1 = failures found

set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)" || { echo "review.sh: cannot resolve repo root" >&2; exit 1; }
cd "$REPO_ROOT" || { echo "review.sh: cannot cd to $REPO_ROOT" >&2; exit 1; }

ERRORS=0
WARNINGS=0
PASSED=0

err() { echo "  ❌ $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "  ⚠️  $*" >&2; WARNINGS=$((WARNINGS + 1)); }
ok() { [ "$QUIET" = "1" ] || echo "  ✓ $*"; PASSED=$((PASSED + 1)); }
section() { [ "$QUIET" = "1" ] || echo ""; [ "$QUIET" = "1" ] || echo "── $* ──"; }

# ── 1. Tests ──
section "Tests"
if command -v uv >/dev/null 2>&1; then
  TEST_OUT=$(uv run python -m pytest tests/ -q 2>&1)
  if echo "$TEST_OUT" | grep -q "passed"; then
    PASS_COUNT=$(echo "$TEST_OUT" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
    ok "pytest: $PASS_COUNT passed"
  else
    err "pytest failures detected"
    [ "$QUIET" = "0" ] && echo "$TEST_OUT" | tail -10 >&2
  fi
else
  warn "uv not found — skipping tests"
fi

# ── 2. Security gate ──
section "Security"
if bash scripts/pre-push-security.sh --quiet 2>/dev/null; then
  ok "pre-push-security: clean"
else
  err "pre-push-security: blockers found"
fi

# ── 3. Step numbering consistency ──
section "Step numbering"

# bundle-analysis.md must say Step 5c, not Step 6
if head -1 skills/ui-reverse-engineering/bundle-analysis.md | grep -q "Step 5c"; then
  ok "bundle-analysis.md: Step 5c"
else
  err "bundle-analysis.md: title should say Step 5c (not Step 6)"
fi

# animation-detection.md must say Step 6
if head -1 skills/ui-reverse-engineering/animation-detection.md | grep -q "Step 6"; then
  ok "animation-detection.md: Step 6"
else
  err "animation-detection.md: title should say Step 6"
fi

# ── 4. Stale references ──
section "Stale references"

# Old package name
OLD_PKG=$(grep -rl 'ui_skills\.' skills/ ui_clone/ tests/ 2>/dev/null | grep -v CHANGELOG | grep -v __pycache__ || true)
if [ -z "$OLD_PKG" ]; then
  ok "no ui_skills.* references"
else
  err "old package name ui_skills.* found in: $OLD_PKG"
fi

# Old plugin name in code (not CHANGELOG)
OLD_NAME=$(grep -rlw 'ui-skills' ui_clone/ skills/ hooks/ 2>/dev/null | grep -v CHANGELOG | grep -v __pycache__ || true)
if [ -z "$OLD_NAME" ]; then
  ok "no 'ui-skills' references in code (correct: ui-clone-skills)"
else
  err "old plugin name 'ui-skills' found in: $OLD_NAME"
fi

# Deleted files
for STALE in "validate-gate.sh" "run-pipeline.sh" "waapi-scrub-inject.js" "capture-frames.sh"; do
  REFS=$(grep -rl "$STALE" skills/ scripts/ 2>/dev/null | grep -v CHANGELOG | grep -v review.sh || true)
  if [ -z "$REFS" ]; then
    ok "no refs to deleted $STALE"
  else
    err "$STALE referenced in: $REFS"
  fi
done

# Old owner name
DIDIDY=$(grep -rl 'dididy' README.md skills/ .claude-plugin/ 2>/dev/null | grep -v review.sh || true)
if [ -z "$DIDIDY" ]; then
  ok "no dididy references (owner is voidmatcha)"
else
  err "old owner 'dididy' found in: $DIDIDY"
fi

# Wrong npm package name
WRONG_NPM=$(grep -rl '@anthropic-ai/agent-browser' skills/ ui_clone/ 2>/dev/null | grep -v review.sh || true)
if [ -z "$WRONG_NPM" ]; then
  ok "no @anthropic-ai/agent-browser refs (correct: agent-browser)"
else
  err "wrong npm name @anthropic-ai/agent-browser in: $WRONG_NPM"
fi

# ── 5. Gate-artifact timing ──
section "Gate-artifact timing"

# external-sdks.json must be in gate_spec, not gate_bundle
if uv run python -c "
import ast, sys
with open('ui_clone/gate.py') as f:
    src = f.read()
# Check gate_bundle does NOT contain external-sdks
bundle_start = src.index('def gate_bundle')
bundle_end = src.index('def gate_spec')
bundle_body = src[bundle_start:bundle_end]
spec_start = bundle_end
spec_end = src.index('def gate_pre_generate')
spec_body = src[spec_start:spec_end]
if 'external-sdks' in bundle_body:
    print('external-sdks.json is in gate_bundle (should be in gate_spec)', file=sys.stderr)
    sys.exit(1)
if 'external-sdks' not in spec_body:
    print('external-sdks.json missing from gate_spec', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
  ok "external-sdks.json in gate_spec (not gate_bundle)"
else
  err "external-sdks.json gate placement wrong"
fi

# ── 6. Section name keyword sync ──
section "Section keyword sync"

extract_keywords() {
  grep -oE "'\w+','\w+'" "$1" 2>/dev/null | tr -d "'" | sort -u
}

KW1=$(grep -c "kwMap" scripts/extract-assets.sh 2>/dev/null || echo "0")
KW2=$(grep -c "kwMap" scripts/extract-section-html.sh 2>/dev/null || echo "0")
KW3=$(grep -c "kwMap" scripts/section-clips.sh 2>/dev/null || echo "0")
if [ "$KW1" -gt 0 ] && [ "$KW2" -gt 0 ] && [ "$KW3" -gt 0 ]; then
  ok "all 3 scripts use kwMap pattern"
else
  err "section name detection not using kwMap in all 3 scripts"
fi

# ── 7. README accuracy ──
section "README accuracy"

# Sub-doc count
ACTUAL_SUBDOCS=$(find skills -name "*.md" ! -name "SKILL.md" | wc -l | tr -d ' ')
README_COUNT=$(grep -oE '[0-9]+ focused sub-docs' README.md | grep -oE '[0-9]+')
if [ "$ACTUAL_SUBDOCS" = "$README_COUNT" ]; then
  ok "sub-doc count matches README ($ACTUAL_SUBDOCS)"
else
  err "sub-doc count: actual=$ACTUAL_SUBDOCS, README=$README_COUNT"
fi

# FPS default
FPS_DEFAULT=$(grep -oE 'FPS="\$\{FPS:-[0-9]+\}"' scripts/video-transition-compare.sh | grep -oE '[0-9]+')
if [ "$FPS_DEFAULT" = "60" ]; then
  ok "video-transition-compare.sh FPS default is 60"
else
  err "video-transition-compare.sh FPS default is $FPS_DEFAULT (should be 60)"
fi

# ── 8. Hardcoded paths ──
section "Hardcoded paths"
# Detect absolute user-home paths (/Users/<name>/ or /home/<name>/)
HARDCODED=$(grep -rlE '/Users/[a-zA-Z]+/|/home/[a-zA-Z]+/' skills/ scripts/ ui_clone/ 2>/dev/null \
  | grep -v review.sh | grep -v CHANGELOG | grep -v __pycache__ || true)
if [ -z "$HARDCODED" ]; then
  ok "no hardcoded absolute paths"
else
  err "hardcoded absolute paths found in: $HARDCODED"
fi

# ── 9. Shell syntax ──
section "Shell syntax"

SH_BAD=""
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || SH_BAD="$SH_BAD $f"
done < <(find scripts skills -name '*.sh' -type f 2>/dev/null)
if [ -z "$SH_BAD" ]; then
  SH_COUNT=$(find scripts skills -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')
  ok "all $SH_COUNT shell scripts pass bash -n"
else
  err "shell syntax errors in:$SH_BAD"
fi

# ── 10. Language consistency ──
section "Language"

# SKILL.md and sub-docs should be English only
# Exclude evals (multilingual trigger tests) and font-check examples
KOREAN_IN_SKILLS=$(grep -rlP '[\x{AC00}-\x{D7AF}]' skills/ 2>/dev/null \
  | grep -v '/evals/' | grep -v 'asset-extraction.md' || true)
if [ -z "$KOREAN_IN_SKILLS" ]; then
  ok "skills/ docs are English only"
else
  err "Korean text found in skill docs: $KOREAN_IN_SKILLS"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════════════"
echo "  Review: $PASSED passed, $WARNINGS warnings, $ERRORS errors"
echo "════════════════════════════════════════"

[ "$ERRORS" -gt 0 ] && exit 1
exit 0

#!/usr/bin/env bash
# auto-verify.sh — Run ALL verification checks in sequence
# Replaces manual "Read verification.md and execute each step"
#
# Usage: bash auto-verify.sh <session> <orig-url> <impl-url> <ref-dir>
# Exit: 0 = all checks passed, 1 = failures found
#
# Runs:
#   1. Layout health check (Phase D0)
#   2. Batch scroll capture + AE comparison (Phase C)
#   3. Post-implement gate check
#
# This script exists because the LLM consistently skips verification steps
# when done manually. Automating removes the temptation to skip.

set -uo pipefail

SESSION="${1:?Usage: auto-verify.sh <session> <orig-url> <impl-url> <ref-dir>}"
ORIG_URL="${2:?}"
IMPL_URL="${3:?}"
REF_DIR="${4:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VD_SCRIPTS="$SCRIPT_DIR/../skills/visual-debug/scripts"

FAIL=0

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     AUTOMATED VERIFICATION PIPELINE      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Phase D0: Layout Health Check ──
echo "━━━ Phase D0: Layout Health Check ━━━"
if [ -f "$VD_SCRIPTS/layout-health-check.sh" ]; then
  bash "$VD_SCRIPTS/layout-health-check.sh" "$SESSION" "$ORIG_URL" "$IMPL_URL" "$REF_DIR" 2>&1
  if [ $? -ne 0 ]; then
    echo ""
    echo "⛔ Phase D0 FAILED — fix layout issues before continuing"
    FAIL=$((FAIL + 1))
  fi
else
  echo "⚠️  layout-health-check.sh not found — skipping"
fi
echo ""

# ── Phase C: Batch Scroll Capture + AE Comparison ──
echo "━━━ Phase C: Visual Comparison ━━━"
if [ -f "$VD_SCRIPTS/batch-scroll.sh" ] && [ -f "$VD_SCRIPTS/batch-compare.sh" ]; then
  echo "▸ Capturing..."
  bash "$VD_SCRIPTS/batch-scroll.sh" "$ORIG_URL" "$IMPL_URL" "$SESSION" "$REF_DIR" 2>&1

  echo ""
  echo "▸ Comparing..."
  COMPARE_OUTPUT=$(bash "$VD_SCRIPTS/batch-compare.sh" "$REF_DIR" 2>&1)
  echo "$COMPARE_OUTPUT"

  # Count FAILs
  FAIL_COUNT=$(echo "$COMPARE_OUTPUT" | grep -c "❌" || true)
  PASS_COUNT=$(echo "$COMPARE_OUTPUT" | grep -c "✅" || true)

  echo ""
  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "⛔ Phase C: $FAIL_COUNT position(s) FAILED, $PASS_COUNT passed"
    FAIL=$((FAIL + 1))
  else
    echo "✅ Phase C: All $PASS_COUNT positions PASSED"
  fi
else
  echo "⚠️  batch-scroll.sh or batch-compare.sh not found — skipping"
fi
echo ""

# ── Post-implement gate ──
echo "━━━ Post-Implement Gate ━━━"
bash "$SCRIPT_DIR/validate-gate.sh" "$REF_DIR" post-implement 2>&1 || FAIL=$((FAIL + 1))
echo ""

# ── Summary ──
echo "╔══════════════════════════════════════════╗"
if [ "$FAIL" -gt 0 ]; then
  echo "║  ⛔ VERIFICATION FAILED ($FAIL issue(s))        ║"
  echo "║                                          ║"
  echo "║  DO NOT declare 'done' or 'complete'.    ║"
  echo "║  Fix the issues above and re-run.        ║"
  echo "╚══════════════════════════════════════════╝"
  exit 1
else
  echo "║  ✅ ALL VERIFICATION CHECKS PASSED        ║"
  echo "╚══════════════════════════════════════════╝"
  exit 0
fi

#!/usr/bin/env bash
# capture-frames.sh — capture N frames from a WAAPI animation using time scrubbing
#
# Prerequisites:
#   1. Page already open in agent-browser
#   2. waapi-scrub-inject.js injected: agent-browser eval "$(cat waapi-scrub-inject.js)"
#   3. window.__scrub.setup(configs) called with your animation configs
#
# Usage:
#   ./capture-frames.sh <output-dir> <total-duration-ms> [frames=15]
#
# Example:
#   agent-browser open https://lobehub.com
#   agent-browser eval "$(cat waapi-scrub-inject.js)"
#   agent-browser eval "$(cat lobehub-scrub-config.js)"   # calls window.__scrub.setup(...)
#   ./capture-frames.sh tmp/ref/lobehub-hero/cropped 2000 15
#
# Output:
#   tmp/ref/lobehub-hero/cropped/frame-01.png  (t=0ms)
#   tmp/ref/lobehub-hero/cropped/frame-02.png  (t=142ms)
#   ...
#   tmp/ref/lobehub-hero/cropped/frame-15.png  (t=2000ms)

set -euo pipefail

OUTPUT_DIR="${1:?Usage: $0 <output-dir> <total-duration-ms> [frames]}"
TOTAL_MS="${2:?Usage: $0 <output-dir> <total-duration-ms> [frames]}"
N_FRAMES="${3:-15}"

# Validate OUTPUT_DIR: relative path only, no traversal, alphanumeric/dash/underscore/slash
if [[ "$OUTPUT_DIR" = /* ]]; then
  echo "Error: output-dir must be a relative path (got: $OUTPUT_DIR)" >&2
  exit 1
fi
if [[ "$OUTPUT_DIR" =~ (^|/)\.\.(/|$) ]] || [[ "$OUTPUT_DIR" == *..* ]]; then
  echo "Error: output-dir must not contain '..' (got: $OUTPUT_DIR)" >&2
  exit 1
fi
if [[ "$OUTPUT_DIR" =~ [^a-zA-Z0-9._/\-] ]]; then
  echo "Error: output-dir contains invalid characters — use only [a-zA-Z0-9._/-] (got: $OUTPUT_DIR)" >&2
  exit 1
fi

# Validate TOTAL_MS and N_FRAMES are positive integers
if ! [[ "$TOTAL_MS" =~ ^[0-9]+$ ]] || [ "$TOTAL_MS" -eq 0 ]; then
  echo "Error: total-duration-ms must be a positive integer (got: $TOTAL_MS)" >&2
  exit 1
fi
if ! [[ "$N_FRAMES" =~ ^[0-9]+$ ]] || [ "$N_FRAMES" -eq 0 ]; then
  echo "Error: frames must be a positive integer (got: $N_FRAMES)" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Calculate step size
# N_FRAMES-1 intervals to cover 0..TOTAL_MS inclusive
if [ "$N_FRAMES" -le 1 ]; then
  STEP_MS=0
else
  STEP_MS=$(( TOTAL_MS / (N_FRAMES - 1) ))
fi

echo "Capturing $N_FRAMES frames, 0..${TOTAL_MS}ms, step=${STEP_MS}ms -> $OUTPUT_DIR"

for i in $(seq 1 "$N_FRAMES"); do
  # $T is computed from validated integers only — no injection risk
  T=$(( (i - 1) * STEP_MS ))
  FRAME="$(printf '%02d' "$i")"
  OUTFILE="$OUTPUT_DIR/frame-$FRAME.png"

  # Seek animation to time T
  # $T is always a non-negative integer — safe to interpolate directly without encoding
  if ! agent-browser eval "window.__scrub.seek($T);" > /dev/null 2>&1; then
    echo "Error: Failed to seek to ${T}ms" >&2
    exit 1
  fi

  # Screenshot
  agent-browser screenshot "$OUTFILE"

  echo "  frame-$FRAME  t=${T}ms  -> $OUTFILE"
done

echo "Done. $N_FRAMES frames in $OUTPUT_DIR"

#!/usr/bin/env bash
# Called when ui-reverse-engineering skill is invoked
# Creates a marker file that the pre-generate hook checks
#
# Usage: This should be added as a hook or called at the start of the pipeline
# Args: $1 = ref directory path (e.g., tmp/ref/evolve)

REF_DIR="${1:-}"
MARKER="tmp/.ui-re-active"

mkdir -p tmp
echo "$REF_DIR" > "$MARKER"
echo "UI-RE session started. Marker: $MARKER → $REF_DIR"

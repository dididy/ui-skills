#!/bin/bash
# Block git push if skills/ changed without docs/config update

input=$(cat)
echo "$input" | grep -qE '"command":"[^"]*git\s+push' || exit 0

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

base=$(git rev-parse origin/master 2>/dev/null) || exit 0
[ "$base" = "$(git rev-parse HEAD)" ] && exit 0

changed=$(git diff --name-only "$base" HEAD)
echo "$changed" | grep -q '^skills/' || exit 0

missing=""
for f in CHANGELOG.md .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  echo "$changed" | grep -q "^$f$" || missing="$missing $f"
done

if [ -n "$missing" ]; then
  echo "⚠️ skills/ changed but missing:$missing"
  echo "decision: block"
  exit 2
fi

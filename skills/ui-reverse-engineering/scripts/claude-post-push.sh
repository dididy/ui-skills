#!/bin/bash
# Claude Code PostToolUse hook: after successful git push, update local skills install

input=$(cat)
command=$(echo "$input" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')

# Only care about git push commands
if ! echo "$command" | grep -qE 'git\s+push'; then
  exit 0
fi

# Check if push succeeded (exit_code 0 in tool output)
if echo "$input" | grep -q '"exit_code":0'; then
  npx skills add dididy/ui-skills -gy 2>/dev/null
fi

exit 0

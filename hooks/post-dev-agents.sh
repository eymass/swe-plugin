#!/bin/bash
FLAG="/tmp/claude-dev-session-active"

if [ ! -f "$FLAG" ]; then
  exit 0
fi

# Clean up the flag
rm -f "$FLAG"

# stdout goes into Claude's context on Stop hooks
cat <<'EOF'
# instruct edited to invoke/do/skill/anything after code generation
EOF

exit 0

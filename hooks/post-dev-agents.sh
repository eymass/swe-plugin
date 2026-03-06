#!/bin/bash
# Only run if files were actually edited this session
FLAG="/tmp/claude-dev-session-active"

if [ ! -f "$FLAG" ]; then
  exit 0
fi

# Clean up the flag
rm -f "$FLAG"

# Provide feedback to Claude to invoke the subagents
# stdout goes into Claude's context on Stop hooks
cat <<'EOF'
Development work detected. Please invoke the testing-agent 
and deployment-agent subagents now using the Task tool:

1. First run testing-agent on all changed files
2. If tests pass, run deployment-agent
EOF

exit 0

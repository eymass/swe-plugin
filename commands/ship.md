---
name: ship
description: Run testing and deployment agents on current changes. Use after completing development work.
---

After completing the current development task, execute the following workflow:

1. **Testing phase**: Invoke the `tester-agent` as a subagent using the Task tool.
   - Pass it the list of files changed in this session.
   - Wait for it to complete and report all test results.
   - If any tests fail, fix the issues and re-run until all tests pass.

2. **Deployment phase** (only if all tests pass): Invoke the `deployer-agent` as a subagent using the Task tool.
   - Pass it the summary of changes and test results.
   - Wait for it to complete and report deployment status.

3. **Summary**: Provide a final summary with:
   - Files changed
   - Tests run and results
   - Deployment status

Never skip either step. If tests fail, do NOT proceed to deployment.

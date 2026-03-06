---
name: deploy
description: "Deploy the application to Heroku using Makefile targets. Use when the user says 'deploy', 'push to production', 'deploy to test', or similar deployment requests."
argument-hint: "[prod|test]"
allowed-tools: Bash, Read, Grep, Glob
context: fork
agent: deployer
---

# Deploy Application

Execute a deployment to the specified environment using the project's Makefile.

## Usage

- `/deployer:deploy prod` — Deploy to production (`post-generator-ai`)
- `/deployer:deploy test` — Deploy to test (`post-generator-ai-test`)
- `/deployer:deploy` — Will ask which environment to deploy to

## Steps

1. **Read the Makefile** to confirm the deployment targets and app names
2. **Check git status** to ensure there are no uncommitted changes
3. **Verify prerequisites**:
   - `HEROKU_API_KEY` is set
   - Heroku CLI is installed
   - Git repo has committed changes
4. **Run the deployment**:
   - For production: `make deploy`
   - For test: `make deploy-test`
5. **Capture and display** the full output of the deployment command
6. **Validate the deployment** by running the deploy-validate skill automatically after deployment completes

## Environment Details

| Environment | Make Target     | App Name                |
|------------|-----------------|-------------------------|
| Production | `make deploy`   | `post-generator-ai`     |
| Test       | `make deploy-test` | `post-generator-ai-test` |

## Important

- **Always confirm** before deploying to production
- Test deployments can proceed without confirmation
- If the deployment command fails, show the error output and suggest fixes
- After deployment, always validate using log analysis

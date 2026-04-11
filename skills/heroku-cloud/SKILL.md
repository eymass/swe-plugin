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

- `/deployer:deploy prod` — Deploy to production
- `/deployer:deploy test` — Deploy to test
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



### 2. Create the App

```bash
./tools/deploy/heroku_new_app.sh <app_name> <env_file>
```

This script will:
- Create the Heroku app
- Set config vars from the env file
- Add the heroku git remote
- Deploy the current codebase via `git push heroku main`

### 3. Post-Creation Validation
- Check the app was created: `heroku apps:info --app <app_name>`
- Verify config vars were set: `heroku config --app <app_name>`
- Check deployment status via logs: `heroku logs --app <app_name> -n 100`
- Verify HTTP response: `curl -s -o /dev/null -w "%{http_code}" https://<app_name>.herokuapp.com`

### 4. Report Results

```
✅ New App Created Successfully
   App: <app_name>
   URL: https://<app_name>.herokuapp.com
   Config Vars: <count> variables set
   Status: Running
```

## Important

- This skill only runs when explicitly invoked (`/deployer:deploy-new-app`)
- Always confirm the app name and env file with the user before proceeding
- Never expose secret values from the env file in output
- If the app name is already taken, suggest an alternative

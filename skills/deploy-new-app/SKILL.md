---
name: deploy-new-app
description: "Create and deploy a brand-new Heroku application. Use when the user wants to create a new Heroku app, set up a new environment, or provision a new deployment target."
argument-hint: "<app-name> <env-file>"
allowed-tools: Bash, Read, Grep, Glob
disable-model-invocation: true
context: fork
agent: deployer
---

# Create New Heroku App

Provision a new Heroku application using the `heroku_new_app.sh` script, which creates the app and sets config vars from an env file.

## Usage

- `/deployer:deploy-new-app my-app .prod.env` — Create a new app with production env vars
- `/deployer:deploy-new-app my-app-staging .test.env` — Create a staging app with test env vars

## Prerequisites

Before running this skill, verify:

1. **Heroku CLI** is installed: `command -v heroku`
2. **Heroku authentication** is active: `heroku auth:whoami`
3. **Env file exists** at the specified path
4. **Git repo** is initialized in the project root
5. **App name** is available (not already taken on Heroku)

## Steps

### 1. Validate Inputs
- Confirm the app name is provided and looks valid (lowercase, hyphens, numbers)
- Confirm the env file exists and contains valid key-value pairs
- Preview the config vars that will be set (without showing secret values)

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

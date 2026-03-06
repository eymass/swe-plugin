---
name: deploy-validate
description: "Validate a Heroku deployment by checking application logs and HTTP status. Use when the user wants to verify a deployment is healthy, check for errors after deploying, or diagnose deployment issues."
argument-hint: "[app-name]"
allowed-tools: Bash, Read, Grep
context: fork
agent: deployer
---

# Validate Deployment

Check that a Heroku deployment is healthy by analyzing logs and verifying the application is responding.

## Usage

- `/deployer:deploy-validate post-generator-ai` — Validate the production app
- `/deployer:deploy-validate post-generator-ai-test` — Validate the test app
- `/deployer:deploy-validate` — Will check the default production app

## Validation Steps

### 1. Fetch Recent Logs

```bash
heroku logs --app <app_name> -n 150
```

Retrieve the last 150 log lines to analyze the most recent deployment activity.

### 2. Analyze Logs for Issues

**Look for these error patterns** (any match = potential problem):

| Pattern | Meaning |
|---------|---------|
| `code=H10` | App crashed |
| `code=H12` | Request timeout |
| `code=H13` | Connection closed without response |
| `code=H14` | No web dynos running |
| `code=R14` | Memory quota exceeded |
| `at=error` | Heroku router error |
| `State changed from up to crashed` | App crashed after starting |
| `Error` in build output | Build failure |
| `SIGTERM` / `SIGKILL` | Process was killed |

**Look for these success patterns** (all should be present):

| Pattern | Meaning |
|---------|---------|
| `Build succeeded` | Heroku build completed |
| `Deployed` or `Launching` | Release was deployed |
| `State changed from starting to up` | App started successfully |
| `Listening on` or `Web process running` | App is serving traffic |

### 3. Check HTTP Status

```bash
curl -s -o /dev/null -w "%{http_code}" https://<app_name>.herokuapp.com
```

- **200-299**: App is responding normally ✅
- **301-399**: Redirect (may be normal) ⚠️
- **500-599**: Server error ❌
- **0 or timeout**: App is not responding ❌

### 4. Check Release History

```bash
heroku releases --app <app_name> -n 5
```

Verify the latest release deployed successfully and check if there were any rollbacks.

### 5. Report Results

Provide a clear summary:

```
✅ Deployment Healthy
   App: <app_name>
   URL: https://<app_name>.herokuapp.com
   HTTP Status: 200
   Latest Release: v42 - Deploy abc1234
   Logs: Clean — no errors detected

--- OR ---

❌ Deployment Issues Detected
   App: <app_name>
   HTTP Status: 503
   Errors Found:
   - H10 (App crashed) at 2024-01-15T10:30:00
   - State changed from up to crashed
   Recommendation: Check app logs or rollback with `heroku rollback --app <app_name>`
```

## Troubleshooting Checklist

If validation fails, investigate in this order:

1. **Check recent releases**: `heroku releases --app <app_name> -n 10`
2. **Check config vars**: `heroku config --app <app_name>` (look for missing vars)
3. **Check dyno status**: `heroku ps --app <app_name>`
4. **Check for memory issues**: Look for R14 errors in logs
5. **Suggest rollback**: `heroku rollback --app <app_name>` to revert to the previous working release

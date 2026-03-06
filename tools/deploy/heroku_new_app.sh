#!/bin/bash
set -euo pipefail

#######################################################################
# Deploy a NEW Heroku app
#
# Usage:
#   ./tools/deploy/heroku_new_app.sh <app_name> <env_file>
#
# Arguments:
#   app_name  – Name for the new Heroku app (e.g. publab-agent-staging)
#   env_file  – Path to the .env file whose variables will be pushed
#               to Heroku config vars (e.g. .test.env, .prod.env)
#
# Prerequisites:
#   - Heroku CLI installed and authenticated (`heroku auth:whoami`)
#   - Git repo initialised in the project root
#######################################################################

APP_NAME="${1:-}"
ENV_FILE="${2:-}"

# ── Validation ───────────────────────────────────────────────────────
if [[ -z "$APP_NAME" || -z "$ENV_FILE" ]]; then
  echo "Usage: $0 <app_name> <env_file>"
  echo ""
  echo "  app_name  – Heroku app name to create"
  echo "  env_file  – Path to env file (e.g. .test.env)"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌  Env file not found: $ENV_FILE"
  exit 1
fi

# Ensure Heroku CLI is available
if ! command -v heroku &>/dev/null; then
  echo "❌  Heroku CLI is not installed. Install it first: https://devcenter.heroku.com/articles/heroku-cli"
  exit 1
fi

# Ensure user is logged in
if ! heroku auth:whoami &>/dev/null; then
  echo "❌  Not logged in to Heroku. Run 'heroku login' first."
  exit 1
fi

# ── Create the app ───────────────────────────────────────────────────
echo "🚀  Creating Heroku app: $APP_NAME ..."
heroku create "$APP_NAME"

# ── Set config vars from env file ────────────────────────────────────
echo "🔧  Setting config vars from $ENV_FILE ..."

# Read env file, skip blank lines and comments, strip trailing whitespace
# and backslash continuations, then push each var to Heroku.
config_args=()
while IFS= read -r line || [[ -n "$line" ]]; do
  # Trim leading/trailing whitespace
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Skip empty lines and comments
  [[ -z "$line" || "$line" == \#* ]] && continue

  # Strip trailing backslash (continuation char used in some env files)
  line="${line%\\}"
  line="$(echo "$line" | sed 's/[[:space:]]*$//')"

  config_args+=("$line")
done < "$ENV_FILE"

if [[ ${#config_args[@]} -gt 0 ]]; then
  heroku config:set --app "$APP_NAME" "${config_args[@]}"
  echo "✅  ${#config_args[@]} config var(s) set."
else
  echo "⚠️   No config vars found in $ENV_FILE"
fi

# ── Set the Heroku remote ───────────────────────────────────────────
# heroku create already adds a remote named "heroku".
# If you need a named remote per-app, uncomment the line below:
# heroku git:remote --app "$APP_NAME" --remote "$APP_NAME"

# ── Deploy ───────────────────────────────────────────────────────────
echo "📦  Deploying to Heroku ..."
git push heroku main || git push heroku master

# ── Post-deploy info ─────────────────────────────────────────────────
echo ""
echo "✅  App deployed successfully!"
echo "   URL  : https://$APP_NAME.herokuapp.com"
echo "   Logs : heroku logs --tail --app $APP_NAME"
echo "   Open : heroku open --app $APP_NAME"

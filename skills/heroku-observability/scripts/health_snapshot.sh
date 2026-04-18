#!/usr/bin/env bash

# health_snapshot.sh — one-shot Heroku app health overview

# Usage: health_snapshot.sh -a <app>

set -euo pipefail

APP=””
while getopts “a:” opt; do
case $opt in
a) APP=”$OPTARG” ;;
*) echo “Usage: $0 -a <app>” >&2; exit 2 ;;
esac
done
[[ -z “$APP” ]] && { echo “Usage: $0 -a <app>” >&2; exit 2; }

echo “=== app: $APP ===”
heroku apps:info -a “$APP” | sed -n ‘1,12p’
echo
echo “— dynos —”
heroku ps -a “$APP” || true
echo
echo “— last 5 releases —”
heroku releases -a “$APP” -n 5 || true
echo
echo “— add-ons —”
heroku addons -a “$APP” || true
echo
echo “— error codes in last 1500 log lines —”
heroku logs -a “$APP” -n 1500 –source heroku 2>/dev/null   
| grep -Eo ‘code=[HRL][0-9]+’   
| sort | uniq -c | sort -rn || echo “(none)”
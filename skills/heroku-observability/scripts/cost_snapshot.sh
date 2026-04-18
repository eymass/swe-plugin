#!/usr/bin/env bash

# cost_snapshot.sh — dyno formation + add-on plan list

# Note: Heroku does not expose exact billing via CLI. This is formation + plans;

# cross-reference dashboard.heroku.com/account/billing for actuals.

# Usage: cost_snapshot.sh -a <app>

set -euo pipefail

APP=””
while getopts “a:” opt; do
case $opt in
a) APP=”$OPTARG” ;;
*) echo “Usage: $0 -a <app>” >&2; exit 2 ;;
esac
done
[[ -z “$APP” ]] && { echo “Usage: $0 -a <app>” >&2; exit 2; }

echo “=== dyno formation ===”
heroku ps -a “$APP” –json 2>/dev/null   
| jq -r ’
group_by(.type + “|” + .size) |
map({type:.[0].type, size:.[0].size, count:length}) |
.[] | “(.count)x (.type) @ (.size)”
’ || heroku ps -a “$APP”

echo
echo “=== add-ons + plans ===”
heroku addons -a “$APP” –json 2>/dev/null   
| jq -r ‘.[] | “(.plan.name)\t(.name)”’   
| column -t -s $’\t’ || heroku addons -a “$APP”

echo
echo “=== recent ps:scale changes (from releases) ===”
heroku releases -a “$APP” –json 2>/dev/null   
| jq -r ‘sort_by(.version) | reverse | .[0:20] | .[] | select(.description | test(“Scale to|resize”; “i”)) | “v(.version)\t(.created_at)\t(.user.email // “?”)\t(.description)”’   
| column -t -s $’\t’ || echo “(no scale events in last 20 releases)”

echo
echo “Cross-reference:”
echo “  Actuals: https://dashboard.heroku.com/account/billing”
echo “  Pricing: https://www.heroku.com/pricing”
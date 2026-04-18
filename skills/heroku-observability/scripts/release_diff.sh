#!/usr/bin/env bash

# release_diff.sh — show a release vs the prior one (author, time, description)

# Usage: release_diff.sh -a <app> [-n <version>]   (default: latest)

set -euo pipefail

APP=””
VERSION=””
while getopts “a:n:” opt; do
case $opt in
a) APP=”$OPTARG” ;;
n) VERSION=”$OPTARG” ;;
*) echo “Usage: $0 -a <app> [-n <version>]” >&2; exit 2 ;;
esac
done
[[ -z “$APP” ]] && { echo “Usage: $0 -a <app> [-n <version>]” >&2; exit 2; }

if [[ -z “$VERSION” ]]; then
VERSION=”$(heroku releases -a “$APP” –json | jq -r ‘sort_by(.version) | last | .version’)”
fi
PREV=$((VERSION - 1))

echo “=== v$VERSION (current) ===”
heroku releases:info “v$VERSION” -a “$APP” | sed -n ‘1,20p’
echo
echo “=== v$PREV (prior) ===”
heroku releases:info “v$PREV” -a “$APP” 2>/dev/null | sed -n ‘1,20p’ || echo “(no prior release)”
echo
echo “=== elapsed between releases ===”
heroku releases -a “$APP” –json   
| jq -r –argjson v “$VERSION” –argjson p “$PREV” ’
map(select(.version==$v or .version==$p))
| sort_by(.version)
| if length==2 then
“v(.[0].version) (.[0].created_at)  →  v(.[1].version) (.[1].created_at)”
else “prior release not available” end
’
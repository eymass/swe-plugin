#!/usr/bin/env bash

# error_scan.sh — grouped error signatures from recent logs

# Usage: error_scan.sh -a <app> [-n <lines>]   (default 1500)

set -euo pipefail

APP=””
LINES=1500
while getopts “a:n:” opt; do
case $opt in
a) APP=”$OPTARG” ;;
n) LINES=”$OPTARG” ;;
*) echo “Usage: $0 -a <app> [-n <lines>]” >&2; exit 2 ;;
esac
done
[[ -z “$APP” ]] && { echo “Usage: $0 -a <app> [-n <lines>]” >&2; exit 2; }

TMP=”$(mktemp)”; trap “rm -f $TMP” EXIT
heroku logs -a “$APP” -n “$LINES” > “$TMP”

echo “=== platform error codes (H/R/L) ===”
grep -Eo ‘code=[HRL][0-9]+’ “$TMP” | sort | uniq -c | sort -rn || echo “(none)”
echo
echo “=== 5xx responses ===”
grep -Eo ‘status=5[0-9]{2}’ “$TMP” | sort | uniq -c | sort -rn || echo “(none)”
echo
echo “=== top 10 exception signatures (IDs/numbers normalized) ===”
grep -iE ‘(error|exception|traceback|panic|fatal)’ “$TMP”   
| sed -E ‘s/^[^ ]+ [^ ]+ //; s/[0-9a-f]{16,}/<hash>/g; s/\b[0-9]+\b/<n>/g’   
| sort | uniq -c | sort -rn | head -10 || echo “(none)”
echo
echo “=== dynos seen in log window ===”
grep -Eo ‘dyno=[^ ]+’ “$TMP” | sort -u || echo “(none)”
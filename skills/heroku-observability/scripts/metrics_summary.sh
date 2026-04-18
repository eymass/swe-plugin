#!/usr/bin/env bash

# metrics_summary.sh — latency + memory + throughput from recent logs

# Prereq: heroku labs:enable runtime-metrics -a <app>  (for memory samples)

# Usage: metrics_summary.sh -a <app> [-n <lines>]   (default 3000)

set -euo pipefail

APP=””
LINES=3000
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

echo “=== router service time (app processing) ===”
grep -Eo ‘service=[0-9]+ms’ “$TMP” | sed ‘s/[^0-9]//g’ | sort -n   
| awk ‘{a[NR]=$1; s+=$1} END{
if(NR==0){print “(no router samples)”; exit}
p50=a[int(NR*0.5)]; p95=a[int(NR*0.95)]; p99=a[int(NR*0.99)];
printf “n=%d avg=%.0fms p50=%sms p95=%sms p99=%sms\n”, NR, s/NR, p50, p95, p99
}’

echo
echo “=== router connect time (queue) ===”
grep -Eo ‘connect=[0-9]+ms’ “$TMP” | sed ‘s/[^0-9]//g’ | sort -n   
| awk ‘{a[NR]=$1; s+=$1} END{
if(NR==0){print “(none)”; exit}
p95=a[int(NR*0.95)]; p99=a[int(NR*0.99)];
printf “n=%d avg=%.0fms p95=%sms p99=%sms\n”, NR, s/NR, p95, p99
}’

echo
echo “=== memory_total per dyno (most recent samples) ===”
grep -E ‘sample#memory_total’ “$TMP”   
| grep -Eo ‘source=[^ ]+ dyno=heroku.[^ ]+ sample#memory_total=[0-9.]+[A-Za-z]+’   
| tail -20   
| sort -u || echo “(no runtime-metrics — enable: heroku labs:enable runtime-metrics -a $APP)”

echo
echo “=== load_avg_1m per dyno (most recent) ===”
grep -Eo ‘dyno=heroku.[^ ]+ sample#load_avg_1m=[0-9.]+’ “$TMP” | tail -10 | sort -u || echo “(none)”

echo
echo “=== throughput ===”
REQS=$(grep -c ‘method=’ “$TMP” || echo 0)
echo “$REQS requests in last $LINES log lines”

echo
echo “=== status code distribution ===”
grep -Eo ‘status=[0-9]{3}’ “$TMP” | sort | uniq -c | sort -rn || echo “(none)”
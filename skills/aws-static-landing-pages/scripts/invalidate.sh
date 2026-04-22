#!/usr/bin/env bash
#
# invalidate.sh — Smart CloudFront invalidation helper.
#
# By default, invalidates HTML paths only (hashed assets don't need invalidation).
# Use --all only in true emergencies.
#
# Usage:
#   ./invalidate.sh --dist <dist-id>                 # HTML only (default)
#   ./invalidate.sh --dist <dist-id> --paths "/..."  # custom paths
#   ./invalidate.sh --dist <dist-id> --all           # /* — costs money at scale
#

set -euo pipefail

DIST_ID=""
PATHS=("/*.html" "/" "/index.html")
ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist)  DIST_ID="$2"; shift 2 ;;
    --paths) shift; PATHS=(); while [[ $# -gt 0 && "$1" != --* ]]; do PATHS+=("$1"); shift; done ;;
    --all)   ALL=true; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 --dist <dist-id> [--paths "/path1" "/path2" ...] [--all]
  Default: invalidates HTML paths only ('/', '/index.html', '/*.html')
  --all:   invalidates '/*' (expensive at scale — avoid in normal operation)
EOF
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$DIST_ID" ]] && { echo "ERROR: --dist required" >&2; exit 1; }

if $ALL; then
  PATHS=("/*")
  echo "WARNING: invalidating /* — costs after the first 1000 paths/month."
  read -rp "Continue? [y/N] " ans
  [[ "$ans" != "y" && "$ans" != "Y" ]] && exit 0
fi

echo "==> Invalidating ${PATHS[*]} on $DIST_ID..."

INV_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "${PATHS[@]}" \
  --query 'Invalidation.Id' \
  --output text)

echo "    Invalidation: $INV_ID"
echo "    Waiting for completion..."

aws cloudfront wait invalidation-completed \
  --distribution-id "$DIST_ID" \
  --id "$INV_ID"

echo "==> Done."

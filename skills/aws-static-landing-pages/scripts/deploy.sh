#!/usr/bin/env bash
#
# deploy.sh — Deploy a static landing page to S3 + CloudFront.
#
# Usage:
#   ./deploy.sh --bucket <bucket> --dist <distribution-id> --dir <build-dir> [--dry-run]
#
# What it does:
#   1. Uploads hashed assets (everything except *.html) with Cache-Control: immutable, 1y
#   2. Uploads HTML with Cache-Control: s-maxage=60, must-revalidate, no browser cache
#   3. Invalidates ONLY the HTML paths (hashed assets never need invalidation)
#   4. Waits for the invalidation to complete and prints TTFB verification
#
# Safety:
#   - --dry-run flag shows what would happen without making changes
#   - Refuses to run if the build dir is empty or missing index.html
#   - Greps the build for common secret patterns and aborts on match
#

set -euo pipefail

BUCKET=""
DIST_ID=""
BUILD_DIR=""
DRY_RUN=false
DOMAIN=""  # optional, for post-deploy TTFB check

usage() {
  cat <<EOF
Usage: $0 --bucket <bucket> --dist <dist-id> --dir <build-dir> [--domain <domain>] [--dry-run]

  --bucket   S3 bucket name (required)
  --dist     CloudFront distribution ID (required)
  --dir      Path to built site (required), must contain index.html
  --domain   Domain for post-deploy TTFB check (optional)
  --dry-run  Show what would happen, don't do it
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket) BUCKET="$2"; shift 2 ;;
    --dist)   DIST_ID="$2"; shift 2 ;;
    --dir)    BUILD_DIR="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -z "$BUCKET" || -z "$DIST_ID" || -z "$BUILD_DIR" ]] && usage

# ---- sanity checks ----

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "ERROR: build dir '$BUILD_DIR' does not exist" >&2
  exit 2
fi

if [[ ! -f "$BUILD_DIR/index.html" ]]; then
  echo "ERROR: '$BUILD_DIR/index.html' not found — is this really a built site?" >&2
  exit 2
fi

# Secret scan — quick, not exhaustive. For real scanning, use trufflehog or gitleaks in CI.
SECRET_PATTERNS='(sk_live_|rk_live_|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36}|gho_[0-9A-Za-z]{36}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'
if grep -rEq "$SECRET_PATTERNS" "$BUILD_DIR" 2>/dev/null; then
  echo "ERROR: possible secret found in build. Aborting." >&2
  grep -rnE "$SECRET_PATTERNS" "$BUILD_DIR" | head -n 5 >&2
  exit 3
fi

# Mixed-content scan
if grep -rE 'src="http://|href="http://' "$BUILD_DIR" 2>/dev/null | grep -v 'http://www.w3.org' > /tmp/mixed.txt; then
  if [[ -s /tmp/mixed.txt ]]; then
    echo "WARNING: http:// references found (mixed content risk):"
    head -n 10 /tmp/mixed.txt
    read -rp "Continue anyway? [y/N] " ans
    [[ "$ans" != "y" && "$ans" != "Y" ]] && exit 4
  fi
fi

echo "==> Deploying $BUILD_DIR → s3://$BUCKET (dist: $DIST_ID)"
$DRY_RUN && echo "    (DRY RUN — no changes will be made)"

DRY_FLAG=""
$DRY_RUN && DRY_FLAG="--dryrun"

# ---- upload hashed assets (everything except HTML) ----

echo "==> Step 1/3: Uploading hashed assets with immutable cache..."
aws s3 sync "$BUILD_DIR" "s3://$BUCKET/" \
  --exclude "*.html" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete \
  $DRY_FLAG

# ---- upload HTML ----

echo "==> Step 2/3: Uploading HTML with short edge TTL..."
aws s3 sync "$BUILD_DIR" "s3://$BUCKET/" \
  --exclude "*" --include "*.html" \
  --cache-control "public, max-age=0, s-maxage=60, must-revalidate" \
  --content-type "text/html; charset=utf-8" \
  --delete \
  $DRY_FLAG

# ---- invalidate HTML only ----

if ! $DRY_RUN; then
  echo "==> Step 3/3: Invalidating HTML paths on CloudFront..."
  INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "$DIST_ID" \
    --paths "/" "/index.html" "/*.html" \
    --query 'Invalidation.Id' \
    --output text)
  echo "    Invalidation ID: $INVALIDATION_ID"

  # Wait (optional — comment out if you want to return immediately)
  echo "    Waiting for invalidation to complete (~1-3 min)..."
  aws cloudfront wait invalidation-completed \
    --distribution-id "$DIST_ID" \
    --id "$INVALIDATION_ID"
  echo "    Invalidation complete."
else
  echo "==> Step 3/3: (DRY RUN — would invalidate /, /index.html, /*.html)"
fi

# ---- post-deploy verification ----

if [[ -n "$DOMAIN" ]] && ! $DRY_RUN; then
  echo "==> Verifying https://$DOMAIN/ ..."
  curl -o /dev/null -sS -w "    HTTP: %{http_code}  TTFB: %{time_starttransfer}s  Total: %{time_total}s  Protocol: %{http_version}\n" "https://$DOMAIN/"

  echo "==> Response headers:"
  curl -sSI "https://$DOMAIN/" | grep -iE "^(cache-control|content-type|strict-transport|x-cache|x-content-type|server|content-encoding):"
fi

echo "==> Done."

#!/usr/bin/env bash
#
# s3-provision.sh — Provision a public S3 website bucket and sync landing page files.
#
# Usage:
#   ./s3-provision.sh --bucket <bucket> --dir <source-dir> [--region <region>] [--name <lp-name>]
#
# What it does:
#   1. Creates the S3 bucket if it does not exist
#   2. Removes all public access block settings
#   3. Applies a bucket policy allowing public s3:GetObject (website reads)
#   4. Configures static website hosting (index.html as index + error document)
#   5. Syncs all files from <source-dir> to the bucket root
#   6. Prints the S3 website endpoint URL
#   7. Fetches the endpoint and reports HTTP status
#
# Requirements:
#   - AWS CLI v2 installed and configured (profile or instance role)
#   - IAM permissions: s3:CreateBucket, s3:PutPublicAccessBlock, s3:PutBucketPolicy,
#                       s3:PutBucketWebsite, s3:PutObject, s3:ListBucket
#
# Exit codes:
#   0  — success, website is live
#   1  — missing required arguments
#   2  — source directory missing or no index.html found
#   3  — bucket creation failed (not an "already exists" error)
#   4  — public access block removal failed
#   5  — bucket policy application failed
#   6  — website hosting configuration failed
#   7  — file sync failed
#   8  — endpoint verification returned non-200 status
#

set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────────────

BUCKET=""
SOURCE_DIR=""
REGION="us-east-1"
LP_NAME="lp"

# ── helpers ──────────────────────────────────────────────────────────────────

log() { echo "[s3-provision] $*"; }
err() { echo "[s3-provision] ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: $0 --bucket <bucket> --dir <source-dir> [--region <region>] [--name <lp-name>]

  --bucket   S3 bucket name (required, must be globally unique)
  --dir      Local directory to sync (required, must contain index.html)
  --region   AWS region (default: us-east-1)
  --name     LP name for log labels (default: lp)
EOF
  exit 1
}

# ── argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)  BUCKET="$2";     shift 2 ;;
    --dir)     SOURCE_DIR="$2"; shift 2 ;;
    --region)  REGION="$2";     shift 2 ;;
    --name)    LP_NAME="$2";    shift 2 ;;
    -h|--help) usage ;;
    *) err "Unknown argument: $1"; usage ;;
  esac
done

[[ -z "$BUCKET"     ]] && { err "--bucket is required"; usage; }
[[ -z "$SOURCE_DIR" ]] && { err "--dir is required";    usage; }

# ── pre-flight checks ────────────────────────────────────────────────────────

if [[ ! -d "$SOURCE_DIR" ]]; then
  err "Source directory '$SOURCE_DIR' does not exist."
  exit 2
fi

if [[ ! -f "$SOURCE_DIR/index.html" ]]; then
  err "No index.html found in '$SOURCE_DIR'. Build the landing page before running this script."
  exit 2
fi

log "Starting provisioning for LP: $LP_NAME"
log "Bucket: $BUCKET | Region: $REGION | Source: $SOURCE_DIR"

# ── step 1: create bucket ────────────────────────────────────────────────────

log "Checking bucket: $BUCKET ($REGION)"

BUCKET_EXISTS=false
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
  BUCKET_EXISTS=true
  log "Bucket already exists — skipping creation."
else
  log "Bucket does not exist — creating..."

  CREATE_ARGS=(--bucket "$BUCKET" --region "$REGION")
  # us-east-1 does not accept LocationConstraint
  if [[ "$REGION" != "us-east-1" ]]; then
    CREATE_ARGS+=(--create-bucket-configuration "LocationConstraint=$REGION")
  fi

  if ! aws s3api create-bucket "${CREATE_ARGS[@]}" 2>&1; then
    err "Bucket creation failed."
    exit 3
  fi
  log "Bucket created."
fi

# ── step 2: remove public access block ──────────────────────────────────────

log "Removing public access block..."
if ! aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" 2>&1; then
  err "Failed to remove public access block."
  exit 4
fi
log "Public access block removed."

# ── step 3: apply public read bucket policy ──────────────────────────────────

log "Applying public read bucket policy..."

PUBLIC_POLICY=$(cat <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
POLICY
)

if ! aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --policy "$PUBLIC_POLICY" 2>&1; then
  err "Failed to apply bucket policy."
  exit 5
fi
log "Public read policy applied."

# ── step 4: configure static website hosting ────────────────────────────────

log "Configuring static website hosting (index: index.html, error: index.html)..."
if ! aws s3api put-bucket-website \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --website-configuration '{
    "IndexDocument": {"Suffix": "index.html"},
    "ErrorDocument": {"Key": "index.html"}
  }' 2>&1; then
  err "Failed to configure website hosting."
  exit 6
fi
log "Static website hosting configured."

# ── step 5: sync files ───────────────────────────────────────────────────────

log "Syncing files from $SOURCE_DIR → s3://$BUCKET/"

if ! aws s3 sync "$SOURCE_DIR" "s3://$BUCKET/" \
  --region "$REGION" \
  --delete \
  --exclude ".DS_Store" \
  --exclude "*.map" 2>&1; then
  err "File sync failed."
  exit 7
fi
log "Sync complete."

# ── step 6: print endpoint ───────────────────────────────────────────────────

# S3 website endpoints differ by region format
if [[ "$REGION" == "us-east-1" ]]; then
  ENDPOINT="http://${BUCKET}.s3-website-${REGION}.amazonaws.com"
else
  ENDPOINT="http://${BUCKET}.s3-website.${REGION}.amazonaws.com"
fi

log "Website endpoint: $ENDPOINT"

# ── step 7: verify endpoint ──────────────────────────────────────────────────

log "Verifying endpoint (allowing 15s for policy propagation)..."
sleep 5

HTTP_STATUS=$(curl -o /dev/null -sS -w "%{http_code}" --max-time 10 "$ENDPOINT" 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "200" ]]; then
  log "HTTP $HTTP_STATUS OK — website is live."
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log " LP:       $LP_NAME"
  log " Bucket:   $BUCKET"
  log " Region:   $REGION"
  log " Endpoint: $ENDPOINT"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  err "Endpoint returned HTTP $HTTP_STATUS. Check bucket policy propagation or file sync."
  log "Endpoint: $ENDPOINT"
  log "Tip: policy changes can take up to 60 seconds to propagate. Try fetching manually:"
  log "  curl -I $ENDPOINT"
  exit 8
fi

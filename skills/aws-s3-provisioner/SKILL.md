---
name: aws-s3-provisioner
description: "S3 public website provisioner for landing pages. Use when deploying a landing page to a public S3 website bucket — handles bucket creation, public access configuration, website hosting setup, file sync, and endpoint verification. Trigger on: 'upload to S3', 'create S3 bucket for LP', 'sync landing page files to S3', 'provision S3 website', or as Step 3 of the landing-page pipeline after static files are built. Does NOT set up CloudFront — that is handled by the aws-cloudfront-domain agent."
---

# AWS S3 Website Provisioner

You are provisioning a public S3 static website bucket for a landing page. This is the direct S3 website hosting pattern — simple, fast, no CloudFront in this step. CloudFront is wired in the next pipeline step by `aws-cloudfront-domain`.

This skill operates **exclusively via the predefined script** at `skills/aws-s3-provisioner/scripts/s3-provision.sh`. Do not construct raw AWS CLI commands. Call the script with the correct arguments.

---

## When to Use This Skill

| Trigger | Notes |
|---|---|
| New LP deployment, no existing bucket | Script creates bucket + configures everything |
| Existing LP update, bucket already exists | Script skips creation, syncs files only |
| Re-provisioning after policy reset | Script is idempotent — safe to re-run |

**Do NOT use this skill for:**
- Private S3 buckets behind CloudFront OAC (use `aws-static-landing-pages` instead)
- Non-landing-page workloads (app builds, data pipelines, etc.)

---

## Required Inputs

Collect these before running the script:

| Input | Flag | Example |
|---|---|---|
| Bucket name | `--bucket` | `lp-acme-sale-2026` |
| Source directory | `--dir` | `./dist` or `/lpname/` |
| AWS region | `--region` | `us-east-1` (default) |
| LP name (for logs) | `--name` | `acme-sale` |

**Bucket naming rules:**
- Lowercase letters, numbers, hyphens only
- 3–63 characters
- Must be globally unique across all AWS accounts
- Convention: `lp-<brand>-<campaign>-<env>` (e.g., `lp-acme-sale-prod`)

---

## What the Script Does

The script at `scripts/s3-provision.sh` executes these steps in order:

1. **Create bucket** (skips if already exists)
2. **Remove public access block** — clears all four PublicAccessBlock settings
3. **Apply bucket ACL + website policy** — grants `s3:GetObject` to `*` for website reads
4. **Configure static website hosting** — sets `index.html` as both index and error document
5. **Sync all files** from source directory to bucket root
6. **Print S3 website endpoint** — format: `http://<bucket>.s3-website-<region>.amazonaws.com`
7. **Verify endpoint** — HTTP GET to the website URL, reports status code

---

## Invocation

```bash
bash skills/aws-s3-provisioner/scripts/s3-provision.sh \
  --bucket lp-acme-sale-prod \
  --dir ./dist \
  --region us-east-1 \
  --name acme-sale
```

The script is idempotent. Re-running it on an existing bucket skips creation and re-syncs files.

---

## Expected Output

```
[s3-provision] Checking bucket: lp-acme-sale-prod (us-east-1)
[s3-provision] Bucket does not exist — creating...
[s3-provision] Bucket created.
[s3-provision] Removing public access block...
[s3-provision] Applying public read bucket policy...
[s3-provision] Configuring static website hosting (index: index.html, error: index.html)...
[s3-provision] Syncing files from ./dist → s3://lp-acme-sale-prod/
[s3-provision]   upload: dist/index.html
[s3-provision]   upload: dist/styles.css
[s3-provision]   upload: dist/main.js
[s3-provision] Sync complete.
[s3-provision] Website endpoint: http://lp-acme-sale-prod.s3-website-us-east-1.amazonaws.com
[s3-provision] Verifying endpoint...
[s3-provision] HTTP 200 OK — website is live.
```

---

## Gate: Proceed to CloudFront Step

After the script exits 0 and reports HTTP 200, hand the following to `aws-cloudfront-domain`:

- S3 bucket name
- S3 website endpoint URL
- LP name
- Target domain name

If the script exits non-zero or reports a non-200 status, **stop and report the error**. Do not proceed to the CloudFront step with a broken origin.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `BucketAlreadyOwnedByYou` | Bucket exists in your account | Script handles this — continues |
| `BucketAlreadyExists` | Name taken by another account | Choose a different bucket name |
| `AccessDenied` on policy put | IAM user lacks `s3:PutBucketPolicy` | Add permission or use a role with it |
| HTTP 403 after provision | Policy propagation delay | Wait 10–15s and retry the verify step |
| HTTP 404 on index | `index.html` missing from source dir | Verify build output before running script |
| `NoSuchBucket` on sync | Region mismatch | Pass `--region` matching the bucket's region |

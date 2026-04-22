# Security Checklist — Production Landing Pages

Non-negotiables for anything taking paid-ad traffic. Ad networks increasingly scan landing pages for mixed-content, missing HSTS, weak TLS, exposed secrets — failing any of these can pause an ad account.

## Bucket-level

- [ ] **Bucket is private** — `BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, `RestrictPublicAcls` all `true`.
- [ ] **Never use S3 website endpoint** — use the REST endpoint via CloudFront + OAC.
- [ ] **Versioning enabled** — allows rollback if a deploy ships a bad artifact.
- [ ] **Server-side encryption** (`AES256` or `aws:kms`) — AES256 is sufficient for public static content; KMS only if compliance demands it.
- [ ] **Bucket policy restricts to the CloudFront distribution** via `AWS:SourceArn` condition (see SKILL.md step 7).
- [ ] **Lifecycle rule** deletes noncurrent versions after 30 days.
- [ ] **Bucket access logging** to a separate log bucket.

## TLS / certificate

- [ ] **ACM certificate in `us-east-1`** (mandatory for CloudFront, regardless of origin region).
- [ ] **DNS-validated**, not email-validated.
- [ ] **Subject Alternative Names** cover apex + `www` + any planned subdomains.
- [ ] **Auto-renewal** enabled (ACM default).
- [ ] `MinimumProtocolVersion: TLSv1.2_2021` — disables TLSv1.0 and 1.1 and weak ciphers.
- [ ] `SSLSupportMethod: sni-only` — dedicated IP is expensive and unnecessary.

## CloudFront

- [ ] `ViewerProtocolPolicy: redirect-to-https` on every behavior.
- [ ] `HttpVersion: http2and3`.
- [ ] `IsIPV6Enabled: true`.
- [ ] **Origin Access Control (OAC)**, not OAI (OAI is legacy).
- [ ] `AllowedMethods` restricted to `GET, HEAD` (and `OPTIONS` only if CORS required).
- [ ] **Compression enabled** (`Compress: true`).
- [ ] **Access logging enabled** to a dedicated log bucket (standard or real-time).
- [ ] **Custom error responses** for 403/404 → `/404.html` (don't leak S3 XML error pages).

## Response headers policy

Attach the AWS-managed `SecurityHeadersPolicy` (id `67f7725c-6f97-4210-82d7-5512b31e9d03`) as a baseline, then a custom policy on top for CSP and any overrides.

Headers every landing page should send:

| Header                         | Value                                                                 | Notes                                        |
| ------------------------------ | --------------------------------------------------------------------- | -------------------------------------------- |
| `Strict-Transport-Security`    | `max-age=63072000; includeSubDomains; preload`                        | Preload only after all subdomains are HTTPS  |
| `X-Content-Type-Options`       | `nosniff`                                                             |                                              |
| `X-Frame-Options`              | `DENY`                                                                | Or use `frame-ancestors` CSP instead         |
| `Referrer-Policy`              | `strict-origin-when-cross-origin`                                     |                                              |
| `Permissions-Policy`           | `camera=(), microphone=(), geolocation=(), interest-cohort=()`        |                                              |
| `Content-Security-Policy`      | see below                                                             | Start with report-only                       |
| `Cross-Origin-Opener-Policy`   | `same-origin`                                                         |                                              |

### Custom response headers policy

```bash
aws cloudfront create-response-headers-policy --response-headers-policy-config '{
  "Name": "LandingSecurityHeaders",
  "Comment": "Production security headers",
  "SecurityHeadersConfig": {
    "StrictTransportSecurity": {
      "AccessControlMaxAgeSec": 63072000,
      "IncludeSubdomains": true,
      "Preload": true,
      "Override": true
    },
    "ContentTypeOptions": { "Override": true },
    "FrameOptions": { "FrameOption": "DENY", "Override": true },
    "ReferrerPolicy": {
      "ReferrerPolicy": "strict-origin-when-cross-origin",
      "Override": true
    },
    "ContentSecurityPolicy": {
      "ContentSecurityPolicy": "default-src '\''self'\''; script-src '\''self'\'' https://connect.facebook.net https://www.googletagmanager.com https://www.google-analytics.com; img-src '\''self'\'' data: https:; style-src '\''self'\'' '\''unsafe-inline'\''; font-src '\''self'\'' data:; connect-src '\''self'\'' https://www.google-analytics.com https://www.facebook.com; frame-ancestors '\''none'\''",
      "Override": true
    }
  },
  "CustomHeadersConfig": {
    "Items": [
      {
        "Header": "Permissions-Policy",
        "Value": "camera=(), microphone=(), geolocation=(), interest-cohort=()",
        "Override": true
      },
      {
        "Header": "Cross-Origin-Opener-Policy",
        "Value": "same-origin",
        "Override": true
      }
    ],
    "Quantity": 2
  }
}'
```

### CSP rollout

1. Start with `Content-Security-Policy-Report-Only` for 1 week.
2. Collect reports via a report-uri (CloudWatch Logs via Lambda, or a hosted service).
3. Tighten the policy based on real violations.
4. Flip to enforcing `Content-Security-Policy`.
5. Keep a report-uri on the enforcing policy for ongoing monitoring.

**`unsafe-inline` in `style-src` is usually necessary** for critical-CSS inlining. Avoid `unsafe-inline` in `script-src` — use nonces or hashes.

**`unsafe-eval` should never be needed** for a static landing page. If your framework wants it, reconsider the framework.

## WAF

Attach AWS WAF to the distribution for any page with a form or any traffic of note.

Minimum rule set:

- **AWS-managed Core Rule Set** (CRS) — blocks OWASP Top 10 patterns
- **AWS-managed Known Bad Inputs** — blocks known exploit attempts
- **AWS-managed Bot Control** (optional, paid) — if scraping / credential stuffing is a concern
- **Rate-based rule** — 2000 requests / 5 min per IP is a reasonable ceiling for a landing page

```bash
# Create a web ACL (abbreviated — full config via aws wafv2 create-web-acl)
aws wafv2 create-web-acl \
  --name landing-waf-prod \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --default-action Allow={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=landing-waf \
  --rules file://waf-rules.json
```

Associate it with the distribution via the `WebACLId` field in the distribution config.

## Secrets hygiene

Before uploading the build, scan for leaked secrets:

```bash
# Quick grep for common patterns
grep -rnE "(sk_live|rk_live|AKIA|ghp_|gho_|BEGIN RSA|password|api[_-]?key)" ./dist/ && echo "LEAK FOUND" && exit 1

# Or use a real scanner
trufflehog filesystem ./dist/
gitleaks detect --source ./dist/ --no-git
```

Never commit AWS credentials, third-party API keys, internal URLs, or customer data in the built bundle. Every JS file ends up public.

## Logging and monitoring

- [ ] **CloudFront access logs** → S3 log bucket
- [ ] **CloudFront real-time logs** (optional) → Kinesis → Athena for live queries
- [ ] **CloudTrail** enabled at the account level (organization trail preferred)
- [ ] **S3 access logs** on content bucket and log bucket
- [ ] **CloudWatch alarms** on 5xx rate, cache hit rate, origin latency (see performance.md)
- [ ] **GuardDuty** enabled at the account level
- [ ] **AWS Config** rules: `cloudfront-origin-access-identity-enabled` (or the OAC equivalent), `s3-bucket-public-read-prohibited`, `s3-bucket-ssl-requests-only`

## Account / IAM

- [ ] **Separate AWS accounts** for dev / staging / prod (via AWS Organizations)
- [ ] **Least-privilege CI role** — only `s3:PutObject`, `s3:DeleteObject` on the specific bucket, `cloudfront:CreateInvalidation` on the specific distribution
- [ ] **No root-account keys** — disabled at creation, MFA on root, SCP enforcing this
- [ ] **IAM Identity Center (SSO)** for human access, not IAM users
- [ ] **Access Analyzer** enabled to flag unintended public resources

Example CI role trust + permission:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::landing-acme-main-prod",
        "arn:aws:s3:::landing-acme-main-prod/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation"],
      "Resource": "arn:aws:cloudfront::<ACCOUNT>:distribution/<DIST_ID>"
    }
  ]
}
```

## Pre-launch checklist

Run through this before the ad campaign goes live:

- [ ] `curl -sSI https://<domain>/` returns 200, HTTP/2 or HTTP/3, all security headers present
- [ ] `curl -sSI http://<domain>/` returns 301 → HTTPS
- [ ] SSL Labs (`https://www.ssllabs.com/ssltest/`) — A or A+ rating
- [ ] Mozilla Observatory (`https://observatory.mozilla.org/`) — A or better
- [ ] Lighthouse mobile — Performance ≥ 90, Accessibility ≥ 90, SEO ≥ 90, Best Practices ≥ 95
- [ ] WebPageTest from target geo, 4G profile — TTFB < 400ms, LCP < 2.5s
- [ ] All third-party tags firing correctly (Meta Pixel, TikTok, GA4)
- [ ] 404 page returns 404 (not 200) and is branded
- [ ] WAF in place with Core Rule Set + rate-based rule
- [ ] CloudWatch alarms configured and routed to an on-call
- [ ] Rollback plan: previous S3 version known, invalidation command ready

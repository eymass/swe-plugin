---
name: aws-static-landing-pages
description: Production-grade deployment of static landing pages and single-page apps to AWS using S3 + CloudFront, with silent multi-variant routing (one domain serving multiple pages based on IP, geo, cookie, UTM, or A/B bucket — invisible to the client), and performance tuning for paid-social traffic. Use whenever the user mentions deploying a landing page, static site, or SPA to AWS; hosting on S3; setting up or editing a CloudFront distribution, cache behaviors, response headers policy, CloudFront Functions, or Lambda@Edge; serving multiple versions of a page under one domain; A/B testing at the edge; geo-routing or IP-based routing; TTFB optimization; cache invalidation; or making a landing page "ready for Meta/TikTok/Google Ads traffic." Also trigger on phrases like "deploy this to AWS," "put this behind CloudFront," "same domain, different page," "split traffic at the edge," or "make this fast for paid ads." Do not trigger for dynamic backend services (ECS/EKS/Lambda APIs), Amplify-managed flows, or non-AWS CDNs.
---

# AWS Static Landing Pages — Production Deployment Skill

You are deploying landing pages used in **paid social campaigns** (Meta, TikTok, Google, LinkedIn). Every 100ms of TTFB costs conversion rate. The user treats this as an enterprise workload: global reach, mobile-first, all major browsers, zero-downtime changes, and silent server-side routing where multiple "pages" share one domain without the client ever seeing a redirect.

This skill encodes how a senior AWS architect actually ships these. Follow the decision flow, use the commands verbatim (substituting identifiers), and escalate to the reference files when the situation demands depth.

---

## Mental model — the four layers

Every production landing-page stack on AWS is exactly these four layers. Don't invent new ones; don't skip any.

1. **Origin** — S3 bucket(s) holding the built HTML/CSS/JS/images. Use **REST endpoint** + **Origin Access Control (OAC)**, never the public S3 website endpoint. Website endpoints expose HTTP-only, leak the bucket, and block OAC.
2. **CDN** — a single CloudFront distribution fronts all origins. CloudFront is where routing, caching, compression, security headers, TLS, and observability live.
3. **Edge logic** — CloudFront Functions (viewer request / viewer response, ~sub-ms, free tier generous) for lightweight routing and header work; Lambda@Edge (viewer/origin request/response, full Node runtime) only when CF Functions can't do it.
4. **DNS + TLS** — Route 53 alias record to the distribution; ACM certificate **in us-east-1** (CloudFront requires this region regardless of where your buckets live).

If a requirement doesn't fit one of these layers cleanly, you're probably over-engineering. Challenge it before adding anything else.

---

## Decision flow — pick the right routing strategy

The user will describe a routing need. Match it to exactly one of these patterns. Using the wrong one is the most common source of slow pages and cache-poisoning bugs.

| Need                                                                                | Strategy                                                                                                                           | Why                                                                                                      |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Different URL paths → different S3 buckets (e.g. `/`, `/promo`, `/b2b`)             | **CloudFront cache behaviors** with path patterns + multiple origins                                                               | Built in, zero compute, perfect cache hit ratio. This is the default.                                    |
| Same URL, different HTML based on **country/region**                                | **CloudFront Function (viewer-request) → rewrite `event.request.uri`** + include `CloudFront-Viewer-Country` in cache key          | Country header is free and trusted (CloudFront signs it). Keeps cache partitioned by country.            |
| Same URL, different HTML based on **cookie / UTM / query param** (A/B test, cohort) | **CloudFront Function (viewer-request) → rewrite URI to a variant prefix** + add the bucketing signal to the cache key             | Deterministic URI rewrite = clean cache keys, no double-caching, no redirect flash.                      |
| Same URL, different HTML based on **IP range** (office/allow-list/partner)          | **CloudFront Function** inspecting `event.viewer.ip` + URI rewrite; add a custom header to cache key                               | Client sees same URL, you silently swap origin paths. For large IP lists, ship a CIDR table in-function. |
| Same URL, different HTML based on **device** (mobile vs desktop landing)            | **CloudFront response-headers + `CloudFront-Is-Mobile-Viewer`** routed via viewer-request function                                 | Prefer serving a responsive single page. Only split if the creative team genuinely ships two variants.   |
| Full server-side logic (auth, DB lookups, API fan-out) before picking a page        | **Lambda@Edge (origin-request)** — not this skill's default; treat as an escalation                                                | CF Functions cap at ~10KB, 1ms CPU, no network. Lambda@Edge is the escape hatch.                         |
| Dynamic rendering / SSR                                                             | Not in scope here — this skill is for **static** landing pages. If the user genuinely needs SSR, recommend Next.js on Lambda@Edge, CloudFront + Lambda Function URLs, or Amplify Hosting — and stop. |                                                                                                          |

**Golden rule:** the client must never see a 3xx redirect just because you're A/B testing or geo-routing. Redirects add a round-trip, break mobile ad trackers, and get flagged by paid-social QA tools. Always **rewrite the URI at the edge**, keep the viewer URL unchanged, serve 200 OK with the variant HTML.

---

## Core deployment workflow

Use this 9-step flow for any new landing page. Every step is mandatory. Skipping even one (especially OAC or response-headers policy) is how stacks end up in the "works-on-my-machine / unsafe-in-production" state.

### 1. Build the static bundle

Assume the user has a build already (e.g. `dist/`, `build/`, `out/`). If not, ask once. Validate:

- `index.html` at root
- Hashed asset filenames (`app.a3f9.js`) — required for the immutable cache strategy below
- No absolute `http://` links — breaks HSTS
- Gzip-friendly text assets (no pre-minified-then-base64'd blobs)

### 2. Create the S3 bucket (private, versioned, no website hosting)

```bash
REGION=us-east-1
BUCKET=landing-acme-main-prod

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  $( [ "$REGION" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=$REGION" )

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicAcls=true"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Do **not** enable S3 static website hosting. You're using the REST endpoint.

### 3. Upload with correct Cache-Control (the single biggest perf lever)

Two-tier caching strategy — this is non-negotiable for paid-social pages:

- **HTML** (short-lived, always revalidated): `Cache-Control: public, max-age=0, s-maxage=60, must-revalidate`
- **Hashed assets** (immutable, long-lived): `Cache-Control: public, max-age=31536000, immutable`

```bash
# Hashed assets — set immutable first, then exclude from the HTML pass
aws s3 sync ./dist "s3://$BUCKET/" \
  --exclude "*.html" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete

# HTML — short TTL at viewer, 60s at edge
aws s3 sync ./dist "s3://$BUCKET/" \
  --exclude "*" --include "*.html" \
  --cache-control "public, max-age=0, s-maxage=60, must-revalidate" \
  --content-type "text/html; charset=utf-8" \
  --delete
```

The `s-maxage=60` on HTML means CloudFront serves cached HTML to everyone for 60s but the viewer always revalidates — so a new deploy reaches all users within ~60s without a full invalidation.

### 4. Request an ACM certificate (in us-east-1, always)

```bash
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "www.example.com" "*.example.com" \
  --validation-method DNS \
  --region us-east-1
```

Then add the DNS validation CNAMEs in Route 53. Wait for `ISSUED` before creating the distribution.

### 5. Create an Origin Access Control (OAC)

OAC replaces the legacy Origin Access Identity (OAI). Always OAC for new work.

```bash
aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "oac-landing-acme",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }'
```

### 6. Create the CloudFront distribution

See `references/distribution-config.json` for a complete production-ready distribution config (HTTP/2 + HTTP/3, TLSv1.2_2021, compression on, managed CachingOptimized policy, SecurityHeadersPolicy attached, OAC wired to the S3 origin).

Key settings you must get right:

- **PriceClass**: `PriceClass_All` for global paid-social; `PriceClass_100` (US+EU) if budget-constrained and audience is Western.
- **HTTP version**: `http2and3` — HTTP/3 meaningfully helps mobile TTFB.
- **Compress**: `true` (Brotli + gzip — CloudFront picks based on `Accept-Encoding`).
- **Viewer protocol policy**: `redirect-to-https`.
- **Minimum TLS**: `TLSv1.2_2021`.
- **Default root object**: `index.html`.
- **Cache policy**: AWS-managed `CachingOptimized` (id `658327ea-f89d-4fab-a63d-7e88639e58f6`) for assets; a **custom policy** for HTML that caches on `CloudFront-Viewer-Country` if you're geo-routing (see step 7).
- **Response headers policy**: attach the `SecurityHeadersPolicy` managed policy (id `67f7725c-6f97-4210-82d7-5512b31e9d03`) at minimum. Add a custom one for CSP (see `references/security.md`).

### 7. Attach the S3 bucket policy to allow the distribution

```bash
DIST_ID=E1ABCDEFG23HIJ
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipalRead",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID"
      }
    }
  }]
}
EOF
)"
```

### 8. Route 53 alias + post-deploy verification

Create an A/AAAA ALIAS record to the distribution's domain name (never a CNAME at apex). Then verify end-to-end:

```bash
# TLS, HTTP/2, HTTP/3, compression, headers, TTFB
curl -sSI --http3 https://example.com/ | head -n 30
curl -o /dev/null -s -w "TTFB: %{time_starttransfer}s  Total: %{time_total}s\n" https://example.com/
```

Target numbers for a paid-social landing page:
- **TTFB** from CloudFront edge: < 100ms warm, < 400ms cold
- **Lighthouse Performance** (mobile, 4G throttle): ≥ 90
- **LCP**: < 2.0s
- **CLS**: < 0.1

### 9. Wire the deploy to CI

See `scripts/deploy.sh` for a full deploy script that does the two-tier upload, triggers an **invalidation only for HTML** (assets are hashed — never invalidate them), and verifies the deploy.

```bash
./scripts/deploy.sh \
  --bucket landing-acme-main-prod \
  --dist E1ABCDEFG23HIJ \
  --dir ./dist
```

---

## Silent multi-variant routing — the core differentiator

This is what the user actually cares about most: **one domain serving multiple pages, invisibly.** No redirects, no flash, no "loading..." trick. The viewer asks for `example.com/` and gets different HTML depending on who they are — all served 200 OK on the first byte.

The pattern is always the same three pieces:

1. A **viewer-request CloudFront Function** that inspects the request and **rewrites `event.request.uri`** to point at a variant prefix in S3 (e.g. `/` → `/variants/promo-a/index.html`).
2. A **cache policy** that includes the bucketing signal (country header, cookie, custom header) in the cache key — otherwise you'll serve variant A to variant B's users.
3. **S3 layout** that keeps variants under distinct prefixes: `variants/default/`, `variants/promo-a/`, `variants/promo-b/`, `variants/il/`, etc.

Full working code for each routing type (path, geo, cookie/UTM, IP-range, device) lives in **`references/cloudfront-functions.md`**. Read that file the moment the user asks for anything beyond a single landing page on a single domain.

Quick example — geo routing, attached to viewer-request on the default behavior:

```javascript
function handler(event) {
  var req = event.request;
  var country = req.headers['cloudfront-viewer-country'];
  var code = country ? country.value : 'US';

  // Only rewrite the root; let asset paths pass through untouched
  if (req.uri === '/' || req.uri === '/index.html') {
    if (code === 'IL') req.uri = '/variants/il/index.html';
    else if (code === 'DE' || code === 'AT' || code === 'CH') req.uri = '/variants/de/index.html';
    else req.uri = '/variants/default/index.html';
  }
  return req;
}
```

Attach this to the default behavior as `viewer-request`. Create a custom cache policy that whitelists `CloudFront-Viewer-Country` in the cache key. Done — three silent geo variants on one URL.

**Anti-patterns to call out:**

- ❌ Redirecting (`302 /il/`) — breaks ad trackers, adds a round-trip, users see the URL change.
- ❌ Client-side JS switching content — fails Lighthouse LCP, hydration flash is visible on slow mobile.
- ❌ Forgetting to add the bucketing signal to the cache key — you'll serve one variant to everyone after the first request.
- ❌ Putting variants at the HTML level only (`/promo-a.html`) — fine for path-based, but you lose the "same URL" property.

---

## Performance playbook for paid social

These pages are the first 3 seconds of a $X CAC funnel. Treat performance as the feature.

Read **`references/performance.md`** for the complete playbook. Highlights:

1. **Two-tier caching** (step 3 above) — the single biggest win.
2. **Brotli + gzip** via CloudFront `Compress: true` — saves 20-30% on text weight over gzip alone.
3. **HTTP/3** on the distribution — ~50–150ms faster TTFB on mobile LTE.
4. **Origin Shield** in the region closest to the S3 bucket — reduces origin fetches by ~80% on cold pops; free-ish at scale. Turn on for any campaign expecting >100k daily clicks.
5. **Preconnect / preload** in HTML `<head>`:
   ```html
   <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
   <link rel="preload" as="font" href="/fonts/inter.woff2" type="font/woff2" crossorigin>
   <link rel="preload" as="image" href="/hero.avif" fetchpriority="high">
   ```
6. **Image strategy**: AVIF → WebP fallback → JPEG. Serve hero at `fetchpriority="high"`. No `<picture>` tricks needed if CloudFront isn't doing image conversion; just ship the right format from build.
7. **Font strategy**: self-host `woff2`, `font-display: swap`, subset to the actual characters used.
8. **Third-party tags** (Meta Pixel, TikTok, GA4): load with `async` or `defer`, never in the critical path. Consider server-side tagging via a separate CloudFront behavior later.
9. **Don't ship a framework if you don't need one.** A 200KB React bundle for a 1-screen landing page is malpractice. Vanilla HTML + a sprinkle of JS beats React on every metric that matters here.
10. **Measure from the ad network's edge**, not your laptop. Use WebPageTest with a 4G profile from the geo you're targeting.

---

## Security & production readiness

Read **`references/security.md`** for the full checklist. The non-negotiables:

- OAC, not OAI, not public-read bucket
- TLSv1.2_2021 minimum; prefer TLSv1.3 via modern SecurityPolicy
- Managed `SecurityHeadersPolicy` attached, plus a custom CSP (report-only first, enforce after a week)
- HSTS with `includeSubDomains; preload` — only after you're certain all subdomains are HTTPS-ready
- AWS WAF attached to the distribution with the managed **Core Rule Set** + **Known Bad Inputs**, especially if forms exist
- CloudTrail on, S3 access logging on (to a separate log bucket), CloudFront access logs to the same log bucket
- No secrets, API keys, or internal URLs in the built JS bundle — grep the `dist/` before upload
- Separate dev / staging / prod AWS accounts, or at minimum separate distributions and buckets

---

## Cache invalidation — do it right

- **Never invalidate `/*`** as a reflex. It costs money at scale and defeats the point of hashed assets.
- On HTML-only changes: `aws cloudfront create-invalidation --distribution-id $DIST --paths "/" "/index.html" "/*.html"`
- On a full redeploy with hashed assets: HTML invalidation is enough. Old hashed assets remain cached (fine — they're immutable) and get garbage-collected by S3 lifecycle.
- Set an S3 lifecycle rule to delete noncurrent object versions older than 30 days (you enabled versioning in step 2).

---

## Observability

- **Real-user metrics**: CloudFront real-time logs → Kinesis Data Firehose → S3 → Athena. Or CloudWatch RUM for LCP/FID/CLS from actual users.
- **Synthetic**: CloudWatch Synthetics canary hitting `/` from 3+ regions every 5 minutes. Alarm on `Duration > 2000ms` or `StatusCode != 200`.
- **Cache hit ratio**: CloudWatch metric `CacheHitRate` — target > 85% for this use case. If lower, your cache key is partitioned too finely.
- **Error rate**: `5xxErrorRate` alarm at > 1% for 5 minutes.

---

## Escalation triggers — when to stop and rethink

Pause and push back on the user if any of these come up — these signal the skill's defaults may not fit:

- **"I need to read from a database before picking the page"** → this is no longer a static landing page. Propose Lambda@Edge or recommend a proper rendering service.
- **"We need per-user personalization on first paint"** → edge functions can't query anything external. Consider server-side rendering on a real compute layer.
- **"The page has a form that writes to our DB"** → fine, but the form POST goes to API Gateway or a Lambda Function URL, **not** to CloudFront/S3. Keep the landing page static; the form handler is a separate concern.
- **"We need dozens of language variants"** → at >10 variants, consider a single SPA with client-side i18n + a small edge function setting the default locale. Don't multiply S3 prefixes indefinitely.
- **"We're A/B testing 5+ variants on the same URL"** → works, but your cache key will need a bucket-id header, and cache efficiency will drop. Talk the user through the tradeoff before building it.

---

## Reference files

When the user's ask goes deeper than the workflow above, open the relevant reference file. Each is self-contained.

- **`references/cloudfront-functions.md`** — Complete, copy-paste CF Function code for every routing pattern (path, geo, cookie/UTM, A/B bucketing, IP allow-list, device, UTM-driven variant). Cache-policy configuration for each. Test commands.
- **`references/distribution-config.json`** — Full production CloudFront distribution config JSON. Use with `aws cloudfront create-distribution-with-tags --cli-input-json file://...`.
- **`references/performance.md`** — Deep performance playbook: Origin Shield sizing, compression configuration, resource hints, image pipelines, font subsetting, third-party tag patterns, measurement methodology.
- **`references/security.md`** — Full security checklist: CSP construction, HSTS rollout, WAF rule set, logging/monitoring, secret-scanning the bundle, account separation.
- **`references/troubleshooting.md`** — Common failure modes: 403s from S3 after OAC, cache-key explosions, TLS handshake errors, mixed-content warnings, HTTP/3 negotiation failures, stale HTML after deploy.
- **`scripts/deploy.sh`** — Production-grade deploy script (two-tier upload, selective invalidation, post-deploy verification).
- **`scripts/invalidate.sh`** — Smart invalidation helper (HTML-only by default).

---

## One final heuristic

If the user says "just deploy this landing page to AWS," **still do all 9 steps.** The temptation is to take shortcuts — public S3 bucket, no CloudFront, no TLS certificate, cache-control on the S3 object itself. Every one of those shortcuts bites in production: mixed-content warnings, slow TTFB, ad accounts flagging HTTP, no ability to roll out a fix globally. The full stack is only marginally more effort than the cowboy version, and it scales from 1 visitor to 10M without changes.

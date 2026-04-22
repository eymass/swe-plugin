# AWS architecture reference

Read this file when designing the hosting stack, choosing between services, or deciding between AWS and Vercel / Netlify / Cloudflare Pages.

## Reference architecture

```
Viewer (TikTok IAB / Meta IAB / system browser)
    │
    ▼  Route53 (ALIAS apex → CloudFront, ACM cert in us-east-1)
    ▼
CloudFront distribution  ── HTTP/3 · TLS 1.3 · Brotli · PriceClass_200
    ├─ AWS WAF (Common + KnownBadInputs + BotControl-Common + rate limit)
    ├─ CloudFront Functions (viewer req/res):
    │     UA routing · CSP/HSTS headers · A/B cookie bucketing via KeyValueStore
    └─ Lambda@Edge (origin req/res):
          pixel proxy /px/events · CAPI relay · Secrets Manager token lookup · HTML personalization
    │
    ▼  Origin Shield (us-east-1 or nearest to S3)
    │
S3 (private, OAC)  +  ALB / Lambda Function URL (for /api/*)
    │
CloudWatch RUM ──▶ CloudWatch Logs / Metrics / Alarms · EventBridge (scheduled invalidations)
Secrets Manager (TikTok + Meta tokens) · CDK TypeScript for IaC
```

## Service choices — what, why

### CloudFront
- **HTTP/3** — enable. TikTok IAB traffic is on mobile carriers with variable latency; HTTP/3's 0-RTT resumption helps.
- **Brotli** — enable for text content. Saves ~15–20% over gzip on HTML/CSS/JS.
- **TLS 1.3** — minimum. Drop TLS 1.2 only when CRUX shows no legacy-client tail.
- **PriceClass_200** — default for TikTok-first advertisers. Covers North America, Europe, Asia (incl. SEA where TikTok density is highest), without paying for India / South America edges.
- **Origin Shield** — enable in the region nearest S3. Collapses origin fetches; improves cache hit ratio for long-tail pages.
- **HTTP/3 + TLS 1.3** — default for any new distribution.

### S3
- Private bucket, **Origin Access Control (OAC)**, never OAI (deprecated).
- Never use the S3 website endpoint. Always the REST endpoint with OAC.
- Versioning on, lifecycle policy to expire old versions at 30 days.
- For multi-region resilience, CRR (Cross-Region Replication) to a standby bucket + CloudFront origin group. Overkill for a single landing page; useful for a portfolio of always-on pages.

### ACM
- Certificate **must** be in `us-east-1` for CloudFront — non-negotiable.
- Use DNS validation. Wildcard `*.yourdomain.com` + apex `yourdomain.com` on one cert for simplicity.

### Route53
- ALIAS A and AAAA records at apex pointing to CloudFront. Publish AAAA — a large fraction of mobile carriers serving TikTok traffic are IPv6-only.
- Health checks on the origin if you're doing active-active failover; not needed for a single CloudFront distro.

### CloudFront Functions vs Lambda@Edge
**CloudFront Functions handles ~90% of edge logic:**
- URL rewrites
- Security headers (CSP, HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)
- Cache-key normalization
- UA sniffing for IAB variants
- Cookie-based A/B bucketing backed by CloudFront KeyValueStore

Sub-millisecond execution, ~$0.10 per million invocations, runs at every PoP. JavaScript runtime (ES5.1-ish with restrictions); no network access; no file system.

**Lambda@Edge is reserved for:**
- Outbound HTTPS (pixel / CAPI relay)
- Secrets Manager calls
- Complex HTML personalization
- Origin response rewrites with significant logic

Node 20.x runtime. Cold start ~200 ms; warm ~20 ms. ~$0.60 per million invocations plus compute. Runs at regional edge caches (not every PoP).

**Rule:** if a CloudFront Function can do it, use a CloudFront Function. Reach for Lambda@Edge only when you need network I/O or secrets.

### WAF
Stack for a paid-social landing page:
- `AWSManagedRulesCommonRuleSet` — core OWASP coverage
- `AWSManagedRulesKnownBadInputsRuleSet` — blocks common exploit patterns
- `AWSManagedRulesBotControlRuleSet` at **Common** level — bot scoring without the pricey Targeted tier (~$10/mo per ACL + $1 per million requests after the 10M free tier)
- Rate rule: 2000 req / 5 min at the apex, 100 / min on `/api/*`
- Geo-match block for non-target countries when a campaign is geo-fenced
- **Allowlist**, do not block: `TikTokBot`, `facebookexternalhit`, `Meta-ExternalAgent`, `LinkedInBot`, `Twitterbot`, `Slackbot-LinkExpanding`. They generate OG preview cards. Blocking them erases your ad thumbnails.

### CloudWatch RUM
Mandatory because CrUX excludes WebView traffic. PageSpeed Insights, Search Console, and CrUX BigQuery all report zero data for TikTok IAB users. RUM is the only surface that sees them.

- Unauthenticated mode with a resource-based policy (not Cognito) — avoids dependency on a cookie inside a partitioned IAB storage jar.
- Sample 100% until traffic exceeds ~1M monthly sessions; then 10%.
- Budget: roughly $1 per 100k events.
- Alternative: Sentry Performance if already on Sentry. Datadog RUM if already on Datadog. Don't run two; pick one.

### Secrets Manager
- TikTok Events API access token
- Meta CAPI access token (if dual-fanout)
- Stripe restricted keys for any server-side Stripe calls

Lambda@Edge reads at cold start, caches in module scope. Rotate quarterly; set a CloudWatch Alarm on age.

### IaC
- **AWS CDK (TypeScript)** — default for CloudFront-heavy stacks with Lambda@Edge and custom WAF rules. Expressive, good typings.
- **SAM** — best for pure Lambda + API Gateway. Overkill-and-wrong-shape for a landing page.
- **Terraform** — acceptable if the org standard is Terraform. Not preferred for Lambda@Edge because AWS-provider lifecycle on edge functions is clunky (forced replaces on minor changes).

## Amplify Hosting — when to use it

Right answer when:
- The team wants `git push` → auto-deploy
- Needs Next.js SSR / ISR on Node 20 / 22
- Does not need fine-grained CloudFront config or Lambda@Edge
- Comfort with Amplify's CloudFront provisioning (limited override surface)

**Wrong answer when** you need:
- A custom first-party pixel-proxy endpoint
- Edge-based A/B splits via KeyValueStore
- Deep WAF integration with custom rules
- Tight cost control at 50M+ requests/month

For a single-page, low-complexity lander with a static CMS and a contact form, Amplify is faster to ship. For anything that needs the CAPI relay, DIY CloudFront + S3 + CDK.

## Why AWS over Vercel / Netlify / Cloudflare Pages

For a TikTok-first advertiser:

**Vercel / Netlify:**
- Great DX, fast previews.
- Weaker on: first-party pixel proxy (requires Edge Functions but their runtime has egress restrictions), WAF (Vercel Firewall is recent and less mature than AWS WAF), data residency control, secrets management (env vars only, no KMS-backed rotation).
- Cost: can spike unpredictably at 10M+ requests/month on paid-social campaigns.

**Cloudflare Pages:**
- Excellent edge performance, Turnstile native.
- Weaker on: deep ops integration (if the rest of your infra is AWS, you're stitching two clouds), Node-compat story for CAPI relays is improving but not seamless, integration with enterprise SSO / SCIM.

**AWS wins for:**
- First-party pixel proxy on your apex domain — extends cookie lifetimes past ITP's 7-day cap by setting cookies server-side with `Set-Cookie` headers from Lambda@Edge.
- Deep WAF + Bot Control integration with the whole AWS IAM / org story.
- Data residency control (pick your CloudFront price class and origin region).
- Predictable cost at 10M+ req/month under the new CloudFront flat-rate plans.
- IAM-scoped Events API token in Secrets Manager, not a config panel.

**The trade:** slower deploys, invalidation discipline, more IaC. Accept it.

## Deployment discipline

- **Hash all static assets** (JS, CSS, images) with content hashes. Immutable cache forever.
- **HTML is the only thing invalidated**. Never `/*` — expensive and slow. Invalidate by explicit path.
- Preview deploys behind basic auth or signed cookies.
- Rollback plan: pre-baked `aws cloudfront update-distribution` to the previous config. Document the exact command in the runbook.

## Cost expectations (rough, 2025–2026)

For a single landing page taking 1M monthly visits from paid social:

| Service | Approx monthly |
|---|---|
| CloudFront (1M req, PriceClass_200, ~500 KB avg response) | $40–60 |
| S3 storage + requests | <$5 |
| Route53 hosted zone + queries | $1–2 |
| ACM | free |
| Lambda@Edge (1M invocations for pixel proxy) | $1–5 |
| CloudFront Functions (1M invocations) | $0.10 |
| WAF (ACL + rules + 1M requests) | $15–20 |
| CloudWatch RUM (100k events sampled) | $1–3 |
| Secrets Manager (2 secrets) | $0.80 |
| **Total** | **~$65–95 / month** |

At 10M visits, linear scaling: roughly $600–900 / month. Budget accordingly.

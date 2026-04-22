# Performance, monitoring, and experimentation

Read this file for Core Web Vitals targets, RUM setup, bot protection, funnel instrumentation, and A/B testing.

## Core Web Vitals — the non-negotiables

Targets are p75 measured by RUM on mid-range Android over 4G inside the TikTok IAB. Not lab, not Lighthouse, not PageSpeed Insights — RUM.

| Metric | Target | Poor |
|---|---|---|
| LCP (Largest Contentful Paint) | < 2.5 s | > 4.0 s |
| INP (Interaction to Next Paint) | < 200 ms | > 500 ms |
| CLS (Cumulative Layout Shift) | < 0.1 | > 0.25 |
| TTFB (Time to First Byte) | < 600 ms from CloudFront edge | > 1.8 s |
| FCP (First Contentful Paint) | < 1.8 s | > 3.0 s |
| First-paint JS (gzipped) | < 150 KB | — |

INP replaced FID on 12 March 2024 as the responsiveness Core Web Vital. It is the hardest metric on ad landers because third-party JS piles up on the main thread.

## INP tuning — where the milliseconds go

Every 100 KB of third-party JS costs roughly 40–80 ms INP on a mid-tier Android. Budget accordingly.

- **Defer non-critical JS** until after LCP. Use `<script async>` or `<script defer>`; avoid blocking `<script>` in the head.
- **Boot chat widgets on first interaction**, not on load. Intercom, Drift, Zendesk, etc. — all fire on first `click` or `pointerdown`, never on `DOMContentLoaded`.
- **Preconnect to pixel domains** early so handshakes don't block later:
  ```html
  <link rel="preconnect" href="https://analytics.tiktok.com">
  <link rel="preconnect" href="https://business-api.tiktok.com">
  ```
- **Preload the hero image** and the single critical font weight.
- **Lazy-load everything below the fold** — images, iframes, non-critical scripts.
- **Break up long tasks**: `await new Promise(r => setTimeout(r, 0))` or `scheduler.yield()` (where supported) to yield to the main thread.
- **Keep the DOM under ~1,500 nodes.** Deep / wide DOMs tank INP on input events.
- **Avoid `requestAnimationFrame` chains on input handlers.** Debounce / throttle aggressively.

## LCP tuning

- Hero image is almost always the LCP element on a lander. Make it:
  - AVIF with WebP fallback
  - `fetchpriority="high"`
  - Preloaded in the head
  - Served from CloudFront with `Cache-Control: public, max-age=31536000, immutable`
- Inline critical CSS. External CSS blocks render.
- Server push / HTTP early hints if supported by the origin (Amplify and CloudFront support).
- Reduce TTFB: CloudFront with Origin Shield; Brotli; HTTP/3.

## CLS tuning

- Width and height attributes on every image and video. `<img src="..." width="1200" height="800">` — the browser reserves space before the asset loads.
- `aspect-ratio` CSS on dynamic media containers.
- Avoid injecting content above existing content (ads, cookie banners that push the hero down). Banners render in place from the start, even if hidden.
- Font swap: `font-display: swap` with a carefully chosen fallback font metrically similar to the web font — reduces layout shift on swap. Use `size-adjust`, `ascent-override`, `descent-override` on `@font-face` for precise matching.

## CloudWatch RUM setup

Mandatory — CrUX excludes WebView traffic.

Basic setup:
1. Create a RUM app monitor in CloudWatch.
2. Use **unauthenticated identity pool** or **resource-based policy** mode (not Cognito) — avoids cookie dependency inside partitioned IAB storage.
3. Install the client snippet (async load, guard with `window.AwsRumClient`).
4. Send custom events for funnel steps: `form_start`, `form_submit`, `thank_you_view`.
5. Sample 100% until traffic > 1M monthly sessions; then sample 10%.

Metrics to dashboard:
- p75 LCP / INP / CLS / TTFB by country, device type, UA class (IAB vs system browser)
- Error rate by UA class
- Session duration distribution
- Custom funnel events

## Alternative RUM

- **Sentry Performance** — right if Sentry is already the error tracker. Single tool, correlated error + perf.
- **Datadog RUM** — right if the org is Datadog-standard. Expensive at scale; feature-rich.
- **Pick one.** Never two.

## Session replay — what works, what breaks

| Tool | TikTok IAB | Meta IAB | System browser |
|---|---|---|---|
| Microsoft Clarity | ✅ Works | ✅ | ✅ |
| Sentry Replay | ✅ Works | ✅ | ✅ |
| LogRocket | ⚠️ User ID fails across redirects | ⚠️ | ✅ |
| Hotjar | ⚠️ User ID fails across redirects | ⚠️ | ✅ |
| FullStory | ⚠️ User ID fails across redirects | ⚠️ | ✅ |

**Default: Microsoft Clarity** — free, unlimited, works everywhere. **Or** Sentry Replay if already on Sentry.

Anything that depends on a service worker or a third-party cookie on its own domain will degrade inside IABs.

## Bot protection and CAPTCHA

### Do not use reCAPTCHA v3 as the sole gate on IAB traffic.
Since mid-2025, Google systematically scores legitimate WebView users at 0.3 or lower, because:
- No Google session cookies in the isolated IAB jar
- Fresh fingerprint every visit
- UA flags (`wv`, `FBAN`, `Instagram`, `musical_ly`) trigger the risk model

Legitimate users get blocked. Unusable.

### Default stack
- **Cloudflare Turnstile** on the client — free, unlimited, works in every IAB (doesn't depend on prior Google cookies; falls back to proof-of-work when hardware attestation is unavailable).
- **AWS WAF Bot Control Common** at the edge — behavioral scoring, bot list matching.
- **Rate limiting** on submit endpoints — 100 / min per IP is typical.
- **Re-render Turnstile on any submit error** — the token is single-use; some pre-submit AJAX validations will consume it.

### Acceptable alternatives
- **hCaptcha** — drop-in Turnstile alternative. Use when Google-ecosystem dependence is a concern.

### Escalation
- **DataDome** — when real-dollar fraud justifies five-figure annual spend.
- **Arkose Labs** — same trigger, different vendor. Strong on credential stuffing and new-account fraud.

## Funnel events — instrument all of these

Every paid-social LP ships with these events instrumented on both the client Pixel and the server CAPI, with shared `event_id`:

1. **Ad impression** — from TikTok's side, reconciled daily via Ads Manager API.
2. **LP view** — fires on page load. Server event includes `ttclid` from URL, `_ttp` cookie, user IP, UA.
3. **Scroll depth** — 25%, 50%, 75%, 100%. Throttled fire.
4. **Form start** — first input focus. Indicates engagement.
5. **Form field errors** — per-field validation failures. Diagnostic signal for form-quality issues.
6. **Form submit attempt** — click on submit button.
7. **Form submit success** — server returns 2xx, form cleared.
8. **Thank-you page view** — conversion event.
9. **Qualified lead** — server-side scoring (e.g., lead passes enrichment, email validates).

Each step gets p75 latency, funnel drop-off chart, and regression alarm on p75 or drop-off rate.

## Dedupe rate monitoring

The dedupe rate between Pixel and Events API should land in the **60–90%** band:
- **< 60%** — `event_id` wiring is broken. You're sending the same event with different IDs, so TikTok can't match them.
- **> 90%** — server channel is under-firing. Most events arrived only from the client Pixel; the server-side handler is erroring silently or consent-gated out.

Dashboard the rate, alarm on deviation.

## A/B testing — what works inside IABs

### Default: edge-bucketed variants via CloudFront Functions + KeyValueStore
Deterministic bucketing by a first-party cookie (set by CF Function on first visit), variant config read from KV Store, HTML rewrite at the edge. Zero client JS, zero render delay.

Implementation:
1. CF Function on viewer request reads the `ab_bucket` cookie; if absent, generates one and sets it.
2. CF Function reads the variant config from KeyValueStore (experiment ID → variant map).
3. Origin request adds a header like `x-ab-variant: hero-b`; origin serves per-variant HTML.
4. Measure in RUM + CAPI event stream. Call experiments on pre-registered success metrics.

### Acceptable: Statsig, GrowthBook (server-side flags + experimentation)
Right when you outgrow edge bucketing — need server-side flags for API-driven personalization, multi-arm bandits, proper stats engine. Both have good AWS deployment stories.

### Refuse: Optimizely, VWO, AB Tasty visual mode
Client-side visual editors kill LCP (render delay while the SDK evaluates) and their cookies fail under storage partitioning. For ad landers, these are anti-patterns.

### Dead: Google Optimize
EOL September 2023. No Google migration path. Do not propose it.

## RUM-to-business reconciliation

At campaign scale, reconcile three sources weekly:
1. **TikTok Ads Manager** — impressions, clicks, conversions as reported by TikTok.
2. **RUM** — page views, CWV, errors, funnel events from your own data.
3. **CRM / revenue system** — qualified leads, purchases, LTV.

Discrepancies:
- **TikTok > RUM** on clicks: tracking is missing some sessions (bounced users, JS disabled, CSP blocking). Acceptable 5–10% gap.
- **RUM > CRM** on conversions: lead quality issue or CRM ingestion lag. Investigate.
- **TikTok > CRM** on conversions: attribution window mismatch, or Pixel is over-firing. Check `event_id` wiring.

Build a dashboard that shows all three side-by-side by campaign and by day.

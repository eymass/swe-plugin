# Performance Playbook — Paid-Social Landing Pages

Every 100ms of TTFB costs ~1% of CTR→LP-view conversion. Treat perf as a feature, not an afterthought. This doc is the complete tuning checklist in priority order.

## Target metrics (mobile, 4G throttle, p75)

| Metric                              | Target          | Fail condition                |
| ----------------------------------- | --------------- | ----------------------------- |
| TTFB (from CF edge, warm)           | < 100ms         | > 300ms → investigate         |
| TTFB (cold)                         | < 400ms         | > 800ms → origin shield issue |
| LCP (Largest Contentful Paint)      | < 2.0s          | > 2.5s → image/font issue     |
| CLS (Cumulative Layout Shift)       | < 0.1           | > 0.25 → dimensions missing   |
| INP (Interaction to Next Paint)     | < 200ms         | > 500ms → JS blocking         |
| Lighthouse Performance (mobile)     | ≥ 90            | < 75 → stop, audit            |
| Total transfer (initial load)       | < 500KB         | > 1MB → cut something         |

---

## Layer 1: Caching (the single biggest lever)

### Two-tier Cache-Control strategy

Set these at upload time on S3 — not via CloudFront response manipulation, not via HTML `<meta>` tags.

| Asset type           | `Cache-Control`                                              | Why                                                         |
| -------------------- | ------------------------------------------------------------ | ----------------------------------------------------------- |
| HTML                 | `public, max-age=0, s-maxage=60, must-revalidate`            | Viewer revalidates every load; edge serves cached for 60s. A deploy propagates in ~60s without invalidation. |
| Hashed JS/CSS/fonts  | `public, max-age=31536000, immutable`                        | Filename is content-hashed; never changes. Browser and edge cache forever. |
| Non-hashed images    | `public, max-age=604800, stale-while-revalidate=86400`       | Caches for a week, soft revalidation for 24h.               |
| `robots.txt`, `.well-known/*` | `public, max-age=3600`                              | Short — these change occasionally.                          |

**`immutable` is crucial** — without it, browsers still send `If-None-Match` on every navigation. With `immutable`, browsers skip the revalidation round-trip entirely.

### CloudFront cache policy — key rules

1. Default to the AWS-managed `CachingOptimized` policy.
2. Only create custom cache policies when you **need a cache-key component** (variant bucket, country).
3. **Never** put `User-Agent` in the cache key — cache explosion.
4. **Never** put raw cookies in the cache key if you can avoid it; route in a function, emit `X-Variant-Bucket`, cache on that.
5. Query-string handling: strip everything except the one or two params that actually affect the response. Ad tracking params (`fbclid`, `gclid`, `ttclid`, `utm_*`) must not be in the cache key.

### Origin Shield — when and where

Origin Shield is a regional CloudFront layer between edge pops and the origin. It dramatically reduces origin fetches on cold pops.

**Turn it on if:**
- You expect sustained traffic > 10 RPS
- You're running a paid campaign across many geos (many cold pops)
- You see high origin-fetch rates in CloudWatch (`OriginLatency` spikes)

**Location:** put the shield in the region closest to your S3 bucket. If the bucket is in `us-east-1`, shield in `us-east-1`.

Cost: a small fee per request, but reduces S3 GET costs and origin load. Net is usually positive.

---

## Layer 2: Compression

### Enable Compression at CloudFront

`Compress: true` on every cache behavior. CloudFront automatically chooses Brotli for supported browsers (all modern ones) and gzip as fallback, based on the `Accept-Encoding` header.

Brotli saves 15-25% over gzip on HTML, 20-30% on JS.

### What compresses, what doesn't

CloudFront compresses only text content types smaller than 10MB:
- `text/html`, `text/css`, `application/javascript`, `application/json`, `text/plain`, `image/svg+xml`, etc.

Binary assets (JPEG, PNG, WebP, AVIF, WOFF2) are already compressed — don't double-compress.

### Upload without pre-compression

Do **not** upload `.gz` or `.br` files to S3 and set `Content-Encoding: br`. CloudFront handles compression. Pre-compressed uploads break the Brotli/gzip auto-negotiation.

Exception: if you ship a build with pre-compressed assets for another reason, use `Content-Encoding` and disable `Compress` on that behavior.

---

## Layer 3: Protocol and transport

### HTTP/2 and HTTP/3

Set `HttpVersion: http2and3` on the distribution. HTTP/3 (QUIC over UDP):
- Eliminates TCP head-of-line blocking
- Faster handshake on lossy mobile networks
- ~50-150ms TTFB improvement on mobile LTE

HTTP/3 is still negotiated — browsers that don't support it fall back to HTTP/2 automatically.

### TLS

- `MinimumProtocolVersion: TLSv1.2_2021` — supports modern ciphers including ChaCha20 (faster on mobile CPUs).
- Newer `TLSv1.3` everywhere possible (supported since all modern browsers).
- Prefer SNI-only (`SSLSupportMethod: sni-only`); dedicated IP is expensive and no longer needed.

### IPv6

`IsIPV6Enabled: true` on the distribution. Many mobile carriers route IPv6 preferentially; denying v6 adds a fallback round-trip.

---

## Layer 4: HTML critical path

### Resource hints in `<head>`

```html
<!-- DNS + TCP + TLS warmup -->
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="preconnect" href="https://www.googletagmanager.com">

<!-- Preload the hero image at highest priority -->
<link rel="preload" as="image" href="/hero.avif" type="image/avif" fetchpriority="high">

<!-- Preload the critical font file -->
<link rel="preload" as="font" href="/fonts/inter-variable.woff2" type="font/woff2" crossorigin>

<!-- Preload the critical CSS if split -->
<link rel="preload" as="style" href="/critical.css">
<link rel="stylesheet" href="/critical.css">
```

### Inline critical CSS

For a landing page, inline the above-the-fold CSS (< 14KB is ideal — fits in the initial TCP window) directly in `<head>`. Defer the rest:

```html
<style>/* critical ~8KB */</style>
<link rel="preload" as="style" href="/app.css" onload="this.rel='stylesheet'">
<noscript><link rel="stylesheet" href="/app.css"></noscript>
```

### Defer / async all JS

No blocking scripts in `<head>`. Ever.

```html
<script src="/app.js" defer></script>
<script src="https://connect.facebook.net/en_US/fbevents.js" async></script>
```

`defer` scripts execute in order after HTML parsing; `async` scripts execute as soon as they load (order not guaranteed — fine for independent tracking pixels).

### `fetchpriority` on the hero

```html
<img src="/hero.avif" alt="..." fetchpriority="high" width="1200" height="800">
```

Also set explicit `width` and `height` to reserve layout space — prevents CLS.

---

## Layer 5: Images

### Format priority

1. **AVIF** — best compression, supported in modern browsers
2. **WebP** — fallback for older browsers
3. **JPEG/PNG** — last resort

If your build doesn't emit multiple formats, use `<picture>`:

```html
<picture>
  <source srcset="/hero.avif" type="image/avif">
  <source srcset="/hero.webp" type="image/webp">
  <img src="/hero.jpg" alt="..." width="1200" height="800">
</picture>
```

### Responsive images

```html
<img srcset="/hero-600.avif 600w, /hero-1200.avif 1200w, /hero-2400.avif 2400w"
     sizes="(max-width: 768px) 100vw, 1200px"
     src="/hero-1200.avif"
     alt="..."
     width="1200" height="800"
     fetchpriority="high">
```

### Image CDN (optional escalation)

If the build pipeline can't pre-generate responsive variants, consider:
- **Lambda@Edge image handler** (Sharp-based, origin-response), caching processed images in CloudFront
- AWS Serverless Image Handler (CloudFormation template from AWS Solutions)
- Third-party: Cloudinary, imgix

For static landing pages with a known hero asset, **pre-generate at build time**. Don't pay per-request for an image transformer.

---

## Layer 6: Fonts

### Self-host `woff2`

Google Fonts via `<link href="//fonts.googleapis.com/css2?...">` adds a DNS lookup, a CSS round-trip, and cross-origin font fetches. Self-host:

1. Download the `woff2` files from Google Fonts Helper or similar.
2. Put them in `/fonts/` in the bucket.
3. Subset to only the characters you use (e.g. `glyphhanger --subset` or `subfont`).
4. Use `font-display: swap` in `@font-face` so text renders immediately in a fallback font while the custom one loads.

### Variable fonts

One variable font file often replaces 4–8 static files (regular/bold/italic/etc.). Ship one `.woff2` variable file and cut total font weight by 60-80%.

```css
@font-face {
  font-family: 'Inter';
  src: url('/fonts/inter-variable.woff2') format('woff2-variations');
  font-weight: 100 900;
  font-style: normal;
  font-display: swap;
}
```

---

## Layer 7: Third-party tags

These are the usual culprits for tanking Lighthouse scores on paid landing pages.

### Tag load order

1. **Consent banner first** (if GDPR) — otherwise no tracking fires.
2. **Meta Pixel, TikTok Pixel, Google Ads / GA4** — all `async`, all after the main content.
3. **Heatmaps (Hotjar, FullStory)** — defer aggressively or gate behind consent.
4. **Chat widgets (Intercom, Drift)** — lazy-load on user intent (scroll, click).

### Server-side conversion tracking

Meta's Conversions API, TikTok Events API, Google's Enhanced Conversions — all support server-side firing. Consider a follow-up story where the form POST goes to a Lambda that fires server-side conversions, removing the browser pixel weight entirely.

---

## Layer 8: Measurement

### Synthetic (deterministic baseline)

- **CloudWatch Synthetics canary** from us-east-1, eu-west-1, ap-southeast-1 every 5 minutes. Alarm on duration > 2000ms.
- **WebPageTest** run from the geo your paid ads target, with a 4G profile, 3 runs → take median.
- **Lighthouse CI** in GitHub Actions — fail the build on Performance < 90.

### Real-user (ground truth)

- **CloudWatch RUM** — captures LCP, CLS, INP from real sessions. Free tier is generous.
- **Sentry / DataDog RUM** if already in the stack.
- **CloudFront access logs** → Athena → query for p95 `time-taken`, cache hit ratio, 5xx rate.

### Key CloudWatch metrics to alarm on

| Metric              | Threshold          | Action               |
| ------------------- | ------------------ | -------------------- |
| `CacheHitRate`      | < 80% for 10 min   | Audit cache key      |
| `5xxErrorRate`      | > 1% for 5 min     | Page on-call         |
| `OriginLatency` p95 | > 500ms for 10 min | Check origin / shield|
| `TotalErrorRate`    | > 5% for 5 min     | Page on-call         |

---

## Don'ts — common perf-killers

- ❌ Shipping a 200KB React runtime for a 1-screen landing page. Use HTML + a sprinkle of JS.
- ❌ Loading jQuery "because the dev is used to it". You don't need it.
- ❌ Using `document.write()` — automatic Lighthouse fail.
- ❌ Large-DOM pages (> 1500 nodes) — tank INP.
- ❌ Unoptimized animations (`transform: none; top: 0;` instead of `transform: translateY(0)`).
- ❌ Blocking scripts anywhere above the fold.
- ❌ Loading all Meta/TikTok/GA pixels without consent gating in GDPR regions.
- ❌ Autoplay videos with sound — every browser blocks this anyway.
- ❌ Pre-compressed assets with `Content-Encoding` set — breaks CloudFront's auto-negotiation.
- ❌ Cache key explosion — check `CacheHitRate` weekly.

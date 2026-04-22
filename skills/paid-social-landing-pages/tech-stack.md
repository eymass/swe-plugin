# Tech stack reference

Read this file when picking a framework, form library, payment integration, or CAPTCHA for a paid-social landing page.

## Framework — what to reach for, in order of preference

### 1. Plain HTML/CSS with a tiny JS layer (default)
Right for most single-purpose landers. Fastest to ship, smallest bundle, no hydration cost. If the page has fewer than three dynamic behaviors (form submit, hero video, menu toggle), this is the correct choice. Stop thinking about frameworks.

### 2. Astro
Right for content-driven landers that benefit from component architecture but don't need client-side state. Islands architecture means only interactive components ship JS; the rest is static HTML. Defaults to zero-JS by default — ideal for IAB traffic.

### 3. Eleventy (11ty)
Right for marketing sites with many similar pages (per-product, per-campaign, per-geo variants). Pure static generation, plugin ecosystem, no runtime. Template flexibility is its strength over Astro if the team knows Nunjucks or Liquid.

### 4. Next.js (App Router + Server Components)
Right only when SSR/ISR is required:
- Personalization by query param (UTM-based hero swaps)
- Geo-specific content
- Auth-gated pages
- Dynamic pricing

If you reach for Next.js, ship with:
- App Router (not Pages Router for new work)
- Server Components by default
- Client components only where interactivity demands
- First-paint JS < 150 KB gzipped

On AWS, run Next.js via Amplify Hosting or OpenNext on Lambda@Edge.

### What to refuse

- **Vite + React SPA with client-side routing** for an ad lander. Hydration storm kills INP. The time-to-meaningful-paint on a mid-tier Android in TikTok's IAB is 3–5 seconds worse than SSR.
- **Gatsby** — not ideal; stagnant community in 2025–2026.
- **CRA (Create React App)** — deprecated.
- **Angular** for a lander — vast majority of projects do not need it.

## Styling

### Tailwind CSS (default)
Right for speed. The utility-class approach works well for single-purpose pages where a design system is not the point. Ship with the JIT engine and purge unused classes — final CSS should be <20 KB.

### Hand-rolled CSS
Right when you have three critical pages and a designer with strong opinions. Ship as critical CSS inline (`<style>` in `<head>`) for everything above the fold; async-load the rest via `media="print" onload="this.media='all'"`.

### What to refuse
- **CSS-in-JS at runtime** (styled-components, Emotion in client mode). Adds FOUC risk and 30–50 KB of runtime. Use zero-runtime solutions (Vanilla Extract, Panda CSS) if CSS-in-JS is mandated.

## Forms

### React Hook Form + Zod (when in React)
Best-in-class. Low re-render count (uncontrolled inputs), schema-based validation, small bundle. Zod for validation because the schema can be shared with the server-side handler.

### Vanilla forms with progressive enhancement (when not in React)
Standard HTML5 validation (`required`, `type="email"`, `pattern`) + a submit handler that posts JSON. Works without JS; enhances with JS for AJAX + error display. This is the correct choice for Astro / 11ty / plain-HTML landers.

### Autocomplete attributes — mandatory
The only path to iCloud Keychain and 1Password inside WKWebView. Always set:

```html
<input type="email" autocomplete="email" name="email">
<input type="tel" autocomplete="tel" name="phone">
<input type="text" autocomplete="given-name" name="first_name">
<input type="text" autocomplete="family-name" name="last_name">
<input type="text" autocomplete="postal-code" name="zip">
<input type="password" autocomplete="new-password" name="password">
```

Without these, WKWebView's built-in autofill and password managers don't trigger. Measurable drop in conversion.

### Input types
Use native input types: `type="email"`, `type="tel"`, `type="url"`, `type="number"`, `type="date"`. They trigger the correct mobile keyboard. `type="tel"` specifically brings up the numeric pad — important for phone and zip fields.

## Payments

### Stripe Checkout (hosted) — default for IAB traffic
The hosted `checkout.stripe.com` page inherits a fresh cookie jar (the user is leaving your origin) but Stripe's server-side session carries the context. Supports cards, Apple Pay (when the user has opened it in Safari), Google Pay, Link, buy-now-pay-later methods.

```js
const { url } = await fetch('/api/checkout', { method: 'POST', body: JSON.stringify({ priceId }) }).then(r => r.json());
window.location.href = url;
```

**On TikTok and Meta-family IABs, this is the only reliable payment path.** The user is redirected to `checkout.stripe.com`; on TikTok iOS this breaks out of the IAB into the system Safari on most 2025–2026 builds. On Android, behavior varies; test per campaign.

### Stripe Payment Element (Elements) — system browser only
The embedded Payment Element works fine in Safari, Chrome, Twitter's SFSafariViewController, Reddit, YouTube. Inside TikTok / Meta / Snap it renders, but Apple Pay / Google Pay buttons hide and Link OTP flow breaks.

Use Payment Element only when traffic source is confirmed to be system browser (email campaigns, SEO, direct). Never default to it for paid-social.

### Stripe Link
Works inside WKWebView but the device-remembrance cookie is partitioned — users re-OTP every session. If the OTP email opens in Gmail's own IAB, the original Link tab is destroyed. Rely on Link only in system browser contexts.

### Apple Pay domain registration
Before debugging why Apple Pay doesn't render:
1. Register every origin (production, staging, preview) in the Stripe Dashboard Payment method domains.
2. Host `.well-known/apple-developer-merchantid-domain-association` on each.
3. Verify with `curl https://yourdomain.com/.well-known/apple-developer-merchantid-domain-association` — should return the association file.

Without this, Apple Pay never renders even in Safari. Most "Apple Pay doesn't work" issues are missing domain registration.

## Fonts

- `font-display: swap` on every `@font-face` — FOIT kills LCP.
- `preload` the single critical weight — no more than one:
  ```html
  <link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin>
  ```
- WOFF2 only. WOFF and TTF are unnecessary in 2025–2026.
- **Self-host fonts from CloudFront.** Never hotlink Google Fonts on an ad lander — the extra DNS + TLS handshake costs 100–200 ms LCP.
- Variable fonts preferred when using multiple weights — one file, smaller total.

## Images

- **AVIF with WebP fallback**:
  ```html
  <picture>
    <source srcset="hero.avif" type="image/avif">
    <source srcset="hero.webp" type="image/webp">
    <img src="hero.jpg" alt="..." fetchpriority="high" width="1200" height="800">
  </picture>
  ```
- `fetchpriority="high"` on the hero image. Tells the browser to prioritize the LCP element.
- `loading="lazy"` and `decoding="async"` on everything below the fold.
- Responsive images with `srcset` and `sizes` for bandwidth efficiency.
- `width` and `height` attributes mandatory — prevents CLS.
- Image optimization pipeline: Next.js Image, Astro Image, or a Lambda@Edge resizer behind CloudFront.

## Video

- `<video autoplay muted playsinline loop preload="metadata" poster="/hero.jpg">` — autoplay requires both `muted` and `playsinline` on iOS.
- `preload="metadata"` — fetches only the metadata upfront, not the full video.
- Poster frame for Low Power Mode (when autoplay is disabled on iOS).
- Short hero loops (<10s): inline MP4, H.264 baseline profile for compatibility.
- Longer content (>30s): HLS via Mux or Cloudflare Stream. Native HLS on iOS, hls.js on Android WebView.

```html
<video autoplay muted playsinline loop preload="metadata" poster="/hero.jpg">
  <source src="/hero.mp4" type="video/mp4">
</video>
```

## CAPTCHA

See `performance-monitoring.md` for bot protection detail. Short version:

- **Default: Cloudflare Turnstile.** Free, unlimited, works in every IAB.
- **Acceptable: hCaptcha.** Drop-in Turnstile alternative.
- **Refuse: reCAPTCHA v3 as sole gate.** Systematically scores legitimate WebView users at 0.3 or lower.
- **Escalate: DataDome or Arkose Labs.** Only when real-dollar fraud justifies five-figure spend.

## Third-party scripts — load discipline

The rule: **nothing on the main thread on initial load except critical first-party code.**

- Pixel: defer until after LCP. Load the base snippet synchronously so the global is ready, but `ttq.page()` fires via `requestIdleCallback`.
- Chat widgets (Intercom, Drift, Zendesk): load on first interaction, not on `DOMContentLoaded`.
- Heatmaps (Hotjar, Clarity): load via `requestIdleCallback` or defer until after first paint.
- Tag managers (GTM client): if possible, move to server-side GTM. Every client GTM adds 50–100 KB.
- Live chat proactive popups: fire after 30+ seconds of engagement, not on load.

Every 100 KB of third-party JS costs 40–80 ms INP on mid-tier Android. Budget accordingly; INP is non-negotiable.

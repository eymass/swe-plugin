# TikTok Pixel + Events API — implementation reference

Read this file when setting up tracking, debugging attribution, or deciding on a CAPI gateway pattern.

## Why both tracks are mandatory

Client-only Pixel loses 25–40% of events paid media is billed for, because of:
- iOS 14.5+ ATT (App Tracking Transparency) — users opt out of IDFA.
- ITP's 7-day first-party cookie cap.
- IAB storage isolation — a fresh jar every ad tap.
- Ad blockers.
- Consent walls that defer Pixel loading.

Ship the Events API (server-side) from day one, share a UUID `event_id` between client and server, and let TikTok dedupe.

## How deduplication actually works

- Matching key: `pixel_code` + `event` name + `event_id` within a 48-hour window.
- Within **5 minutes**: the two events are **merged** — server-side identifiers enrich the earlier client event.
- Between **5 minutes and 48 hours**: deduped, first kept.

Generate `event_id` as UUIDv4 at action time (form submit, purchase confirmation), stash in the dataLayer, send with the client Pixel event, and include in the server CAPI call. One source of truth, never two.

## EMQ — Event Match Quality

EMQ is the single lever that governs how well TikTok's optimizer attributes conversions. Target:
- Purchase ≥ 8.0
- Lead / CompleteRegistration ≥ 6.5
- ViewContent ≥ 4.0

Every additional identifier raises the score. Hash with SHA-256 after normalization.

| Field | CAPI key | Hash | Normalization |
|---|---|---|---|
| Email | `email` / `em` | SHA-256 | lowercase, trim whitespace |
| Phone | `phone` / `ph` | SHA-256 | E.164 `+[country][number]`, digits only, no spaces or punctuation |
| External ID | `external_id` | SHA-256 | stable user or cookie ID, your choice |
| First name | `first_name` / `fn` | SHA-256 | lowercase, strip punctuation and accents |
| Last name | `last_name` / `ln` | SHA-256 | lowercase, strip punctuation and accents |
| Date of birth | `date_of_birth` / `db` | SHA-256 | `YYYYMMDD` |
| City | `ct` | SHA-256 | lowercase, no spaces |
| State | `st` | SHA-256 | lowercase, ISO 3166-2 subdivision code |
| Zip / postcode | `zp` | SHA-256 | lowercase, no spaces |
| Country | `country` | SHA-256 | lowercase, ISO 3166-1 alpha-2 |
| IP address | `ip` | **No hash** | send as received |
| User agent | `user_agent` | **No hash** | send as received |
| Click ID | `ttclid` | No | from URL param `ttclid=...` |
| TikTok Pixel cookie | `ttp` | No | from `_ttp` first-party cookie |

**Never hash in the browser.** The browser sends plaintext over TLS to your first-party endpoint, which hashes and forwards to TikTok. Hashing in the browser risks logging plaintext PII into RUM or session replay.

## Canonical Pixel base (consent-gated)

```html
<script>
!function (w,d,t){w.TiktokAnalyticsObject=t;var ttq=w[t]=w[t]||[];
ttq.methods=["page","track","identify","instances","debug","on","off","once","ready",
"alias","group","enableCookie","disableCookie","holdConsent","revokeConsent","grantConsent"];
ttq.setAndDefer=function(t,e){t[e]=function(){t.push([e].concat([].slice.call(arguments,0)))}};
for(var i=0;i<ttq.methods.length;i++)ttq.setAndDefer(ttq,ttq.methods[i]);
ttq.load=function(e,n){var i="https://analytics.tiktok.com/i18n/pixel/events.js";
ttq._i=ttq._i||{};ttq._i[e]=[];ttq._i[e]._u=i;ttq._t=ttq._t||{};ttq._t[e]=+new Date;
ttq._o=ttq._o||{};ttq._o[e]=n||{};var o=d.createElement("script");o.async=!0;
o.src=i+"?sdkid="+e+"&lib="+t;var a=d.getElementsByTagName("script")[0];
a.parentNode.insertBefore(o,a)};
ttq.holdConsent(); ttq.load('YOUR_PIXEL_ID'); ttq.page();
}(window,document,'ttq');
</script>
```

Call `ttq.grantConsent()` only after the CMP records opt-in. For California / Virginia / Colorado / Connecticut / Utah users, set `limited_data_use: true` on every event.

**TikTok has no Google Consent Mode v2 analog.** LDU is the Meta-equivalent mechanism; use it for US state privacy laws. For GDPR, revoke consent entirely (`ttq.revokeConsent()`) until opt-in.

## Events API v1.3 payload

POST `https://business-api.tiktok.com/open_api/v1.3/event/track/` with header `Access-Token: <your-token>`.

```json
{
  "event_source": "web",
  "event_source_id": "CXXXXXXXXXXXXXXXXXXX",
  "test_event_code": "TEST12345",
  "data": [{
    "event": "Purchase",
    "event_time": 1761100000,
    "event_id": "evt_9f3c2b1a-7e0f-4a10-9b21-5c9d",
    "user": {
      "email": "<sha256>",
      "phone": "<sha256>",
      "external_id": "<sha256>",
      "ip": "203.0.113.42",
      "user_agent": "Mozilla/5.0 (iPhone…)",
      "ttclid": "E.C.P.v3fQ…",
      "ttp": "94e2a4j9-h3ss-…"
    },
    "properties": {
      "currency": "USD",
      "value": 99.99,
      "order_id": "ORDER-10045",
      "contents": [{
        "content_id": "SKU_123",
        "content_name": "Blue Widget",
        "quantity": 1,
        "price": 99.99
      }]
    },
    "page": {
      "url": "https://example.com/ty",
      "referrer": "https://example.com/checkout"
    },
    "limited_data_use": false
  }]
}
```

Remove `test_event_code` before promoting to production. Store the access token in AWS Secrets Manager, not in source.

## Standard events — use the official taxonomy

Use TikTok's standard event names when possible; custom events get weaker attribution. Core set:
- `ViewContent` — landing page view with product context
- `ClickButton` — primary CTA click
- `SubmitForm` — form submission
- `CompleteRegistration` — account creation
- `Lead` — qualified lead captured
- `AddToCart`, `InitiateCheckout`, `AddPaymentInfo`, `Purchase` — e-commerce funnel
- `Subscribe` — subscription or recurring billing signup
- `Contact` — contact form or inquiry

## Attribution windows

As of the November 2025 Attribution Manager:
- **Click-through**: 1 day / 7 days / 14 days / **28 days** (28-day added in 2025)
- **View-through**: off / 1 day / 7 days
- **Engaged-view-through**: 1 day / 7 days (6-second watch threshold)

Default to **7-day click + 1-day view**. Attribution windows are immutable once an ad group ships — set them before launch.

## Gateway patterns — pick one

### Pattern A: Vendor-hosted Events API gateway
Stape, Elevar, TAGGRS. Best when TikTok is primary, stack is Shopify / WooCommerce, and the team doesn't have platform-engineering depth. Monthly fee; minimal engineering burden.

### Pattern B: Server-side GTM with `tiktok/gtm-template-eapi`
Best when running multi-platform CAPI (Meta + Google + TikTok) under one event governance layer. Requires running sGTM on your own infrastructure — on AWS, that's ECS Fargate or App Runner behind a subdomain like `sgtm.yourdomain.com`.

### Pattern C: Direct Lambda@Edge on the apex domain
Best for engineering-led teams who want:
- First-party cookie lifetime extension (the `/px/events` endpoint can set cookies with `Set-Cookie` headers on the apex, sidestepping ITP's 7-day cap on client-set cookies).
- Data residency control.
- IAM-scoped secrets (token lives in Secrets Manager, never in a config panel).
- No ongoing vendor fee.

The Lambda@Edge function receives a client beacon, hashes the EMQ fields, enriches with server-side data (IP, UA, ttclid from cookie), and forwards to TikTok's `/event/track/`. Cold start ~200 ms, warm ~20 ms.

## SKAdNetwork / AdAttributionKit

TikTok supports AdAttributionKit (the Apple successor to SKAN, as of iOS 17.4+). This is an app-install attribution mechanism, not a web-conversion one — relevant only when the TikTok ad objective is app installs or app events.

The Kochava real-time iOS partnership (October 2025) cut postback latency from 24–72 h to near-real-time for apps using it. If the client runs an app with Kochava as their MMP, recommend enabling the partnership.

For **web** conversions (the primary use case for landing pages), SKAN is irrelevant; the Events API is the entire signal pipeline.

## Debugging checklist — when conversions disappear

1. **Is the Pixel firing at all?** Test Events tab in TikTok Events Manager. If nothing arrives, it's a load / CSP / consent issue.
2. **Is the Pixel firing but Events API isn't?** Check the Lambda / sGTM / gateway logs for the `/track/` response. A `code: 0` response with `request_id` means TikTok accepted it.
3. **Both firing but no dedupe?** Check that `event_id` is identical in both payloads. Most common bug: generating a new UUID on each side instead of sharing one.
4. **Dedupe rate too high (>90%)?** Server channel is under-firing. Probably the Lambda is erroring silently or consent gating is stopping the server call that should have run after consent.
5. **Dedupe rate too low (<60%)?** `event_id` wiring is broken — you're sending the same event twice without proper ID sharing.
6. **EMQ low?** Add more fields. Phone + email + IP + UA + `ttclid` should get Purchase to ≥ 8.0.
7. **Conversions delayed in reporting?** Normal — server events can take up to 2 hours to appear in Ads Manager; attribution reconciliation happens on a longer window.

## Meta CAPI — the key differences

When the same page is serving Meta traffic too:
- Meta uses `eventID` (camelCase) vs TikTok's `event_id` (snake_case). Send both.
- Meta's `fbp` / `fbc` cookies are the equivalent of TikTok's `_ttp` / `ttclid`.
- Meta's Conversions API endpoint: `https://graph.facebook.com/v18.0/<PIXEL_ID>/events`.
- Meta supports Consent Mode v2 signals (`gdpr`, `gdpr_consent`, `tracking_allowed`); TikTok does not.

A single server-side handler can fan out to both. Share the event object, adapt the keys per platform.

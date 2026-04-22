# TikTok In-App Browser — technical reference

Read this file when debugging or designing for the TikTok IAB specifically: UA detection, storage, viewport, media, payments, deep linking, JS injection, CSP.

## What it actually is

- **iOS:** custom `WKWebView` (not `SFSafariViewController`). TikTok retains full JavaScript-injection capability via `evaluateJavaScript:` and `WKUserScript`. As of iOS 14.3+, injection can be hidden from page JS using `WKContentWorld`.
- **Android:** Android System WebView wrapped as `BytedanceWebview` (not Chrome Custom Tabs).

The custom WKWebView is why TikTok is more hostile than Twitter or Reddit, which delegate to `SFSafariViewController` and inherit the system cookie jar, autofill, passkeys, and Apple Pay.

## User-agent detection

Do not rely on a single substring. Reliable regex for 2025–2026 builds:

```js
const isTikTokIAB = /\b(musical_ly|trill|BytedanceWebview|TikTokOSBrowser|Bytedance)\b|\bJsSdk\//i
  .test(navigator.userAgent);
```

Tokens in the wild:
- Western builds: `musical_ly_43.x`
- Asian builds: `trill_43.x`
- Android appends `BytedanceWebview/<hash>` and `; wv)`
- Every TikTok UA carries `JsSdk/1.0` or `JsSdk/2.0` — a token never seen in real Safari or Chrome
- `TikTokOSBrowser` alone is unreliable; rare in production UAs

Server-side definitive signal on Android (when not suppressed by Android 13+ privacy opt-out): header `X-Requested-With: com.zhiliaoapp.musically`.

## Storage, cookies, identity

Each WKWebView has its own `WKHTTPCookieStore`. A user logged into your site in Safari is anonymous inside the TikTok IAB.

- **ITP is on** and cannot be disabled by the embedder. Third-party cookies fully blocked. Client-set first-party cookies capped at 7 days.
- **Android WebView** blocks third-party cookies by default; TikTok enables them for its own Pixel only.
- `localStorage` / `sessionStorage` / `IndexedDB` persist per-origin inside the IAB's jar but do not cross into Safari / Chrome.
- **Storage partitioning** (Chromium 115+, WebKit equivalent) applies — iframe state is keyed to the top frame.

Design every page for a logged-out, first-time user. Do not rely on recognized sessions, saved addresses, or cross-origin tokens.

## Viewport — the specific breakage

`100vh`, `100svh`, `100lvh`, and `100dvh` all collapse to the same dynamic value because TikTok's host app does not call `setMinimumViewportInset:maximumViewportInset:` on the WKWebView (WebKit bug 255852, open).

Layered fallback:

```css
.hero { height: 100vh; height: 100svh; height: calc(var(--vh, 1vh) * 100); }
```

```js
const setVh = () => document.documentElement.style.setProperty('--vh', `${innerHeight*0.01}px`);
setVh();
addEventListener('resize', setVh);
addEventListener('orientationchange', setVh);
```

Viewport meta: `<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,interactive-widget=resizes-content">`.

Pad bottom CTAs with `env(safe-area-inset-bottom)` + a buffer for TikTok's own bottom chrome (~60 px iOS, ~48 px Android).

Set `history.scrollRestoration = 'manual'` and restore scroll from `sessionStorage` — TikTok re-enters pages in fresh WebView instances and browser-native scroll restoration is unreliable.

Use `overscroll-behavior: none` on scrollable containers rather than trying to fight `scrollView.bounces`.

## Chrome eats the viewport

TikTok's IAB chrome takes ~120 px combined (top bar + bottom bar) on iPhone 12-class devices. Primary CTA must live above this line. If your hero section ends where Safari's fold would be, it is below the fold in TikTok.

## Media

- Autoplay requires **both** `muted` and `playsinline`. Media Engagement Index is always zero (no prior interaction history).
- Native HLS works on iOS; Android WebView needs `hls.js` with MSE.
- iOS Low Power Mode disables autoplay entirely. Ship a poster frame and fall back gracefully.

```html
<video autoplay muted playsinline loop preload="metadata" poster="/hero.jpg">
  <source src="/hero.mp4" type="video/mp4">
</video>
```

## Payments

- **Apple Pay on the web:** Safari and third-party-browser-only. `ApplePaySession.canMakePayments()` returns false in any WKWebView that has used `WKUserScript` (includes TikTok, Meta, Snap). iOS 18 extended Apple Pay to Chrome/Firefox but NOT to embedded WKWebViews.
- **Google Pay via `PaymentRequest`:** not exposed to Android WebView. Stripe Express Checkout Element silently hides the buttons.
- **Stripe Link:** works, but device-remembrance cookie is partitioned — users re-OTP every session. If the OTP email opens in Gmail's own IAB, the original Link tab is destroyed.

Default posture on TikTok traffic: **Stripe Checkout (hosted)**. Render a prominent "Open in Safari / Chrome for Apple Pay" escape.

Escape patterns:
- **Android:** `intent://<url>#Intent;scheme=https;package=com.android.chrome;end` opens in Chrome reliably.
- **iOS:** no reliable programmatic escape. Instruct the user to tap ⋯ → Open in Safari. The three-dot option exists in most 2025–2026 iOS builds but varies by version and region — do not script against its presence.

Register every origin (production, staging, preview) in the Stripe Dashboard payment-method-domain list. Host `.well-known/apple-developer-merchantid-domain-association` before debugging why Apple Pay doesn't render in the system browser either.

## Deep links

- `tel:`, `mailto:`, `sms:` — hand off cleanly on both iOS and Android.
- App Store / Play Store — work.
- Universal Links / App Links to **other** apps — unreliable from within TikTok. Always provide a fallback store URL and a visible "Open in app" button.

## JavaScript injection — what you're up against

Felix Krause's 2022 InAppBrowser.com research observed TikTok iOS injecting `keypress`, `keydown`, and click listeners plus `elementFromPoint` lookups — functionally a keylogger. TikTok said the code was for debugging. No independent 2024–2026 re-audit has been published; Krause's post is flagged outdated and he predicts migration to invisible `WKContentWorld` injection.

**Operational assumption:** injection capability is unchanged or has become undetectable. CSP does not block host-app injection — scripts run in an isolated world outside your policy.

Consequences:
- Do not capture full PANs, full SSNs, driver's license numbers, or equivalent sensitive PII in-page inside TikTok's IAB. Route to Stripe Checkout or an equivalent hosted flow.
- Consider what a keylogger could reconstruct from the form. Addresses and phone numbers are usually acceptable; credentials and payment data are not.

## CSP that keeps Pixel + CAPI working

```
script-src 'self' https://analytics.tiktok.com https://*.tiktok.com;
connect-src 'self' https://analytics.tiktok.com https://*.tiktok.com https://mssdk.tiktokw.us;
img-src 'self' data: https://analytics.tiktok.com https://*.tiktok.com;
frame-src https://*.tiktok.com;
```

Do not use `sandbox` on the top document. Be cautious with `require-trusted-types-for 'script'`. Never fall back to http pixel endpoints when `upgrade-insecure-requests` is set.

## Form quirks

- `autocomplete` attributes (`email`, `tel`, `given-name`, `family-name`, `postal-code`, `new-password` / `current-password`) are the only path to iCloud Keychain and 1Password inside WKWebView. Use them rigorously.
- Keyboard resize triggers `resize` events; make sure your `--vh` handler runs on every resize, not just on orientation change.
- Focus loss on fixed-position elements when the software keyboard appears is a known WebKit issue. Use `position: sticky` where possible, or detach fixed elements on focus.

## What breaks that you would not expect

- Service workers — may register but caching behavior under storage partitioning is unreliable. Do not depend on offline-first.
- Passkeys and WebAuthn — available but the credential jar is partitioned; a passkey created in Safari is not visible in TikTok's IAB.
- `window.open()` in a new tab — TikTok opens it inline, same WebView, replaces current page. Design with this in mind or use `target="_top"`.
- File upload (`<input type="file">`) — works on both platforms but camera access is gated by OS permission dialogs that may appear behind the host-app chrome.

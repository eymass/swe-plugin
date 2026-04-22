# Other in-app browsers — hostility map

Read this file when the user asks about a non-TikTok surface, or when deciding whether a TikTok mitigation needs to apply to another platform.

## The ranking

| App | UA signal | Engine iOS / Android | JS injection | Payments friendly? |
|---|---|---|---|---|
| **TikTok** | `musical_ly` / `trill` / `BytedanceWebview` / `JsSdk/` | WKWebView / WebView | **Yes** (confirmed 2022, assume ongoing) | **No** — Apple Pay blocked, Google Pay blocked |
| **Facebook** | `FBAN/FBIOS` · `FB_IAB/FB4A` | WKWebView / WebView | **Yes** (Meta `pcm.js`) | **No** — Apple Pay blocked |
| **Instagram** | `Instagram <ver>` | WKWebView / WebView | **Yes** (same Meta stack) | **No** |
| **Messenger** | `FBAN/MessengerForiOS` · `FB_IAB/Orca-Android` | WKWebView / WebView | **Yes** | **No** |
| **Snapchat** | `Snapchat/<ver>` | WKWebView / WebView | **Yes** | **No** |
| **Pinterest** | `[Pinterest/iOS]` · `[Pinterest/Android]` | WKWebView / WebView | Limited | **No** |
| **LinkedIn** | `LinkedInApp` (iOS only) | WKWebView / Chrome Custom Tabs | iOS yes, Android no | Android yes, iOS no |
| **X / Twitter** | No distinguishing token — looks like Safari | **SFSafariViewController** / Chrome Custom Tabs | **No** | **Yes** |
| **Reddit** | No distinguishing token on link taps | **SFSafariViewController** / Chrome Custom Tabs | **No** | **Yes** |
| **YouTube** | Opens system browser for external links | Safari / Chrome | **No** | **Yes** |

## How to group them operationally

**Tier 1 — hostile (design defensively):**
- TikTok
- Facebook / Instagram / Messenger
- Snapchat
- Pinterest

These use custom WKWebViews or wrapped WebViews, inject scripts, break Apple/Google Pay, and isolate storage. Build for TikTok first; the mitigations cover this entire tier as a superset.

**Tier 2 — mixed (check per platform):**
- LinkedIn (hostile on iOS, friendly on Android because Android uses Chrome Custom Tabs)

**Tier 3 — friendly (treat like a system browser):**
- X / Twitter
- Reddit (official app)
- YouTube (delegates to system browser for external links)

These use `SFSafariViewController` on iOS and Chrome Custom Tabs on Android. They inherit the system cookie jar, autofill, passkeys, and Apple/Google Pay. A standard mobile web page works without special handling.

## UA detection regex for each

```js
const iabDetectors = {
  tiktok: /\b(musical_ly|trill|BytedanceWebview|TikTokOSBrowser|Bytedance)\b|\bJsSdk\//i,
  facebook: /\b(FBAN|FBAV|FB_IAB|FB4A)\b/,
  instagram: /\bInstagram\b/,
  messenger: /\bMessengerForiOS|\bOrca-Android\b/,
  snapchat: /\bSnapchat\b/,
  pinterest: /\[Pinterest\/(iOS|Android)\]/,
  linkedin: /\bLinkedInApp\b/,
  // X/Twitter, Reddit, YouTube do not leave a reliable UA marker on link taps
};

const isAnyHostileIAB = (ua = navigator.userAgent) =>
  iabDetectors.tiktok.test(ua) ||
  iabDetectors.facebook.test(ua) ||
  iabDetectors.instagram.test(ua) ||
  iabDetectors.messenger.test(ua) ||
  iabDetectors.snapchat.test(ua) ||
  iabDetectors.pinterest.test(ua);
```

## Meta's specifics (Facebook / Instagram / Messenger / Threads)

- Meta injects `pcm.js` (Pixel Compatibility Module) and other scripts into hosted pages.
- The Meta Pixel loaded inside a Meta IAB has slightly different deduplication behavior than TikTok's — Meta uses event name + user data + timestamp within a 48-hour window, not an explicit `event_id` (though `eventID` is supported via Conversions API).
- Apple Pay is blocked in all Meta WKWebViews. Google Pay in Android Meta WebView is blocked.
- Meta's "Open in Browser" option is present but less discoverable than TikTok's; positioned in the ⋯ menu.
- Third-party cookies: blocked on iOS, blocked on Android WebView by default.

Practical rule: if the page is designed for TikTok IAB, it works in Meta's family. The reverse is not always true (Meta's scripts are less aggressive than TikTok's).

## Snapchat specifics

- Autoplay video restrictions are stricter — Snap sometimes blocks even `muted + playsinline`. Test explicitly.
- Form UX inside Snap is the worst of the tier: scroll jank when keyboard opens is more pronounced.
- TikTok mitigations otherwise transfer directly.

## LinkedIn — the split brain

- **iOS:** `LinkedInApp` WKWebView. Hostile. Apply TikTok mitigations.
- **Android:** Chrome Custom Tabs (since 2021–2022). Friendly. No special handling needed.

Detection alone is not enough — branch on platform:

```js
const isLinkedInIOSApp = /\bLinkedInApp\b/.test(navigator.userAgent)
  && /iPhone|iPad|iPod/.test(navigator.userAgent);
```

## Twitter, Reddit, YouTube

The official Twitter (X), Reddit, and YouTube apps delegate to `SFSafariViewController` on iOS and Chrome Custom Tabs on Android for external link taps. The UA looks like plain Safari or Chrome; there is no IAB token.

This means:
- Apple Pay and Google Pay work.
- Autofill and passkeys work.
- Third-party cookies follow the system browser's settings.
- No JS injection.

**Do not over-engineer for these.** A normal mobile web page is correct.

Caveat: Reddit's third-party apps (Apollo historical, Boost, Infinity) may use custom WebViews. Production traffic from those is negligible; ignore.

## Email clients (Gmail app, Outlook app)

Not ad surfaces, but they matter for confirmation / OTP flows. Gmail's Android app uses its own IAB that breaks Stripe Link OTPs and email-based magic links — when the user taps the OTP link, it opens in Gmail's IAB in a fresh WebView instance, disconnected from the original checkout tab. Mitigation: use in-page codes (numeric OTPs typed into the original tab) rather than magic-link redirects on any paid-social funnel.

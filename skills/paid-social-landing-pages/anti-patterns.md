# Anti-patterns — what to refuse and how to redirect

Read this file when the user proposes something that violates the skill's rules, or when reviewing a plan that has a common pitfall. Each item below is a request you should push back on, with the reason and the replacement.

## "We'll add the Pixel / Events API later, let's just ship."
**Why refuse:** iOS 14.5+ ATT and ITP drop 25–40% of client-only events. "Later" means weeks of paid-media spend attributed incorrectly, which means the TikTok optimizer learns on bad signal and your CPAs degrade.
**Replacement:** Pixel goes in day one with consent gating. Events API goes in day one, sharing a UUID `event_id` with the Pixel. Test Event Code validates before production flip.

## "Lighthouse says 98, we're fine on performance."
**Why refuse:** Lighthouse is a lab tool simulating a throttled Moto G4 in Chrome. Your paid-social users are on a mid-tier Android on 4G inside a WKWebView with host-app JS injection, third-party script pile-up, and cold caches. Lab scores don't translate.
**Replacement:** Measure with RUM. CloudWatch RUM or Sentry Performance. p75 on real devices in the IAB is the truth.

## "Google Tag Manager can handle all of this client-side."
**Why refuse:** Client GTM in 2026 means 50–100 KB of extra JS on the main thread, and every Pixel loaded through GTM inherits the client-side signal loss. GTM is not a substitute for server-side CAPI.
**Replacement:** Server-side GTM (sGTM) on AWS ECS Fargate, or a direct Lambda@Edge CAPI relay. Client GTM is acceptable for analytics (GA4) but not for the primary ad-platform pixels.

## "We don't need a privacy policy, it's just a landing page."
**Why refuse:** TikTok will reject the ad, full stop — the Ad Review Checklist explicitly requires a privacy policy reachable from every page. You'll also be out of compliance with GDPR, CCPA, and state privacy laws, exposing the business to fines. This isn't an engineering preference; it's a launch blocker.
**Replacement:** Privacy policy, terms, contact info, refund/shipping policy (for e-commerce), and a consent mechanism, all linked from the footer of every page on the domain.

## "The hero video won't autoplay, let's just set autoplay=true."
**Why refuse:** Autoplay on iOS requires **both** `muted` and `playsinline`. Just `autoplay=true` silently fails. Also, iOS Low Power Mode disables autoplay entirely — a meaningful fraction of mobile users.
**Replacement:** `<video autoplay muted playsinline loop preload="metadata" poster="/hero.jpg">` with a poster frame for Low Power Mode.

## "Let's use reCAPTCHA v3 to gate the form."
**Why refuse:** Google has been systematically scoring legitimate WebView users at 0.3 or lower since mid-2025 — no session cookies in the partitioned IAB jar, fresh fingerprint every visit, UA flags (`wv`, `FBAN`, `musical_ly`) trigger the risk model. Your conversion rate will crater.
**Replacement:** Cloudflare Turnstile (free, unlimited, IAB-native) + AWS WAF Bot Control at the edge + rate limiting. hCaptcha as a drop-in alternative.

## "Why do we need to test on a real phone? We have BrowserStack."
**Why refuse:** BrowserStack doesn't simulate TikTok's or Meta's custom WebViews. The quirks you're testing for — JS injection, storage partitioning, viewport collapse, Apple Pay failure, Stripe Link OTP break — are specific to the host-app WebView wrapper, not a generic iOS WebView. Emulated environments give false green lights.
**Replacement:** A dedicated iPhone and Android device per team, running the actual TikTok, Meta, and Snap apps. QA loads the page via a test ad (small budget) or via the "Send to phone" dev-tools flow.

## "Let's embed the checkout form inline so the user doesn't leave the site."
**Why refuse:** Inside a TikTok or Meta IAB, the host app can observe keystrokes. Collecting full PANs, SSNs, or other sensitive PII in your own DOM exposes the user and the business. Also: Apple Pay and Google Pay buttons will not render, so the user loses the fastest checkout paths.
**Replacement:** Stripe Checkout (hosted). The redirect to `checkout.stripe.com` breaks out of TikTok's IAB on most 2025–2026 iOS builds, enabling Apple Pay. On Android, it's a clean redirect.

## "Let's use 100dvh for the hero, that fixes the viewport issue."
**Why refuse:** Inside TikTok's IAB, `100vh`, `100svh`, `100lvh`, and `100dvh` all collapse to the same dynamic value because the host app doesn't call `setMinimumViewportInset`. `dvh` alone does not fix it (WebKit bug 255852).
**Replacement:** Layered fallback — `height: 100vh; height: 100svh; height: calc(var(--vh, 1vh) * 100);` — plus a JS listener that sets `--vh` on resize and orientationchange.

## "Let's put the primary CTA below the hero so the user has to scroll."
**Why refuse:** TikTok's IAB chrome eats ~120 px (top bar + bottom bar) on iPhone 12-class devices. If the CTA requires a scroll to become visible, you lose 30–50% of clicks. Friction is not engagement.
**Replacement:** Primary CTA above the IAB fold, with a sticky bottom CTA after scroll for redundancy.

## "Let's use a service worker to cache the pixel and make it offline-capable."
**Why refuse:** Service workers registered inside a WebView face partitioned storage. Behavior is unreliable across IAB sessions. Adds complexity with little reward for a lander.
**Replacement:** Standard HTTP caching (`Cache-Control: immutable` on hashed assets) is sufficient. Service workers are for PWAs, not ad landers.

## "Let's add a countdown timer to create urgency."
**Why refuse:** If the timer doesn't actually trigger anything (price goes up, offer expires, inventory runs out), it's a dark pattern. TikTok's AI review flags fake urgency and rejects the ad.
**Replacement:** Real urgency or no urgency. If the sale actually ends at a time, show a real countdown tied to that time. If not, remove it.

## "Let's store the conversion ID in localStorage so we can track returning users."
**Why refuse:** IAB localStorage is partitioned. A user returning in Safari won't share state. You'll undercount returns and double-count "new" users.
**Replacement:** Server-side identity — ask for email, look up in CRM, link via `external_id` in the CAPI payload.

## "Let's add `crossorigin` to all our scripts for performance."
**Why refuse:** `crossorigin` on scripts you serve yourself does nothing. On third-party scripts, it enables proper error reporting (critical) but requires the third-party to set the CORS header (not always the case). Applied blanket, it can break things.
**Replacement:** `crossorigin` on third-party scripts and CDN fonts where the provider supports it. Not on same-origin scripts.

## "Let's use AMP for our landers."
**Why refuse:** AMP is not required for TikTok (it was a Google-ads thing, now deprecated by Google too). AMP forces constraints that limit what you can do with Pixel / CAPI / experimentation. In 2025–2026, there is no scenario where AMP is the right answer for a new paid-social LP.
**Replacement:** Static HTML or Astro. You'll get better CWV than AMP without the straitjacket.

## "Let's block all bots at WAF to save bandwidth."
**Why refuse:** Blocking `TikTokBot`, `facebookexternalhit`, `Meta-ExternalAgent`, `LinkedInBot`, `Twitterbot` breaks OG preview card rendering. Your ad thumbnails disappear. Your click-through rate craters.
**Replacement:** Allowlist the known social crawlers. Bot Control in WAF handles the rest (scrapers, credential-stuffing tools).

## "Let's deploy on Friday at 5 PM, the code's ready."
**Why refuse:** If something breaks, nobody is around to roll back. Paid-social campaigns spend money 24/7. A broken LP with active ad spend burns through budget until Monday.
**Replacement:** Deploy Tuesday or Wednesday morning. Pre-baked rollback command in the runbook (`aws cloudfront update-distribution --id ... --distribution-config file://previous-config.json`). Soft launch at 1–5% traffic before full cutover.

## "Let's A/B test the page with VWO's visual editor."
**Why refuse:** VWO / Optimizely / AB Tasty client-side visual editors ship a SDK that evaluates variants in the browser, delaying paint by 100–500 ms. LCP tanks. Their cookies fail under storage partitioning. Test quality collapses.
**Replacement:** Edge-bucketed variants via CloudFront Functions + KeyValueStore. Zero client JS, zero render delay. Variant is decided at the edge; origin serves pre-rendered HTML per variant.

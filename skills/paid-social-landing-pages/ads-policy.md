# TikTok ad policy + creative-to-LP match

Read this file before building a page, when reviewing a creative brief, or when an ad gets rejected for landing-page reasons.

## The top-level rule

TikTok's Misleading Content policy requires the landing page to match the ad on offer, price, promotion, product, and disclaimers. The top rejection trigger in TikTok's September 2025 Ad Review Checklist is literally:

> "your ad creative is not consistent with the products or services on the landing page"

**Every brief review starts with:** does the hero, price, claim, and CTA on the LP mirror the ad? If not, fix the LP or kill the creative. Don't waste code on a mismatch — it won't serve.

## Prohibited globally (do not try)

- Illegal goods and services
- Weapons, ammunition, explosives
- Counterfeit or infringing goods
- Deceptive financial schemes (binary options, Ponzi, pyramid)
- Drugs, drug paraphernalia
- Tobacco, e-cigarettes, vaping
- Adult content, sexual services
- Political and issue ads (varies by country — default prohibited)
- Hate content, harassment
- Prescription medications
- Steroids, SARMs, unapproved supplements
- Unlicensed medical devices

If the brief is in any of these categories, stop. No LP engineering will make the ad serve.

## Restricted (allowlist + licensing required)

These verticals can run but require TikTok sales-rep approval, licensing docs, and geo restrictions. Ship the LP only once the allowlist is confirmed.

| Vertical | Gating |
|---|---|
| Alcohol | 25+ (US/CA), brand-only creative, no delivery-commerce CTAs |
| Gambling | Licensed operators, 18/21+ by geo |
| Financial services (incl. crypto) | US/CA in limited beta, Europe varies by country |
| Weight management | No before/after imagery, no guaranteed results, no negative body imagery, 18+ |
| Healthcare / pharma | OTC varies by market, prescription forbidden, CBD sales-rep only |
| Dating | 18+, hetero/same-sex categories flagged separately |

**Before/after imagery is prohibited across beauty, health, and weight-loss verticals** — AI review flags it in 2025. Do not render beauty transformation grids or weight-loss progress photos. Testimonial video works; side-by-side photography does not.

## Functional LP requirements

A page that loads correctly but violates any of these gets the ad rejected:

- Loads inside the IAB (no redirect-to-app-only, no "desktop-only" pages)
- Mobile-first (responsive, no horizontal scroll on iPhone viewport)
- No auto-download (starting file downloads on load is an instant rejection)
- No auto-dial (`tel:` on load)
- No forced app-store redirect (user must be able to see the LP before being offered the app)
- No dark patterns: fake close buttons, fake system notifications, fake play buttons, countdown timers that don't count down, fake "only 3 left!" when inventory is unlimited
- Pricing and shipping clearly visible before checkout
- Language matches the target geo (English ad to US, English LP — not Russian LP)
- **No prohibited products anywhere on the domain**, even if not advertised (the reviewer browses the whole domain from the LP)
- No sensitive-data request gate to access the site (email wall before seeing the offer is not acceptable)

## Mandatory pages

Every LP domain must have, reachable from every page:
- **Privacy policy** disclosing TikTok and ByteDance as data recipients where applicable
- **Terms of service**
- **Contact information** — physical address and working email, especially for e-commerce
- **Refund and shipping policy** — for any commerce
- **Consent mechanism** — reachable from every page (CMP or equivalent)

The CMP must actually gate the Pixel. Reviewers check.

## AI-generated content

Since 2024, TikTok Ads Manager has an AI-generated-content toggle. Required for:
- Realistic AI voices (synthetic voice that sounds human)
- Realistic AI likenesses (synthetic faces or bodies)
- Fully AI-generated talent

**Unauthorized celebrity likeness, deepfakes, and AI-cloned voices of real people are instant rejections** and can risk account suspension. Do not render any recognizable public figure without license. Custom illustration styles that are obviously AI are fine with the toggle enabled.

## Creative-to-LP match — concrete checks

For each campaign brief, verify:

1. **Headline consistency** — the LP hero text matches the ad's primary claim. If the ad says "50% off your first order," the LP has "50% off your first order" in the hero, not "save big on your first order."
2. **Price consistency** — if the ad shows $29.99, the LP shows $29.99 at the same SKU / bundle. Any hidden upcharge (shipping, fees) must be disclosed before the primary CTA.
3. **Product consistency** — the hero visual on the LP is the same product/service featured in the ad. A demo-video ad that leads to a product catalog is a mismatch.
4. **Promotion consistency** — the discount code or offer mentioned in the ad is applied automatically or clearly displayed.
5. **Disclaimer consistency** — any "results not typical" or eligibility language in the ad appears on the LP too.

If the campaign runs multiple creatives against one LP, the LP must match the *union* of creative claims, or the creatives must be split across dedicated LPs. When in doubt, one LP per creative concept.

## Common rejection reasons and fixes

| Rejection | Cause | Fix |
|---|---|---|
| "Landing page does not match ad creative" | Mismatch above | Split into per-creative LPs or rewrite hero |
| "Misleading business practices" | Dark pattern detected (fake urgency, hidden fees) | Remove fake timer, surface fees |
| "Prohibited product" | Something on the domain, not necessarily the LP | Audit the whole domain — restricted products must be removed or excluded from serving |
| "Restricted business without approval" | Vertical requires allowlist | Work with TikTok sales rep first, then ship |
| "Poor landing page experience" | Slow load, broken page, unreadable | CWV audit (see `performance-monitoring.md`) |
| "Inappropriate content" | Before/after, negative body imagery | Replace with testimonial or product shot |
| "Trademark / IP violation" | Unauthorized brand or celebrity use | Remove, use original imagery |

## Geo targeting and LP variants

- Language: LP language matches ad-group geo. If running in Germany, the LP is German; an English LP with a German ad gets rejected.
- Currency: prices display in the geo's currency. USD on a UK campaign is a rejection.
- Legal disclaimers: varies by country (e.g., Germany requires Impressum; EU requires GDPR-compliant CMP).

Ship geo variants via CloudFront Functions that route by `CloudFront-Viewer-Country` header to per-locale HTML files or query params.

## Policy resources

- [TikTok Ads Manager Landing Page Best Practices](https://ads.tiktok.com/help/article/ad-review-checklist-landing-page)
- [TikTok Advertising Policies — Industry Entry](https://ads.tiktok.com/help/article/tiktok-advertising-policies-industry-entry)
- [TikTok Branded Content Policy](https://ads.tiktok.com/help/article/branded-content-policy)

Search TikTok's help center for "Ad Review Checklist" and read the current version before each new campaign — policy updates publish quarterly and the checklist is the canonical source.

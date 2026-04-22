# CloudFront Functions — Routing Patterns

Complete, copy-paste-ready CloudFront Function code for every silent routing pattern. Every example attaches to the **viewer-request** event unless stated otherwise. Every example uses URI rewriting (not redirects) so the client never sees the URL change.

## Table of contents

1. [Runtime notes and constraints](#runtime-notes)
2. [Path-based routing (cache behaviors only, no function)](#path-based)
3. [Geo-based routing (country / region)](#geo)
4. [Cookie-based routing (A/B bucketing, returning-user variants)](#cookie)
5. [UTM / query-param routing (campaign variants)](#utm)
6. [IP-based routing (allow-lists, partner variants)](#ip)
7. [Device-based routing (mobile vs desktop)](#device)
8. [Composite routing (geo + A/B bucket)](#composite)
9. [Cache policy configuration for each pattern](#cache-policies)
10. [Deployment via AWS CLI](#deploy)
11. [Testing](#testing)

---

## <a name="runtime-notes"></a>1. Runtime notes and constraints

CloudFront Functions limits you need to know:

- **Max CPU time**: 1ms (typical), hard cap a few ms
- **Max memory**: 2MB
- **Max function size**: 10KB compiled
- **No network access**, no filesystem, no persistence
- **Runtime**: JavaScript runtime 2.0 (ES6+, `import cf from 'cloudfront'` for helpers)
- **Events**: `viewer-request`, `viewer-response` only (use Lambda@Edge for origin-request / origin-response)
- **KV Store** (optional): up to 5MB per function for lookup tables — useful for CIDR tables, country → variant maps

If you need more than that (network, large code, Node runtime), use Lambda@Edge. But 95% of landing-page routing fits in CF Functions.

**Always use runtime 2.0.** Runtime 1.0 is legacy; runtime 2.0 supports origin modification, KV Store, and modern JS.

---

## <a name="path-based"></a>2. Path-based routing — cache behaviors only

This is the simplest case and **does not need a function**. Use it when different URL paths should hit different S3 buckets.

**Scenario**: `example.com/` serves the main landing page; `example.com/promo/*` serves a separate campaign page from a separate bucket.

**Setup**:
- Origin A: `landing-main-prod.s3.us-east-1.amazonaws.com` (default)
- Origin B: `landing-promo-prod.s3.us-east-1.amazonaws.com`

**Behaviors** (order matters — CloudFront matches top-down):

| Precedence | Path pattern | Origin   | Cache policy       |
| ---------- | ------------ | -------- | ------------------ |
| 1          | `/promo/*`   | Origin B | CachingOptimized   |
| Default    | `*`          | Origin A | CachingOptimized   |

**Gotcha**: CloudFront sends the full URI to the origin. If Origin B's bucket doesn't have a `/promo/` prefix in its keys, requests for `/promo/index.html` will 404. Fix with a CloudFront Function that strips the prefix:

```javascript
function handler(event) {
  var req = event.request;
  // Strip leading /promo before forwarding to Origin B
  req.uri = req.uri.replace(/^\/promo/, '') || '/';
  if (req.uri.endsWith('/')) req.uri += 'index.html';
  return req;
}
```

Attach to the `/promo/*` behavior as viewer-request.

---

## <a name="geo"></a>3. Geo-based routing

**Scenario**: Same URL (`example.com/`), different HTML per country. Israeli users get Hebrew variant; German/Austrian/Swiss users get German variant; everyone else gets the English default.

**S3 layout**:
```
landing-main-prod/
├── variants/default/index.html
├── variants/default/app.a3f9.js
├── variants/il/index.html
├── variants/il/app.b7c2.js
├── variants/de/index.html
└── variants/de/app.c4e1.js
```

**Function** (attach to default behavior, viewer-request):

```javascript
function handler(event) {
  var req = event.request;
  var uri = req.uri;

  // Only rewrite root / index requests; let asset paths pass through
  if (uri !== '/' && uri !== '/index.html') return req;

  var countryHeader = req.headers['cloudfront-viewer-country'];
  var code = countryHeader ? countryHeader.value : 'US';

  var variant = 'default';
  if (code === 'IL') variant = 'il';
  else if (code === 'DE' || code === 'AT' || code === 'CH') variant = 'de';
  // extend as needed

  req.uri = '/variants/' + variant + '/index.html';
  return req;
}
```

**Cache policy** (critical): include `CloudFront-Viewer-Country` in the cache key. Without this, the first user's variant gets cached and served to everyone.

See [Cache policy configuration](#cache-policies) below.

**Also update the CloudFront distribution's origin request policy** to forward `CloudFront-Viewer-Country` so the function receives it. Use the managed policy **Managed-CORS-S3Origin** + a custom policy, or the AWS-managed `AllViewerExceptHostHeader`.

**Asset paths**: because assets are under `/variants/<locale>/app.xxx.js`, the HTML must reference them with the correct prefix. Build-time: generate per-variant HTML with the right `<script src>` paths. Don't try to rewrite asset URIs in the function — you'll blow through the 1ms CPU budget.

---

## <a name="cookie"></a>4. Cookie-based routing — A/B testing and returning-user variants

**Scenario**: New visitors are randomly assigned to variant A or B and stickied with a cookie. On return, they see the same variant.

**Function** (viewer-request on default behavior):

```javascript
function handler(event) {
  var req = event.request;
  if (req.uri !== '/' && req.uri !== '/index.html') return req;

  var cookies = req.cookies || {};
  var bucket = cookies['ab_bucket'] && cookies['ab_bucket'].value;

  // If no bucket cookie, assign one based on a hash of the viewer IP + UA
  // (CF Functions can't set cookies with Set-Cookie on the request path;
  //  instead, let the origin's HTML set it, or use a viewer-response function)
  if (bucket !== 'a' && bucket !== 'b') {
    // Deterministic bucketing on this request only; real stickiness happens on response
    var seed = (req.headers['user-agent'] ? req.headers['user-agent'].value : '') +
               (event.viewer && event.viewer.ip ? event.viewer.ip : '');
    var hash = 0;
    for (var i = 0; i < seed.length; i++) hash = ((hash << 5) - hash + seed.charCodeAt(i)) | 0;
    bucket = (Math.abs(hash) % 2 === 0) ? 'a' : 'b';
  }

  req.uri = '/variants/' + bucket + '/index.html';
  // Pass the decision to the origin / response stage via a custom header
  req.headers['x-ab-bucket'] = { value: bucket };
  return req;
}
```

**Pair with a viewer-response function to set the sticky cookie**:

```javascript
function handler(event) {
  var res = event.response;
  var req = event.request;
  var bucket = req.headers['x-ab-bucket'] && req.headers['x-ab-bucket'].value;
  if (bucket && !(req.cookies && req.cookies['ab_bucket'])) {
    // 30-day sticky cookie
    res.headers['set-cookie'] = {
      value: 'ab_bucket=' + bucket + '; Path=/; Max-Age=2592000; Secure; SameSite=Lax'
    };
  }
  return res;
}
```

**Cache policy**: include cookie `ab_bucket` in the cache key. Bucket A and Bucket B will be cached separately.

---

## <a name="utm"></a>5. UTM / query-param routing — campaign-specific variants

**Scenario**: Paid ads pass `?campaign=spring25` or `?utm_content=hero-v2`. Serve a matching variant. Unknown / missing campaign → default.

```javascript
function handler(event) {
  var req = event.request;
  if (req.uri !== '/' && req.uri !== '/index.html') return req;

  var qs = req.querystring || {};
  var campaign = qs.campaign && qs.campaign.value;

  // Explicit allow-list — never trust arbitrary query params to build file paths
  var allowed = {
    'spring25': 'spring25',
    'blackfriday': 'bf2025',
    'webinar': 'webinar-q1'
  };

  var variant = (campaign && allowed[campaign]) || 'default';
  req.uri = '/variants/' + variant + '/index.html';
  return req;
}
```

**Security note**: the allow-list is mandatory. Never concatenate a user-supplied query param into a URI — you'll expose directory traversal (`?campaign=../private`) and let attackers probe your bucket.

**Cache policy**: include the `campaign` query string in the cache key. Strip all other query strings from the cache key to avoid cache explosion from ad tracking params (`fbclid`, `gclid`, `ttclid`, etc.).

---

## <a name="ip"></a>6. IP-based routing

**Scenario**: Corporate IP ranges see an internal/debug variant; specific partner CIDR sees a co-branded variant; everyone else sees default.

```javascript
function handler(event) {
  var req = event.request;
  if (req.uri !== '/' && req.uri !== '/index.html') return req;

  var ip = event.viewer && event.viewer.ip;
  if (!ip) return req;

  // Small allow-lists only — for bigger lists, use CloudFront KV Store
  var internal = ['203.0.113.', '198.51.100.'];   // prefix match
  var partner  = ['192.0.2.'];

  var variant = 'default';
  for (var i = 0; i < internal.length; i++) {
    if (ip.indexOf(internal[i]) === 0) { variant = 'internal'; break; }
  }
  if (variant === 'default') {
    for (var j = 0; j < partner.length; j++) {
      if (ip.indexOf(partner[j]) === 0) { variant = 'partner'; break; }
    }
  }

  req.uri = '/variants/' + variant + '/index.html';
  return req;
}
```

**For real CIDR matching** (not prefix strings), use the CloudFront KV Store — load a lookup structure at function init. Keep the data under 5MB. For massive IP lists (millions), use AWS WAF with an IP set instead and gate the behavior at that layer.

**Cache policy**: you generally do NOT want IP in the cache key (cache explosion). Instead, add a custom header `X-Variant-Bucket` in the function and include THAT in the cache key:

```javascript
req.headers['x-variant-bucket'] = { value: variant };
```

Then cache key = `x-variant-bucket`, which has only 3 possible values (internal/partner/default) → 3 cache entries total.

---

## <a name="device"></a>7. Device-based routing

**Scenario**: Mobile users get a lighter, tap-optimized variant; desktop users get the full experience.

Prefer responsive CSS. Only split at the edge when the creative team genuinely ships two distinct files.

```javascript
function handler(event) {
  var req = event.request;
  if (req.uri !== '/' && req.uri !== '/index.html') return req;

  var isMobile = req.headers['cloudfront-is-mobile-viewer'];
  var isTablet = req.headers['cloudfront-is-tablet-viewer'];

  var variant = 'desktop';
  if ((isMobile && isMobile.value === 'true') || (isTablet && isTablet.value === 'true')) {
    variant = 'mobile';
  }
  req.uri = '/variants/' + variant + '/index.html';
  return req;
}
```

Forward `CloudFront-Is-Mobile-Viewer` and `CloudFront-Is-Tablet-Viewer` in the origin request policy. Include both in the cache key.

---

## <a name="composite"></a>8. Composite routing — geo + A/B bucket

**Scenario**: Israeli users are A/B tested between two Hebrew variants; everyone else gets the English default.

```javascript
function handler(event) {
  var req = event.request;
  if (req.uri !== '/' && req.uri !== '/index.html') return req;

  var country = req.headers['cloudfront-viewer-country'];
  var code = country ? country.value : 'US';

  if (code !== 'IL') {
    req.uri = '/variants/default/index.html';
    req.headers['x-variant-bucket'] = { value: 'default' };
    return req;
  }

  // Israel: bucket into a or b
  var cookies = req.cookies || {};
  var bucket = cookies['ab_bucket'] && cookies['ab_bucket'].value;
  if (bucket !== 'a' && bucket !== 'b') {
    var ip = (event.viewer && event.viewer.ip) || '';
    var ua = (req.headers['user-agent'] && req.headers['user-agent'].value) || '';
    var seed = ip + ua;
    var h = 0;
    for (var i = 0; i < seed.length; i++) h = ((h << 5) - h + seed.charCodeAt(i)) | 0;
    bucket = (Math.abs(h) % 2 === 0) ? 'a' : 'b';
  }

  req.uri = '/variants/il-' + bucket + '/index.html';
  req.headers['x-variant-bucket'] = { value: 'il-' + bucket };
  return req;
}
```

Cache key: `X-Variant-Bucket` only (not country, not cookie). Three cache entries total: `default`, `il-a`, `il-b`.

---

## <a name="cache-policies"></a>9. Cache policy configuration

For geo routing, create a custom cache policy:

```bash
aws cloudfront create-cache-policy --cache-policy-config '{
  "Name": "LandingGeoCache",
  "DefaultTTL": 60,
  "MaxTTL": 3600,
  "MinTTL": 0,
  "ParametersInCacheKeyAndForwardedToOrigin": {
    "EnableAcceptEncodingGzip": true,
    "EnableAcceptEncodingBrotli": true,
    "HeadersConfig": {
      "HeaderBehavior": "whitelist",
      "Headers": { "Quantity": 1, "Items": ["CloudFront-Viewer-Country"] }
    },
    "CookiesConfig": { "CookieBehavior": "none" },
    "QueryStringsConfig": { "QueryStringBehavior": "none" }
  }
}'
```

For variant-bucket routing (the most efficient pattern):

```bash
aws cloudfront create-cache-policy --cache-policy-config '{
  "Name": "LandingVariantBucketCache",
  "DefaultTTL": 60,
  "MaxTTL": 3600,
  "MinTTL": 0,
  "ParametersInCacheKeyAndForwardedToOrigin": {
    "EnableAcceptEncodingGzip": true,
    "EnableAcceptEncodingBrotli": true,
    "HeadersConfig": {
      "HeaderBehavior": "whitelist",
      "Headers": { "Quantity": 1, "Items": ["X-Variant-Bucket"] }
    },
    "CookiesConfig": { "CookieBehavior": "none" },
    "QueryStringsConfig": { "QueryStringBehavior": "none" }
  }
}'
```

For UTM-driven variants:

```bash
aws cloudfront create-cache-policy --cache-policy-config '{
  "Name": "LandingCampaignCache",
  "DefaultTTL": 60,
  "MaxTTL": 3600,
  "MinTTL": 0,
  "ParametersInCacheKeyAndForwardedToOrigin": {
    "EnableAcceptEncodingGzip": true,
    "EnableAcceptEncodingBrotli": true,
    "HeadersConfig": { "HeaderBehavior": "none" },
    "CookiesConfig": { "CookieBehavior": "none" },
    "QueryStringsConfig": {
      "QueryStringBehavior": "whitelist",
      "QueryStrings": { "Quantity": 1, "Items": ["campaign"] }
    }
  }
}'
```

**Always prefer cache key on a function-produced header** (`X-Variant-Bucket`) over caching on many cookies/headers directly. This collapses cache entries to exactly the number of variants.

---

## <a name="deploy"></a>10. Deployment via AWS CLI

```bash
# 1. Create the function
aws cloudfront create-function \
  --name landing-router \
  --function-config 'Comment="Silent variant routing",Runtime=cloudfront-js-2.0' \
  --function-code fileb://router.js

# 2. Publish it (functions live in draft stage until published)
ETAG=$(aws cloudfront describe-function --name landing-router --query 'ETag' --output text)
aws cloudfront publish-function --name landing-router --if-match "$ETAG"

# 3. Associate it with the distribution (via update-distribution)
# Get the current config, edit the DefaultCacheBehavior.FunctionAssociations,
# and call update-distribution with --if-match <current ETag>

aws cloudfront get-distribution-config --id $DIST_ID > dist.json
# Extract ETag and Config, edit Config.DefaultCacheBehavior.FunctionAssociations:
# {
#   "Quantity": 1,
#   "Items": [{
#     "FunctionARN": "arn:aws:cloudfront::<acct>:function/landing-router",
#     "EventType": "viewer-request"
#   }]
# }
# Then:
aws cloudfront update-distribution \
  --id $DIST_ID \
  --if-match $(jq -r .ETag dist.json) \
  --distribution-config file://updated-config.json
```

Deployment takes 3-5 minutes to propagate to all edge locations.

---

## <a name="testing"></a>11. Testing

Test the function inline before publishing:

```bash
aws cloudfront test-function \
  --name landing-router \
  --if-match "$ETAG" \
  --event-object fileb://test-event.json \
  --stage DEVELOPMENT
```

`test-event.json` sample for geo routing:

```json
{
  "version": "1.0",
  "context": { "distributionId": "EXAMPLE123" },
  "viewer": { "ip": "203.0.113.10" },
  "request": {
    "method": "GET",
    "uri": "/",
    "querystring": {},
    "headers": {
      "host": { "value": "example.com" },
      "cloudfront-viewer-country": { "value": "IL" },
      "user-agent": { "value": "Mozilla/5.0" }
    },
    "cookies": {}
  }
}
```

Post-deploy verification:

```bash
# IL request
curl -H "CloudFront-Viewer-Country: IL" -sSI https://example.com/

# Verify the correct variant was served by checking a unique string in the HTML
curl -s https://example.com/ | grep -o '<html lang="[^"]*"'

# Verify cache partitioning
curl -sI https://example.com/ | grep -i "x-cache"
# Hit from cloudfront / Miss from cloudfront
```

When geo-testing, use a VPN or set `cloudfront-viewer-country` on staging only (production ignores viewer-supplied values — CloudFront overwrites them).

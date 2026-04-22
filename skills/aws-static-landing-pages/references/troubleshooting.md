# Troubleshooting — Common Failure Modes

Every issue below has been hit in production. Each entry: **symptom → root cause → fix**.

---

## 403 Forbidden from S3 after setting up OAC

**Symptom**: CloudFront returns 403 on every request, XML body reads `Access Denied` (or is blank if you configured a custom error page).

**Root cause**: the S3 bucket policy doesn't grant `cloudfront.amazonaws.com` access, OR the `AWS:SourceArn` condition doesn't match the distribution.

**Fix**:

```bash
# Verify the policy references the correct distribution ARN
aws s3api get-bucket-policy --bucket <BUCKET> --query Policy --output text | jq
```

Expected condition:

```json
"Condition": {
  "StringEquals": {
    "AWS:SourceArn": "arn:aws:cloudfront::<ACCOUNT>:distribution/<DIST_ID>"
  }
}
```

Rewrite the policy (see SKILL.md step 7) and retry. Also confirm the distribution's origin has `OriginAccessControlId` set to the OAC's ID, not empty.

**Common variant**: if the bucket has **KMS encryption**, you also need to grant the CloudFront service principal `kms:Decrypt` on the key.

---

## 403 with `MalformedInput` on objects that exist

**Symptom**: Some URIs (e.g. `/about`) return 403 but `/about/index.html` works.

**Root cause**: S3 REST endpoint (unlike the website endpoint) does NOT auto-append `index.html`. When the browser asks for `/about`, S3 looks for an object literally named `about` — it doesn't exist.

**Fix**: attach a CloudFront Function that appends `index.html` to directory-style URIs:

```javascript
function handler(event) {
  var req = event.request;
  var uri = req.uri;
  if (uri.endsWith('/')) req.uri = uri + 'index.html';
  else if (!uri.includes('.')) req.uri = uri + '/index.html';
  return req;
}
```

Attach to viewer-request on the default behavior.

---

## Stale HTML after a deploy

**Symptom**: users still see the old landing page hours after deploy.

**Root causes** (ranked by likelihood):

1. **Didn't invalidate HTML** — even with `s-maxage=60`, users with a warm browser cache may hold old HTML for hours.
2. **Cache-Control is too aggressive on HTML** — check the object's metadata in S3.
3. **HTTP caching in an intermediate proxy** — rare, but corporate networks sometimes do this.

**Fix**:

```bash
# Check the object metadata
aws s3api head-object --bucket <BUCKET> --key index.html

# Should show: CacheControl: "public, max-age=0, s-maxage=60, must-revalidate"
```

If Cache-Control is wrong, re-upload with the correct header (see SKILL.md step 3).

If Cache-Control is correct, invalidate:

```bash
aws cloudfront create-invalidation \
  --distribution-id <DIST_ID> \
  --paths "/" "/index.html" "/*.html"
```

---

## Cache hit ratio below 50%

**Symptom**: CloudWatch `CacheHitRate` sits under 50%, origin bill is higher than expected.

**Root causes**:

1. Cache key includes high-cardinality signals (cookies, user-agent, ad-tracking query strings).
2. HTML TTL is set to 0 without `s-maxage`.
3. Too many behaviors with uncoordinated cache keys.

**Diagnosis**:

```bash
# Pull CloudFront logs into Athena, then:
SELECT x_edge_result_type, COUNT(*) AS n
FROM cloudfront_logs
WHERE date >= current_date - interval '1' day
GROUP BY x_edge_result_type
ORDER BY n DESC;
```

`Miss`, `RefreshHit`, `Hit` are the three main categories. If `Miss` > 30%, your cache key is too granular.

**Fix**: audit each behavior's cache policy. Remove `User-Agent` from any cache key. Strip `utm_*`, `fbclid`, `gclid`, `ttclid` from the query-string cache key. If routing on cookies or country, emit a `X-Variant-Bucket` header from a CF Function and cache on that instead.

---

## Mixed-content warnings

**Symptom**: page loads but images or scripts fail with a browser console warning `Mixed Content: The page at https://... was loaded over HTTPS, but requested an insecure resource http://...`.

**Root cause**: the built HTML contains `http://` URLs — usually from an old CMS dump or hard-coded test URLs.

**Fix**:

```bash
grep -rn "http://" ./dist/ | grep -v "http://www.w3.org"
```

Replace every non-W3C `http://` with `https://` or with a protocol-relative `//` (though HTTPS-only is preferred).

---

## HTTP/3 not negotiated

**Symptom**: `curl --http3` fails or the browser doesn't show h3 in DevTools.

**Root causes**:

1. Distribution still on `http2` — flip to `http2and3`.
2. Client network blocks UDP 443 (corporate firewalls).
3. curl build lacks HTTP/3 support (most system-installed curl doesn't; use a build with quiche or ngtcp2).

**Fix**:

```bash
aws cloudfront get-distribution-config --id <DIST_ID> --query 'DistributionConfig.HttpVersion'
# Expected: "http2and3"

# If not:
# 1. Fetch the full config, edit HttpVersion to "http2and3", save with ETag
# 2. aws cloudfront update-distribution --id <DIST_ID> --if-match <ETAG> --distribution-config file://updated.json
```

Browser-side verification: Chrome DevTools → Network → select request → Protocol column shows `h3`.

---

## CloudFront Function exceeds CPU or memory

**Symptom**: on publish or at request time, function returns a 502 with `FunctionExecutionError`, or the test console shows compute utilization > 100.

**Root cause**: runtime 1.0 functions have strict limits. Complex regex, large lookup tables, or inefficient loops will blow the budget.

**Fix**:

1. **Upgrade to runtime 2.0** if you haven't — it's faster and has more headroom:
   ```bash
   aws cloudfront create-function --name <NAME> --function-config 'Comment="",Runtime=cloudfront-js-2.0' --function-code fileb://fn.js
   ```
2. **Move large lookup tables to CloudFront KV Store** (runtime 2.0 only). Up to 5MB per function.
3. **If you truly need more compute**, migrate the function to **Lambda@Edge** (viewer-request). Longer cold start, costs more, but full Node.js runtime.

---

## Function deploys but doesn't run

**Symptom**: you published the function but requests don't reflect the logic.

**Root cause**: you didn't associate the function with a cache behavior.

**Fix**: functions must be associated with a behavior via `FunctionAssociations`. Also ensure you **published** (functions live in draft/DEVELOPMENT stage until published):

```bash
ETAG=$(aws cloudfront describe-function --name <NAME> --query 'ETag' --output text)
aws cloudfront publish-function --name <NAME> --if-match "$ETAG"

# Then update the distribution config to associate it:
# DefaultCacheBehavior.FunctionAssociations:
#   Items: [{FunctionARN: "arn:...:function/<NAME>", EventType: "viewer-request"}]
```

---

## Geo headers missing in the function

**Symptom**: inside the CF Function, `req.headers['cloudfront-viewer-country']` is `undefined`.

**Root cause**: the **origin request policy** on the behavior isn't forwarding geo headers. (Confusingly, whitelisting in the **cache policy** puts them in the cache key but may not surface them to the function.)

**Fix**: use an origin request policy that forwards these headers, OR use the managed policy `AllViewerExceptHostHeader` (id `b689b0a8-53d0-40ab-baf2-68738e2966ac`) as a quick fix. For production, create a custom origin request policy that forwards only what you need:

```bash
aws cloudfront create-origin-request-policy --origin-request-policy-config '{
  "Name": "ForwardGeoAndDevice",
  "HeadersConfig": {
    "HeaderBehavior": "whitelist",
    "Headers": {
      "Quantity": 4,
      "Items": [
        "CloudFront-Viewer-Country",
        "CloudFront-Viewer-Country-Region",
        "CloudFront-Is-Mobile-Viewer",
        "CloudFront-Is-Tablet-Viewer"
      ]
    }
  },
  "QueryStringsConfig": { "QueryStringBehavior": "all" },
  "CookiesConfig": { "CookieBehavior": "all" }
}'
```

Attach this to every behavior that uses geo or device headers.

---

## Ad network flags the landing page

**Symptom**: Meta / TikTok / Google Ads disapproves the ad citing "landing page experience" or "malicious/spammy site".

**Common root causes**:

1. **No HSTS** — fixed via response-headers policy.
2. **TLS misconfiguration** — fixed by upgrading `MinimumProtocolVersion` to `TLSv1.2_2021`.
3. **Slow LCP** — see performance.md.
4. **Too many redirects** — especially visible with path-based variant routing done wrong (you redirected instead of URI-rewriting).
5. **Exposed malware-like patterns** — third-party scripts from shady CDNs; some aggressive analytics/heatmap vendors are on network deny-lists.

**Fix flow**:

1. Run SSL Labs scan → A or A+.
2. Run Lighthouse mobile → Performance ≥ 90.
3. Run Mozilla Observatory → A.
4. Remove any third-party script not strictly required.
5. Reapply to the ad network.

---

## Distribution update stuck "In Progress" for hours

**Symptom**: `aws cloudfront get-distribution --id <DIST_ID> --query 'Distribution.Status'` stays `InProgress` for 30+ minutes.

**Reality**: this is normal. A CloudFront distribution change takes 3-10 minutes typically, but can take up to 15-20 minutes if the change affects many edge pops.

**When to worry**: over 30 minutes is unusual. Open AWS support. In the meantime:

- `aws cloudfront get-distribution --id <DIST_ID>` — check `Status` and `LastModifiedTime`
- Confirm the config change is valid (run `get-distribution-config` and diff against what you submitted)

---

## Deploy uploaded to the wrong bucket

**Symptom**: you ran `aws s3 sync` against the wrong bucket, now the wrong HTML is live.

**Fix**:

1. S3 versioning is on (you followed the SKILL.md). Each object has a previous version.
2. Restore previous versions for affected keys:

```bash
# List versions
aws s3api list-object-versions --bucket <BUCKET> --prefix index.html

# Copy the previous version back on top
aws s3api copy-object \
  --bucket <BUCKET> \
  --copy-source "<BUCKET>/index.html?versionId=<PREVIOUS_VERSION_ID>" \
  --key index.html \
  --metadata-directive REPLACE \
  --cache-control "public, max-age=0, s-maxage=60, must-revalidate" \
  --content-type "text/html; charset=utf-8"

# Invalidate
aws cloudfront create-invalidation --distribution-id <DIST_ID> --paths "/*.html" "/"
```

**Prevention**: CI pipeline should take the bucket name as a variable and never hardcode. Require manual approval before `prod` deploys.

---

## Ads traffic causing 5xx spikes

**Symptom**: 5xx error rate climbs when ad campaign starts; nothing else changed.

**Root causes**:

1. **Burst traffic hitting cold edge pops** — origin shield not enabled or misconfigured.
2. **Cache hit ratio collapses under bot traffic** with randomized query strings.
3. **WAF rule rate-limiting legitimate users** — common if the rate rule is tuned too tight.

**Fix**:

1. Enable **Origin Shield** in the region nearest the bucket.
2. **Strip ad-tracking query strings** from the cache key (`fbclid`, `gclid`, `ttclid`, `utm_*`).
3. Temporarily loosen the **WAF rate-based rule** (e.g. 2000 → 5000 per 5 min per IP) while debugging, and review the blocked requests in WAF logs.
4. Check if a bot is hammering a specific path — block with a WAF custom rule.

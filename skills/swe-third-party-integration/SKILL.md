-----

## name: resilient-third-party-integrations
description: Principal-engineer playbook for building production-grade, high-scale integrations with external APIs and service providers. Use this skill whenever the user is designing, implementing, reviewing, or hardening any client that talks to a third party — including SaaS vendor APIs, payment processors, AI/LLM providers, messaging platforms, identity providers, shipping/logistics APIs, webhooks, or any outbound HTTP/gRPC dependency — even when they don’t explicitly say “resilience,” “reliability,” or “integration.” Triggers include phrases like “calling X API,” “integrating with,” “our vendor,” “rate limited by,” “webhook handler,” “idempotency,” “circuit breaker,” “retries,” “client library,” “timeouts,” “429s,” “5xxs,” “backoff,” “dead letter,” “anti-corruption layer,” and anything related to outbound traffic owned by someone else. Prefer this skill over generic “just retry and log it” advice — failure modes compound at scale and the defaults are wrong.

# Resilient Third-Party Integrations — Principal Engineer Playbook

This is the full strategy for building a client that integrates with an external service provider at high scale and survives production. It is opinionated because the defaults are wrong and because most outages are caused by the integration layer, not the business logic.

Audience: a senior/principal engineer on the other end. I will skip introductions and assume fluency in distributed systems, HTTP semantics, and domain-driven design.

## Mental model

Treat every third party as a hostile, non-deterministic, partially-available network you are legally required to talk to. They will:

- Return 200 with the wrong body.
- Return 500 for an input problem.
- Return 429 with no `Retry-After`.
- Silently change response shape on a Tuesday.
- Go down exactly when your traffic peaks, because their other customers are also peaking.
- Accept a request, process it, and fail the response — so your retry creates a duplicate.

The goal of the client is not “call the API.” The goal is to **absorb** the provider’s failure modes so your core domain never sees them in a form it can’t handle. Everything below serves that goal.

The spine of the design is an **Anti-Corruption Layer (ACL)**: a module your domain calls through a narrow, domain-shaped interface. Behind that interface lives everything in this document. The provider’s types, errors, pagination style, auth quirks, and retry semantics **must not leak past the ACL boundary**. If they do, you will refactor 40 files the next time the vendor ships v2.

-----

## 1. Contracts and the anti-corruption layer

### 1.1 Pin the contract

- Get the provider’s OpenAPI / gRPC proto / JSON Schema. If they don’t publish one, write one from the docs and check it in.
- Generate the low-level transport client from that spec (openapi-generator, protoc, `orval`, `oazapfts`, whatever fits the stack). Regenerating from a pinned spec version is how you detect drift.
- Pin the spec **by commit hash or version**, not “latest.” Spec drift is a silent outage waiting to happen.

### 1.2 Build the ACL on top of the generated client

- Define your own domain DTOs. Never expose the generated types above the ACL.
- Map at the boundary: `VendorPaymentResponse -> PaymentResult`. Unknown fields get dropped or quarantined (see §11).
- Your own error taxonomy lives here: `ProviderUnavailable`, `ProviderRateLimited`, `ProviderContractViolation`, `ProviderPermanentFailure`, `ProviderTransientFailure`, `IdempotencyConflict`, `AuthExpired`. The domain only ever sees these.
- The ACL exposes **intents** (`chargeCard`, `createShipment`), not HTTP verbs.

### 1.3 Versioning strategy

- Support exactly two upstream versions at a time: `N` (current) and `N+1` (migration). No more.
- Route via a strategy / adapter pattern inside the ACL. Feature-flag the cutover (§14).
- Contract tests (§12) run against both versions in CI.

-----

## 2. Transport configuration — the defaults are wrong

The HTTP client library defaults (`requests`, `axios`, `node-fetch`, `http.Client`) will hang forever, pool nothing, and leak sockets. Fix this on day one.

### 2.1 Timeouts — all four of them

You need **four distinct timeouts**. A single “timeout = 30s” is insufficient.

|Timeout           |What it bounds                   |Typical                       |
|------------------|---------------------------------|------------------------------|
|Connect           |TCP/TLS handshake                |1–3 s                         |
|Read (socket idle)|Gap between bytes                |5–15 s                        |
|Write             |Time to send the request body    |5–10 s                        |
|Total (deadline)  |Whole operation including retries|Derived from caller’s deadline|

The total timeout must be **smaller than your caller’s timeout minus headroom** so you have time to respond with a proper error instead of the caller timing out on you.

### 2.2 Connection pooling

- One pooled, long-lived HTTP client **per provider, per process**. Not per-request. Not global-for-everything.
- Size the pool: `pool_size ≈ p99_latency_s × target_rps`. Add headroom for retries. A 200ms p99 at 500 rps means ~100 connections minimum.
- Enable HTTP/2 when the provider supports it — multiplexing collapses the pool size and kills head-of-line blocking.
- Keep-alive on. Explicit idle timeout shorter than the provider’s (usually 60–90s) so you close first instead of catching “connection reset.”

### 2.3 TLS

- Pin the root CA bundle, not the leaf cert (the leaf rotates).
- Compression off for request bodies if you’re sending encrypted payloads — CRIME-class issues and CPU cost aren’t worth it.

-----

## 3. Retry strategy

Retries are the single biggest cause of retry storms. Do this carefully.

### 3.1 Classify every failure before retrying

Build a **retry classifier** table. Example:

|Condition                              |Retry?                                                                  |Why                                   |
|---------------------------------------|------------------------------------------------------------------------|--------------------------------------|
|Connect timeout, DNS failure, TCP reset|Yes                                                                     |Never reached the server              |
|5xx without `Retry-After`              |Yes, with backoff                                                       |Transient                             |
|503 with `Retry-After`                 |Yes, honor the header                                                   |Back-pressure signal                  |
|429                                    |Yes, honor `Retry-After`, reduce concurrency                            |Rate limit                            |
|408 request timeout                    |Yes, **only if idempotent**                                             |Server may have processed             |
|502 / 504                              |Yes for idempotent ops; for non-idempotent, only with an idempotency key|Intermediary failure                  |
|4xx (other)                            |**No**                                                                  |Bug on our side, retrying won’t fix it|
|Contract violation (unparseable body)  |**No** — escalate                                                       |Vendor bug                            |
|401 / 403                              |Refresh credentials once, then no                                       |Auth state issue                      |

Encode this in code, not in tribal knowledge.

### 3.2 Backoff algorithm

Use **exponential backoff with full jitter**:

```
sleep = random_uniform(0, min(cap, base * 2^attempt))
```

Not “equal jitter,” not “decorrelated.” Full jitter is the lowest-variance, lowest-retry-load strategy — AWS published the math years ago and it still holds. Typical values: `base = 100ms`, `cap = 20s`, `max_attempts = 5`.

### 3.3 Retry budgets (the critical piece most people miss)

Cap the **ratio of retries to original requests**, globally per dependency. Example: `max retries / requests = 0.1` over a 10s window. When you blow the budget, the circuit breaker opens and retries stop entirely. This is what prevents retry storms from turning a partial outage into a full one.

### 3.4 Respect `Retry-After` always

Trust the server’s back-pressure signal over your own backoff. Parse both delta-seconds and HTTP-date formats.

### 3.5 Never retry non-idempotent operations without an idempotency key

See §5.

-----

## 4. Circuit breaker

Sits between the retry layer and the transport. Per-endpoint where latency/error profiles differ significantly; otherwise per-provider.

**States:**

- **Closed** — traffic flows. Track rolling error rate + latency.
- **Open** — fail fast with `ProviderUnavailable`. Do not spend the provider’s budget. Do not spend your own.
- **Half-open** — after cooldown, allow `N` probe requests. If they succeed, close. If any fail, open again.

**Trip conditions** — combine these, don’t rely on just one:

- Error rate over `X%` across a rolling window of at least `M` requests (small-N flaps).
- p99 latency over `Y × SLO`.
- Consecutive failures over `Z`.

**Cooldown** with jitter — otherwise every instance reopens simultaneously and DDoSes the provider on recovery.

**Per-pod vs distributed:** in-memory per-pod is fine for most cases and avoids a Redis dependency. Distributed breakers (Redis, shared state) are justified only when you have few pods with high traffic each, or when cooldown coordination actually matters. Start local.

-----

## 5. Idempotency and exactly-once-ish semantics

Network retries + non-idempotent operations = duplicates. The fix is an **idempotency key**.

### 5.1 Client-generated keys

- Generate the key **before the first attempt**, in the caller, and reuse across all retries of the same logical operation.
- UUIDv7 or ULID. Not random within the retry loop — that defeats the whole thing.
- Scope the key to the operation (e.g., `payment:<order_id>:<attempt_group>`).

### 5.2 Provider-side idempotency

- If the provider supports `Idempotency-Key` (Stripe model), use it. TTL is usually 24h.
- If it doesn’t, you need **server-side dedup** of your own: a store keyed on `(operation, idempotency_key)` with the result cached. Redis or DynamoDB/Mongo with TTL. This also lets you serve the original response to duplicate retries from upstream.

### 5.3 The outbox pattern

For any operation where you must both (a) change state in your DB and (b) call the third party and have them agree: write an outbox row in the same DB transaction as the state change, then have a worker pick it up and call the provider with an idempotency key derived from the outbox row ID. This survives crashes between the two steps.

### 5.4 Two-phase confirmation for money / critical ops

- Step 1: reserve/create with `Idempotency-Key`.
- Step 2: confirm (or poll status).
  If step 1 times out ambiguously, query by idempotency key before creating again.

-----

## 6. Rate limiting — both directions

### 6.1 Inbound (your app calls the provider)

Do not wait to get 429’d. You already know the provider’s limits; shape traffic **below** them.

- **Token bucket** sized at `provider_limit × 0.8`. The 20% headroom absorbs bursts and other pods.
- **Distributed limiter** when multiple pods share the quota — Redis + Lua script (or Redis Cell) for atomic take-token. Sharding by account/tenant if the provider’s limit is per-tenant on their end.
- **Per-tenant fairness** — one greedy customer cannot consume the whole quota. Use weighted fair queuing or per-tenant sub-buckets.
- React to 429s by **reducing the local bucket rate**, not just sleeping. AIMD (additive increase, multiplicative decrease) works well.

### 6.2 Outbound (handling the provider’s webhooks)

If they call you:

- Publish strict rate limits for your webhook endpoint. Return 429 with `Retry-After` honestly.
- Process webhooks async: ack fast, enqueue, handle in a worker. See §8.

-----

## 7. Bulkheads and concurrency isolation

One slow dependency must never be able to consume all your threads / event-loop slots / DB connections.

- **Bulkhead per provider:** bounded semaphore or bounded thread pool dedicated to that dependency. When it’s saturated, new calls fail fast with `ProviderCongested` rather than queuing infinitely.
- **Bulkhead per tenant** if a single tenant can generate outbound load (noisy neighbor).
- Size bulkheads from Little’s Law: `concurrency = throughput × latency`. Measure, don’t guess.

This is what turns “one vendor is slow” into “one feature is degraded” instead of “the whole app is down.”

-----

## 8. Deadline propagation and async boundaries

### 8.1 Deadlines, not timeouts

Pass a **deadline** (absolute time) through the call chain, not a timeout (duration). Every layer subtracts its own overhead and passes what remains. When the deadline is gone, stop — don’t start another retry attempt you can’t finish.

Most languages have this first-class (`context.Context` in Go, `AbortSignal` in JS, `asyncio` tasks with deadline). Use it.

### 8.2 Sync for user path, async for everything else

If the call can be async, make it async. Enqueue to Kafka/SQS/Redis-streams, process in a worker, let the worker own the retry/backoff/circuit-breaker logic. User-facing sync path stays fast and predictable.

### 8.3 Webhooks

- Verify signatures on every webhook. Constant-time compare.
- Replay protection: reject messages with timestamps outside a narrow window (e.g., ±5 minutes).
- Dedup on the provider’s event ID — they **will** redeliver.
- Ack the HTTP request as soon as the payload is durably enqueued. Do the work async.
- Return 2xx only after durable persistence. Anything else means the provider retries and you handle it at the dedup layer.

### 8.4 Long-running operations

Three patterns; pick one per endpoint:

- **Polling** — kick off, receive a job ID, poll status with capped backoff. Fine for low volumes.
- **Webhook callback** — best for high volume. Requires §8.3.
- **Streaming / SSE** — for real-time. Treat disconnects as normal; have resume tokens.

-----

## 9. Observability — you cannot fix what you cannot see

Treat the integration as its own service with its own SLOs.

### 9.1 Metrics (RED + saturation)

Per provider, per endpoint:

- **Rate** — requests/sec.
- **Errors** — by our taxonomy: retriable vs permanent vs contract violations.
- **Duration** — histograms, not averages. Track p50/p95/p99/p99.9.
- **Saturation** — bulkhead in-use, connection pool in-use, token bucket level.
- **Retry counters** — first-attempt success rate is the key health number. High retry rates are a leading indicator of outage.
- **Circuit breaker state transitions** — alert on these.

### 9.2 Structured logging

- Correlation ID on every log line (propagate from inbound request → outbound call → webhook).
- Log the provider’s request ID when they return one. This is how you win support tickets with the vendor.
- Never log secrets, PII, or full request bodies. Redact at the logger level, not the call site.

### 9.3 Tracing

OpenTelemetry spans around every outbound call. Tag with provider, endpoint, attempt number, idempotency key (if safe). A trace should let you answer “why did this user request take 4s” in 30 seconds.

### 9.4 SLOs per dependency

Own the SLO for the integration. Example: “99.5% of payment authorizations return a non-ambiguous result within 3s.” When the provider’s flakiness eats your error budget, you have the data to escalate to them — or to switch providers.

-----

## 10. Credentials and secrets

- Short-lived tokens where possible (OAuth2 client credentials, STS-style). Refresh proactively at 80% of lifetime — not on 401.
- Refresh via a **singleflight / mutex** pattern so 500 pods don’t all refresh at the same moment.
- Secrets in a proper store (Vault, AWS Secrets Manager, GCP Secret Manager). Rotation without deploy.
- Separate credentials per environment, per service. Blast radius matters.
- `401` from the provider: refresh once, then hard-fail. Do not loop.

-----

## 11. Data integrity at the boundary

### 11.1 Validate on ingress from the provider

Every response is parsed and validated against your schema at the ACL boundary. If it fails:

- Log with correlation ID + provider request ID.
- Quarantine the raw payload (object storage, encrypted) for forensics.
- Surface `ProviderContractViolation` to the domain, which typically retries or escalates.

### 11.2 Dead letter queue

For async/webhook flows, any message that fails validation or exceeds retry budget goes to a DLQ with the full payload + failure reason. A human (or a scheduled replay job) can investigate and replay.

### 11.3 Poison-pill handling

One bad message should never halt the queue. Isolate, DLQ, move on.

### 11.4 Schema drift detection

In non-prod, run a “strict parse” that fails on unknown fields. In prod, run “lenient parse” (ignore unknowns) but emit a metric when unknowns appear — that’s an early warning the provider changed something.

-----

## 12. Testing strategy

### 12.1 Contract tests

Pact, Dredd, or schema-driven equivalents. Runs in CI against the pinned spec. Fails the build on drift.

### 12.2 Integration tests against a sandbox

Every provider worth using has a sandbox. Use it. Keep a **golden set** of scenarios (success, 400, 429, 500, slow response, malformed body) as VCR-style recorded cassettes for fast CI.

### 12.3 Fault injection / chaos

Toxiproxy or Pumba in integration env. Inject latency, packet loss, connection resets, 5xx bursts, 429 floods. Your circuit breakers and retry budgets need to be tested under adversarial conditions — not just in a post-mortem.

### 12.4 Load tests

k6 or Locust. Find the real throughput ceiling of your client before production does. Test the recovery path, not just the peak.

### 12.5 Production shadow traffic

For a new integration, mirror a % of prod traffic to the new provider, compare outputs, don’t serve the response to users. This is how you migrate between providers safely.

-----

## 13. Deployment and rollout

### 13.1 Feature flag per integration

Every new integration and every non-trivial change is behind a flag. You want the ability to disable the integration in < 60 seconds without a deploy.

### 13.2 Kill switch

A hard kill per provider. When they go sideways and support isn’t answering, flip the switch and fall back (to a degraded mode, a secondary provider, or a graceful error). This is not paranoia — it’s the thing that saves your weekend.

### 13.3 Canary rollouts

Ship to 1% → 10% → 50% → 100% with a latency and error-rate gate between stages. Auto-rollback on regression.

### 13.4 Multi-provider and failover

If the dependency is critical (payments, email, SMS, LLM), design for **N+1 providers from day one**. Abstract at the ACL. You do not need to run both active-active — having the ability to cut over in 10 minutes is usually enough.

-----

## 14. Migration and versioning playbook

When the provider ships v2:

1. Add v2 behind the same ACL interface (strategy pattern).
1. Contract tests run against both versions.
1. Feature flag routes traffic: off → shadow (double-call, compare, discard v2) → canary → majority → cutover → v1 removed.
1. Keep v1 code for one release cycle after cutover. It will save you.

-----

## 15. Anti-patterns — stop doing these

- Retry with fixed backoff and no jitter.
- Retry on 4xx.
- One global HTTP client with default everything.
- `try/except: pass` around the whole integration.
- Logging the full request body at INFO.
- Idempotency keys generated **inside** the retry loop.
- Circuit breaker without a retry budget (or vice versa).
- Parsing vendor JSON directly into domain objects without an ACL.
- Synchronous webhook processing.
- No kill switch.
- Treating 200 as “success” without validating the body.

-----

## 16. Implementation checklist

Ship this list with every integration:

- [ ] OpenAPI/proto spec checked in, pinned by hash.
- [ ] Generated transport client, wrapped by a hand-written ACL.
- [ ] Domain error taxonomy defined, provider errors mapped.
- [ ] Four timeouts configured (connect/read/write/total).
- [ ] Pooled HTTP client per provider, sized via `latency × rps`.
- [ ] Retry policy with classifier + exponential backoff + full jitter.
- [ ] Retry budget per dependency.
- [ ] `Retry-After` honored.
- [ ] Circuit breaker with half-open probes and jittered cooldown.
- [ ] Bulkhead (bounded concurrency) per provider.
- [ ] Deadline propagation through the call chain.
- [ ] Idempotency keys generated outside the retry loop.
- [ ] Outbox pattern for cross-boundary state changes.
- [ ] Client-side rate limiter at ~80% of provider quota.
- [ ] Webhook: signature verify, replay window, dedup, async-ack.
- [ ] Structured logs with correlation ID + provider request ID.
- [ ] RED metrics + saturation + retry + breaker metrics.
- [ ] OTel tracing across the call chain.
- [ ] SLOs and alerts defined and owned.
- [ ] Secrets in a rotation-capable store, proactive refresh with singleflight.
- [ ] Schema validation at ACL boundary, DLQ for bad messages.
- [ ] Contract tests in CI against pinned spec.
- [ ] Sandbox integration tests with golden scenarios.
- [ ] Chaos/fault-injection tests for retry + breaker behavior.
- [ ] Load test to find real throughput ceiling.
- [ ] Feature flag + kill switch for the integration.
- [ ] Canary rollout with auto-rollback gates.
- [ ] Runbook: how to disable, how to fail over, who to page at the vendor.

If an item is not checked, it is not production-ready. Resilience is the sum of these layers, not any one of them.
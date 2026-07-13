# Design Review Challenge Questions — Diso DESIGN.md Reviews

**Confidence:** [Likely] throughout — distilled review heuristics, not verified facts about your system.

**Usage rule:** Every question demands an **artifact or a number**, never prose. Any answer that restates the methodology is a non-answer. Pick 8–12 per review; sections 1, 3, 4 are highest yield.

-----

## 1. Evidence over assertion (anti-checkbox)

- Which gate came *closest to failing*, and what changed as a result? A design where every gate passed first try means the gates weren’t exercised.
- Show the query → index mapping table. Which query lacks a covering index, and why is that acceptable?
- For each field in CONTRACTS.md external calls: cite the spec link + section. Which fields were *inferred* rather than verified?
- Which `ASSUMED` entry in the Open Questions log would Product most likely dispute? Why wasn’t it escalated?

## 2. Numbers or it didn’t happen

- Write QPS per collection at 1x / 10x — show the arithmetic, not the adjective.
- P99 document size, and the largest *realistic* document. What breaks first at 100x: index RAM, connection pool, queue depth, or a hot shard key?
- Measured (not assumed) p99 latency of each sync dependency. Where did the 200 ms sync/async threshold come from for *this* call?
- Eventual consistency window, in seconds. What does the user actually see during it?

## 3. State & concurrency attacks

- Name the one field two services are most tempted to write. How is single-ownership enforced *mechanically*, not just documented?
- Where is the lost-update window when an optimistic-version retry interleaves with a background job on the same document?
- Idempotency store TTL vs. the client’s maximum retry horizon — what happens on a retry after expiry?
- Which invariant spans two aggregates? If “none,” why do the aggregates communicate at all?
- Two users double-click simultaneously across a shard/replica boundary — trace the exact write path.

## 4. Failure-mode adversarial

- Walk the compensation chain when *the compensation itself* fails at step 2. Who resumes it after a process restart, from what durable state?
- Which downstream, dead for 10 minutes, causes **silent data loss** rather than visible errors?
- What’s in the DLQ after one week? Who owns draining it, and what’s the documented replay procedure?
- Circuit breaker opens mid multi-step operation: abandoned, compensated, or resumed? Show the state machine.
- Which “single-step” operation is secretly multi-step because of side effects (cache invalidation, search index, notification)?

## 5. Evolution & migration

- Rollback plan if the schema is wrong after 30 days of production writes — not “we’ll migrate,” the actual reverse migration.
- During rollout, old and new versions run simultaneously: which write shape breaks the old reader?
- Event payload v2 ships: do v1 consumers ignore, crash, or *misinterpret*? Misinterpret is the one that hurts.
- In-flight events during a consumer deploy — dropped, duplicated, or reordered?

## 6. Security beyond authz

- Which endpoint is IDOR-exploitable if the service-layer check is skipped? Prove the check exists at the service layer, not only middleware.
- Where does user-controlled input reach a query, URL, or template? (Injection / SSRF surface.)
- Which event payload leaks data to a *future* consumer you can’t predict today?
- What gets logged that an auditor or regulator would object to — PII, tokens, account balances?
- Can permissions change mid-operation, and does step 4 re-check what step 1 authorized?

## 7. Simplicity / YAGNI attacks

- Which component can be deleted with the least damage? “None” means you haven’t looked hard enough.
- Which abstraction exists for a 10x future with no committed date?
- Could this be one service instead of two? What *concrete* evidence justifies the split — deploy cadence, team boundary, scaling asymmetry?
- Explain each component’s job in one sentence. Which one needed two?

## 8. Operations at 3 AM

- What alert fires *first* when this degrades, and what does the runbook say to do?
- Which metric distinguishes “downstream is slow” from “we are slow”?
- Blast radius of a bad deploy: feature-flagged, canaried, or all-at-once? Where’s the kill switch?
- Monthly infra cost delta at 1x and 10x. Which line item grows superlinearly?

## 9. Meta-questions for an agent-authored design

- Which section was copied from the methodology template rather than derived from this feature’s requirements? (There always is one.)
- Which requirement is least testable as written? Rewrite it as given/when/then on the spot.
- If a second agent implemented from CONTRACTS.md alone, zero context, where would it diverge from your intent?
- Which external API field name are you least certain exists? Verify it now.
- Name the single decision you’d bet is wrong. **“None” is a disqualifying answer.**

-----

## Escalation triggers

Reject the design (back to the relevant phase) if any of these appear:

- Capacity claims with adjectives but no arithmetic → Phase 1/3
- CONTRACTS.md fields without spec citations → Phase 4
- Compensation chains that are not idempotent or not restart-safe → Phase 6
- All gates passed on first attempt with no recorded friction → full re-review
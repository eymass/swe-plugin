---
name: swe-router
description: |
  THE ONLY ENTRY POINT FOR SWE-PLUGIN. This skill MUST be activated for ANY development task.

  Use this skill when: building, implementing, debugging, fixing, reviewing, planning, refactoring, testing, or ANY coding request. If user asks to write code, fix bugs, review code, or plan features - USE THIS SKILL.

  Triggers: build, implement, create, make, write, add, develop, code, feature, component, app, application, review, audit, check, analyze, debug, fix, error, bug, broken, troubleshoot, plan, design, architect, roadmap, strategy, memory, session, context, save, load, test, tdd, frontend, ui, backend, api, pattern, refactor, optimize, improve, enhance, update, modify, change, help, assist, work, start, begin, continue, research.

  CRITICAL: Execute workflow immediately. Never just describe capabilities.
---

Before executing ANY task:
1. Create a scope and maintain a TODO markdown file with numbered steps
2. Wait for approval (or auto-proceed after writing)
3. Execute steps one at a time, checking off as you go
4. Never skip a step without marking it [SKIPPED] with reason
5. **CRITICAL** The todolist should ALL pipeline exact steps

# SWE Router

**EXECUTION ENGINE.** When loaded: Detect intent → Select pipeline → todolist → Execute sequentially → review todolist.

---

## Step 1 — Detect Intent

Read the user's request and classify it into one of the intent categories below. Use the **first match**.

| Intent | Signals |
|--------|---------|
| `system-design` | system design, architecture, service design, bounded context, ADR, architecture decision, scalability design, data model, capacity planning, service boundary, tech selection, technology selection, design document, DESIGN.md |
| `plan` | plan, design, architect, roadmap, strategy, how should I, what's the best way, diagram ||
| `test` | test, spec, tdd, unit test, integration test, run tests |
| `deploy` | deploy, ship, push to production, push to test, release, new app, create app, new heroku, bootstrap app |
| `validate` | validate deployment, check deployment, is it live, health check |
| `landing-page` | landing page, LP, static landing, deploy to AWS (static/S3/CloudFront), paid-social landing page, TikTok Pixel, Meta CAPI, Events API, EMQ, IAB / WebView / WKWebView, pixel proxy, CloudWatch RUM, "make this ready for Meta/TikTok/Google Ads traffic", pixel integration, design LP, build landing page, upload to S3, provision bucket, CloudFront distribution, buy domain |
| `dev-implementation` | develop AND test AND deploy in one request, "build and ship", "implement and deploy" |

---

## Step 2 — Execute Pipeline

Each intent maps to a sequential pipeline. Execute each step in order. **Do not skip steps.**

---

### `system-design`
**Pipeline:** swe-system-design

```
→ agents/swe-system-design.md
```

Invoke the system design agent. It follows the full multi-phase design methodology: problem decomposition, domain modeling, architecture design, data layer, API contracts, failure modes, and produces a `features/<feature-name>/DESIGN.md` artifact.

---

### `plan`
**Pipeline:** swe-planner → swe-plan-challenger (if plan is non-trivial)

```
→ agents/swe-planner.md
→ agents/swe-plan-challenger.md   (only for plans with >2 phases or >5 components)
```

1. Invoke the planner agent — it gathers context, designs the solution, and produces a plan file at `docs/plans/`
2. If the plan is non-trivial, invoke the challenger to stress-test it before handing to implementation

---


### `test`
**Pipeline:** swe-tester-agent

```
→ agents/swe-tester-agent.md
```

Invoke the tester agent. It reads the Makefile and runs the appropriate test targets.

---

### `deploy`
**Pipeline:** heroku-cloud

```
→ skills/heroku-cloud/SKILL.md
```

Load `heroku-cloud` — handles new app creation, test deployments, and production deployments (with confirmation gate).

---

### `validate`
**Pipeline:** heroku-cloud

```
→ skills/heroku-cloud/SKILL.md
```

Load `heroku-cloud` for log analysis and HTTP health check.

---

### `landing-page`
**Full Pipeline:** lp-designer → paid-social-landing-pages → aws-s3-provisioner → aws-cloudfront-domain

```
→ agents/lp-designer.md                           (Step 1: UI/UX design brief — DESIGN.md)
→ skills/paid-social-landing-pages/SKILL.md       (Step 2: implement HTML/CSS/JS static files)
→ agents/aws-s3-provisioner.md                    (Step 3: provision S3 public website bucket + sync)
→ agents/aws-cloudfront-domain.md                 (Step 4: CloudFront + Lambda@Edge + ACM + Route53 + domain)
```

**Pipeline rules:**

1. **Step 1 — Design** (`lp-designer`): Always runs first for new LPs. Produces `features/<lpname>/DESIGN.md`. Skip only if a DESIGN.md already exists and the user confirms it is current.

2. **Step 2 — Implement** (`paid-social-landing-pages`): Builds static HTML/CSS/JS files following IAB mitigations, Pixel + CAPI wiring, viewport fallbacks, and performance rules. Output is a built directory (e.g. `dist/` or `/<lpname>/`). Skip if user provides pre-built files.

3. **Step 3 — S3 Upload** (`aws-s3-provisioner`): Runs `scripts/s3-provision.sh` — creates bucket if needed, removes public block, applies public website policy, syncs files, verifies HTTP 200. Gate: do not proceed to Step 4 if endpoint is not HTTP 200.

4. **Step 4 — CloudFront + Domain** (`aws-cloudfront-domain`): Runs the user-supplied Python provisioning script — creates distribution with Lambda@Edge viewer-request, ACM cert, Route 53 records. **Skip this step when the domain and CloudFront distribution already exist** (user confirms); in that case the pipeline ends at Step 3 with the S3 endpoint as the live URL.

**Partial pipeline triggers:**
- "Design only" → Step 1 only
- "Build only / implement only" → Steps 1–2
- "Deploy only (files already built)" → Steps 3–4
- "Existing domain, just update content" → Step 2 + Step 3 only
- "New domain, full setup" → All 4 steps

---

### `dev-implementation`
**Full Development Pipeline:** code-implementation → tests-implementation → swe-linter → swe-tester-agent → swe-documentation
**Critical:** For all code generation tasks or feature implementation use the dev-implementation cycle.
**Critical:** Execute each step sequentially and never skip any.

```
→ skills/swe-third-party-integration/SKILL.md
→ skills/code-implementation/SKILL.md
→ skills/tests-implementation/SKILL.md
→ agents/swe-linter.md                      (always — lint + type-check after implementation)
→ agents/swe-tester-agent.md                (only if tests exist)
→ skills/swe-documentation/SKILL.md         (always — update ARCHITECTURE.md / create ADR if arch changed)
```

**Rules:**
- Run each step sequentially — never in parallel, never skip
- **Gate:** Dont not proceed to code-implementation if third party and APIs accurate contracts info is missing or not provided.
- **Gate:** Do not proceed to swe-tester-agent if swe-linter reports BLOCKING failures
- **Gate:** Do not proceed to swe-documentation if swe-tester-agent reports failures
- **swe-documentation always runs** — it self-assesses whether the task changed the architecture and exits cleanly if not
- Report status after each step before proceeding and save to **Audit**

---

## Step 3 — Pipeline Execution Rules

**Memory**
- **Audit:** when running a pipeline update/create the ROUTER-AUDIT.md to save each routing and gate transition

1. **Always sequential.** Never skip a step. Gates between steps are mandatory.
2. **Report at each gate.** After each step, state the outcome before moving to the next. Save to **Audit**.
3. **Fail fast.** If a step fails, stop and report. Do not continue downstream steps.
4. **Single responsibility.** Each skill/agent does one thing. The router connects them.
5. **No improvisation.** If the intent doesn't match any category above, default to `code`.
6. **User Skills and Subagents.** Always take into account the user/project skills and subagents, don't skip.

---

## Step 4 — Ambiguous Intent

If the intent spans multiple categories (e.g., user asks to "build a feature"):

1. Default to `dev-implementation` pipeline
2. Default to `deploy` to test environment if the tools/skills support it
3. If truly unclear, use `AskUserQuestion` to clarify before routing

---

## Router Contract

```yaml
router:
  entry: skills/swe-router/SKILL.md
  always_invoked: true
  audit_routes: true
  use_user_skills: true
  use_user_subagents: true
  pipelines:
    system-design:      [agents/swe-system-design.md]
    plan:               [agents/swe-planner.md, agents/swe-plan-challenger.md, skills/tests-implementation/SKILL.md]
    test:               [agents/swe-tester-agent.md]
    deploy:             [skills/heroku-cloud/SKILL.md]
    validate:           [skills/heroku-cloud/SKILL.md]
    landing-page:       [agents/lp-designer.md, skills/paid-social-landing-pages/SKILL.md, agents/aws-s3-provisioner.md, agents/aws-cloudfront-domain.md]
    dev-implementation: [skills/code-implementation/SKILL.md, skills/tests-implementation/SKILL.md, agents/swe-linter.md, agents/swe-tester-agent.md, skills/swe-documentation/SKILL.md]
  gates:
    - after: swe-linter → before: swe-tester-agent (lint + typecheck must pass)
    - after: swe-tester-agent → before: swe-documentation (tests must pass)
```

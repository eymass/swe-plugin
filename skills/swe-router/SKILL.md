---
name: swe-router
description: |
  THE ONLY ENTRY POINT FOR SWE-PLUGIN. This skill MUST be activated for ANY development task.

  Use this skill when: building, implementing, debugging, fixing, reviewing, planning, refactoring, testing, or ANY coding request. If user asks to write code, fix bugs, review code, or plan features - USE THIS SKILL.

  Triggers: build, implement, create, make, write, add, develop, code, feature, component, app, application, review, audit, check, analyze, debug, fix, error, bug, broken, troubleshoot, plan, design, architect, roadmap, strategy, memory, session, context, save, load, test, tdd, frontend, ui, backend, api, pattern, refactor, optimize, improve, enhance, update, modify, change, help, assist, work, start, begin, continue, research.

  CRITICAL: Execute workflow immediately. Never just describe capabilities.
---

# SWE Router

**EXECUTION ENGINE.** When loaded: Detect intent → Select pipeline → Execute sequentially.

---

## Step 1 — Detect Intent

Read the user's request and classify it into one of the intent categories below. Use the **first match**.

| Intent | Signals |
|--------|---------|
| `plan` | plan, design, architect, roadmap, strategy, how should I, what's the best way, diagram |
| `frontend-ui` | ui, design, visual, layout, component, page, dashboard, css, html, artifact, mockup |
| `frontend-dev` | react, state, hook, form, accessibility, animation, frontend, responsive |
| `code` | implement, build, write, add, create, function, endpoint, API, backend, fix, bug, debug, refactor, modify |
| `test` | test, spec, tdd, unit test, integration test, run tests |
| `deploy` | deploy, ship, push to production, push to test, release |
| `deploy-new` | new app, create app, new heroku, bootstrap app |
| `validate` | validate deployment, check deployment, is it live, health check |
| `full-dev` | develop AND test AND deploy in one request, "build and ship", "implement and deploy" |

---

## Step 2 — Execute Pipeline

Each intent maps to a sequential pipeline. Execute each step in order. **Do not skip steps.**

---

### `plan`
**Pipeline:** planner-agent

```
→ agents/planner-agent.md
```

Invoke the planner agent. It will gather context, design the solution, and produce a plan file at `docs/plans/`.

---

### `frontend-ui`
**Pipeline:** frontend-ui-design → code-generation

```
→ skills/frontend-ui-design/SKILL.md
→ skills/code-generation/SKILL.md
```

1. Load `frontend-ui-design` to establish design direction and produce the UI
2. Load `code-generation` to implement the component code with correct patterns

---

### `frontend-dev`
**Pipeline:** frontend-development → code-generation

```
→ skills/frontend-development/SKILL.md
→ skills/code-generation/SKILL.md
```

1. Load `frontend-development` for component architecture, state, accessibility
2. Load `code-generation` to implement following project patterns

---

### `code`
**Pipeline:** code-generation

```
→ skills/code-generation/SKILL.md
```

Load `code-generation`. Answer Universal Questions first, then implement.

---

### `test`
**Pipeline:** tester-agent

```
→ agents/tester-agent.md
```

Invoke the tester agent. It reads the Makefile and runs the appropriate test targets.

---

### `deploy`
**Pipeline:** deploy skill → deploy-validate skill

```
→ skills/deploy/SKILL.md
→ skills/deploy-validate/SKILL.md
```

1. Load `deploy` — confirm environment, run `make deploy` or `make deploy-test`
2. Load `deploy-validate` — check logs and HTTP status to confirm success

---

### `deploy-new`
**Pipeline:** deploy-new-app skill → deploy-validate skill

```
→ skills/deploy-new-app/SKILL.md
→ skills/deploy-validate/SKILL.md
```

1. Load `deploy-new-app` — create app, set env vars, push
2. Load `deploy-validate` — verify the new app is healthy

---

### `validate`
**Pipeline:** deploy-validate skill

```
→ skills/deploy-validate/SKILL.md
```

Load `deploy-validate` directly.

---

### `full-dev`
**Full Development Pipeline:** code-generation → tester-agent → deploy → deploy-validate
**Critical:**  for all code generation tasks or feature implementation use the full-dev cycle

```
→ skills/code-generation/SKILL.md
→ agents/tester-agent.md          (only if tests exist / Makefile has test target)
→ skills/deploy/SKILL.md          (deploy to test env, only after tests pass / Makefile has deploy targets)
→ skills/deploy-validate/SKILL.md
```

**Memory**
- **Audit:** create ROUTER-AUDIT.md to save each routing and gate transition

**Rules:**
- Run each step sequentially — never in parallel
- **Gate:** Do not proceed to `deploy` if tester-agent reports failures
- **Gate:** Do not proceed to `deploy-validate` if deploy fails
- Report status after each step before proceeding and save to **Audit:**

---

## Step 3 — Pipeline Execution Rules

1. **Always sequential.** Never skip a step. Gates between steps are mandatory.
2. **Report at each gate.** After each step, state the outcome before moving to the next. and save to **Audit:**
3. **Fail fast.** If a step fails, stop and report. Do not continue downstream steps.
4. **Single responsibility.** Each skill/agent does one thing. The router connects them.
5. **No improvisation.** If the intent doesn't match any category above, default to `code`.

---

## Step 4 — Ambiguous Intent

If the intent spans multiple categories (e.g., user asks to "build a feature"):

1. Default to `full-dev` pipeline
2. Default to `deploy` to test environment if the tools/skills supports it
3. If truly unclear, use `AskUserQuestion` to clarify before routing

---

## Router Contract

```yaml
router:
  entry: skills/swe-router/SKILL.md
  always_invoked: true
  pipelines:
    plan:          [agents/planner-agent.md]
    frontend-ui:   [skills/frontend-ui-design/SKILL.md, skills/code-generation/SKILL.md]
    frontend-dev:  [skills/frontend-development/SKILL.md, skills/code-generation/SKILL.md]
    test:          [agents/tester-agent.md]
    deploy:        [skills/deploy/SKILL.md, skills/deploy-validate/SKILL.md]
    deploy-new:    [skills/deploy-new-app/SKILL.md, skills/deploy-validate/SKILL.md]
    validate:      [skills/deploy-validate/SKILL.md]
    full-dev:      [skills/code-generation/SKILL.md, agents/tester-agent.md, skills/deploy/SKILL.md, skills/deploy-validate/SKILL.md]
  gates:
    - after: tester-agent → before: deploy (tests must pass)
    - after: deploy → before: deploy-validate (deploy must succeed)
```

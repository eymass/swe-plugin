# Router Audit

## 2026-04-22 — Add full LP deployment pipeline (4-step: design → implement → S3 → CloudFront)

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `dev-implementation` (pipeline + agent + skill creation) | ✅ |
| 3 | Explored project: identified existing skills, agents, router, plugin.json | ✅ |
| 4 | Created `agents/lp-designer.md` — UI/UX designer subagent (Step 1 of pipeline) | ✅ |
| 5 | Created `skills/aws-s3-provisioner/SKILL.md` — S3 public website provisioner skill | ✅ |
| 6 | Created `skills/aws-s3-provisioner/scripts/s3-provision.sh` — shell script: create/configure bucket, sync, verify | ✅ |
| 7 | Created `agents/aws-s3-provisioner.md` — S3 provisioner subagent (scripts-only, Step 3 of pipeline) | ✅ |
| 8 | Created `agents/aws-cloudfront-domain.md` — CloudFront + domain subagent (Step 4, wraps user Python script) | ✅ |
| 9 | Updated `skills/swe-router/SKILL.md` — replaced 2-step landing-page pipeline with 4-step pipeline | ✅ |
| 10 | Updated `.claude-plugin/plugin.json` — registered 3 new agents | ✅ |
| 11 | swe-linter: N/A (markdown + shell only) | ⏭ SKIPPED |
| 12 | swe-tester-agent: N/A (no test suite for shell scripts here) | ⏭ SKIPPED |
| 13 | swe-documentation: no app architecture change (pipeline config only) | ⏭ SKIPPED |

**Task:** Add complete landing page deployment pipeline with 4 sequential steps, each backed by a dedicated subagent or skill

**Pipeline wired:**
```
landing-page intent →
  Step 1: agents/lp-designer.md                         (UI/UX design brief → DESIGN.md)
  Step 2: skills/paid-social-landing-pages/SKILL.md     (implement HTML/CSS/JS, IAB + Pixel + CAPI)
  Step 3: agents/aws-s3-provisioner.md                  (provision S3 public website + sync files)
  Step 4: agents/aws-cloudfront-domain.md               (CloudFront + Lambda@Edge + ACM + Route53)
```

**New artifacts:**
- `agents/lp-designer.md` — Phase-driven design workflow: discovery → IA → tokens → components → CTA rules → DESIGN.md output
- `skills/aws-s3-provisioner/SKILL.md` — Skill wrapping `s3-provision.sh`; documents inputs, expected output, gates, troubleshooting
- `skills/aws-s3-provisioner/scripts/s3-provision.sh` — Idempotent bash: create bucket if not exists, remove public block, apply public-read policy, configure website hosting, sync files, verify HTTP 200
- `agents/aws-s3-provisioner.md` — Scripts-only subagent; validates source dir, runs script, passes endpoint to next step
- `agents/aws-cloudfront-domain.md` — Placeholder subagent wrapping user-supplied Python script; handles new/existing domain modes; gracefully reports when script not yet provided

**Rationale:** The previous `landing-page` pipeline (paid-social → aws-static) lacked a design step and used the private-S3+OAC pattern. The new pipeline adds an explicit design gate (lp-designer), a simpler public-S3 hosting path for the initial deploy (aws-s3-provisioner), and a CloudFront+domain step (aws-cloudfront-domain) that wraps the user's Python script rather than inventing commands. The pipeline is partial-run aware: existing-domain deployments skip Step 4.

---

## 2026-04-21 — Register `landing-page` intent in swe-router

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `dev-implementation` (router config edit) | ✅ |
| 3 | Read `skills/swe-router/SKILL.md` and new skill descriptions | ✅ |
| 4 | Added `landing-page` row to intent detection table | ✅ |
| 5 | Added `### landing-page` pipeline section (paid-social → aws-static) | ✅ |
| 6 | Updated Router Contract YAML with `landing-page` entry | ✅ |
| 7 | swe-linter: N/A (markdown only) | ⏭ SKIPPED |
| 8 | swe-tester-agent: N/A | ⏭ SKIPPED |
| 9 | swe-documentation: no architecture change | ⏭ SKIPPED |

**Task:** Register two new skills (`aws-static-landing-pages`, `paid-social-landing-pages`) with the swe-router under a new `landing-page` intent
**Pipeline:** `landing-page` → paid-social-landing-pages → aws-static-landing-pages
**Changes:** `skills/swe-router/SKILL.md` — new intent row, pipeline block, and contract entry
**Rationale:** The two skills are complementary — paid-social handles content/tracking/IAB, aws-static handles deploy. Default order runs build-then-deploy; skill descriptions still allow each to trigger independently when the user's ask is scoped to one layer.

---

## 2026-04-19 — Add CONVENTION.md discovery step to `code-implementation` SKILL.md

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `dev-implementation` | ✅ |
| 3 | Added Step 0 — Load repo conventions (CONVENTION.md glob before any code reading) | ✅ |
| 4 | Updated Context Gate Q4 to reference CONVENTION.md | ✅ |
| 5 | Added Stop Signal: skipping Step 0 | ✅ |
| 6 | Added Completion Check item for CONVENTION.md | ✅ |
| 7 | swe-linter: N/A (markdown only) | ⏭ SKIPPED |

**Task:** Direct code-implementation agent to search for CONVENTION.md as a hard-constraint source before pattern-spotting  
**Changes:** `skills/code-implementation/SKILL.md` — Step 0 in Discovery Workflow, Context Gate Q4, Stop Signals, Completion Check

---

## 2026-04-19 — Add observability/logging section to `code-implementation` SKILL.md

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `dev-implementation` | ✅ |
| 3 | Read `skills/code-implementation/SKILL.md` | ✅ |
| 4 | Added "Step 5 — Observability & Debuggability" section with logging levels table and rules | ✅ |
| 5 | Added logging checklist item to Completion Check | ✅ |
| 6 | swe-linter: N/A (markdown-only change) | ⏭ SKIPPED |
| 7 | swe-tester-agent: N/A | ⏭ SKIPPED |
| 8 | swe-documentation: no architecture change | ⏭ SKIPPED |

**Task:** Add observability & debuggability guidance (logging with levels) to code-implementation skill  
**Changes:** `skills/code-implementation/SKILL.md` — new Step 5 section + Completion Check item

---

## 2026-04-13 — Wire `swe-linter` into `dev-implementation` pipeline

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `dev-implementation` | ✅ |
| 3 | Read `skills/swe-router/SKILL.md` | ✅ |
| 4 | Added `swe-linter` step between code-implementation and swe-tester-agent | ✅ |
| 5 | Added gate: swe-linter BLOCKING → stops before swe-tester-agent | ✅ |
| 6 | Updated Router Contract YAML | ✅ |

**Task:** Add `swe-linter` agent to the `dev-implementation` pipeline  
**Changes:** `skills/swe-router/SKILL.md` — pipeline sequence, gate rules, Router Contract  
**New pipeline:** `code-implementation → swe-linter → swe-tester-agent → swe-documentation`

---

## 2026-04-13 — Create `swe-linter` Agent

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `dev-implementation` | ✅ |
| 3 | Explored existing agents and `create-subagent` skill | ✅ |
| 4 | Agent created: `agents/swe-linter.md` | ✅ |
| 5 | `plugin.json` updated with new agent registration | ✅ |

**Task:** Create a generic subagent that discovers and runs project-defined lint and type-check commands, producing structured pass/fail output  
**Pipeline:** `dev-implementation` → code-implementation  
**Agent produced:** `agents/swe-linter.md` — lint and type-check specialist; discovers Makefile/package.json/pyproject.toml/CI config; never invents commands; structured Router Contract output

---

## 2026-04-13 — Slim `dev-implementation` pipeline, remove `code` intent

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `code` | ✅ |
| 3 | Skill loaded: `skills/code-implementation/SKILL.md` | ✅ |
| 4 | Removed `code` intent from detection table | ✅ |
| 5 | Removed `### code` pipeline section | ✅ |
| 6 | Removed deployer + validator steps from `dev-implementation` | ✅ |
| 7 | Updated Router Contract YAML | ✅ |

**Task:** Remove `code` pipeline entirely; strip heroku-cloud deploy + validate from `dev-implementation`
**Pipeline:** `code` → code-implementation skill
**Changes:** `skills/swe-router/SKILL.md`

---



## 2026-04-11 — Register `swe-system-design` in swe-router

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `code` | ✅ |
| 3 | Skill loaded: `skills/code-implementation/SKILL.md` | ✅ |
| 4 | Added `system-design` intent to router detection table | ✅ |
| 5 | Added `system-design` pipeline section to router | ✅ |
| 6 | Added `system-design` entry to Router Contract YAML | ✅ |

**Task:** Wire `swe-system-design` agent into swe-router as a first-class intent
**Pipeline:** `code` → code-implementation skill
**Changes:** `skills/swe-router/SKILL.md` — new intent, pipeline block, and contract entry

---

## 2026-04-11 — Create `swe-system-design` Agent

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `code` | ✅ |
| 3 | Skill loaded: `skills/code-implementation/SKILL.md` | ✅ |
| 4 | Explored existing agents for format reference | ✅ |
| 5 | Agent created: `agents/swe-system-design.md` (metadata + when-to-use only) | ✅ |
| 6 | `plugin.json` updated with new agent registration | ✅ |

**Task:** Add new `swe-system-design` agent with metadata and when-to-use section (no body)
**Pipeline:** `code` → code-implementation skill
**Agent produced:** `agents/swe-system-design.md` — system design specialist for architecture, ADRs, technology selection, and scalability design

---



## 2026-04-10 — Create `ux-designer` Agent

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `code` | ✅ |
| 3 | Skill loaded: `skills/create-subagent/SKILL.md` | ✅ |
| 4 | Explored existing agents for format reference | ✅ |
| 5 | Agent created: `agents/ux-designer.md` | ✅ |
| 6 | `plugin.json` updated with new agent registration | ✅ |

**Task:** Turn "Practical UI/UX Design Workflow" content into a structured agent under `/agents`  
**Pipeline:** `code` → create-subagent skill  
**Agent produced:** `agents/ux-designer.md` — principal UI/UX design expert with structured input/output

---

## 2026-04-10 — Create/Rewrite 4 Subagents

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `code` | ✅ |
| 3 | Pipeline: `code` → direct agent authoring | ✅ |
| 4 | Explored existing agents: `planner-agent.md`, `tester-agent.md`, `deployer-agent.md` | ✅ |
| 5 | Skill loaded: `skills/create-subagent/SKILL.md` | ✅ |
| 6 | Agent created: `agents/blueprint.md` (planner) | ✅ |
| 7 | Agent created: `agents/challenger.md` (plan reviewer) | ✅ |
| 8 | Agent created: `agents/probe.md` (tester) | ✅ |
| 9 | Agent created: `agents/launcher.md` (deployer) | ✅ |
| 10 | `plugin.json` updated with 4 new agent registrations | ✅ |

**Task:** Create/rewrite 4 subagents — planner, plan reviewer, tester, deployer  
**Pipeline:** `code` → create-subagent skill  
**Agents produced:**
- `agents/blueprint.md` — feature planning specialist (replaces/complements `planner-agent`)
- `agents/challenger.md` — adversarial plan reviewer (new)
- `agents/probe.md` — test execution specialist (replaces/complements `tester-agent`)
- `agents/launcher.md` — platform-agnostic deployer (replaces/complements `deployer-agent`)

## 2026-04-02 — Review and fix hooks

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `code` (review + fix) | ✅ |
| 3 | Skill: `update-config` | ✅ |
| 4 | Created `.claude/settings.json` with hooks | ✅ |

**Task:** Review hooks and make sure they work  
**Issues fixed:** hooks not registered in settings.json, `CLAUDE_PLUGIN_ROOT` undefined  
**Output:** `/Users/computercomputer/claude-plugin/.claude/settings.json`

---

## 2026-03-31 — Create `create-subagent` skill

| Step | Route | Status |
|------|-------|--------|
| 1 | `swe-router` invoked | ✅ |
| 2 | Intent classified: `code` | ✅ |
| 3 | Pipeline: `code-generation` | ✅ |
| 4 | Skill created: `skills/create-subagent/SKILL.md` | ✅ |

**Task:** Create a skill that creates a perfect Claude Code subagent  
**Pipeline:** `code` → code-generation  
**Output:** `/tmp/claude-job-hevd5692/repo/skills/create-subagent/SKILL.md`

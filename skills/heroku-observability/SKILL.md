-----

## name: heroku-observability
description: Heroku platform observability — logs, dyno health, releases, runtime metrics, add-ons, costs. Use whenever investigating a Heroku app’s health, errors, latency, memory, or spend. Provides bundled diagnostic scripts, CLI recipes, and error-code reference. Invoke this skill any time the target platform is Heroku, even if the user doesn’t explicitly say “observability.”

# Heroku Observability

Toolkit for inspecting Heroku apps. Prefer bundled `scripts/` over ad-hoc CLI — they parallelize common queries and return consistent output.

## Prerequisites

- `heroku` CLI authenticated — verify with `heroku auth:whoami`
- `jq` installed
- App name known (all scripts take `-a <app>`)

## Scripts — run these first

|Script                                            |Purpose                                                  |
|--------------------------------------------------|---------------------------------------------------------|
|`scripts/health_snapshot.sh -a <app>`             |Dynos, last 5 releases, add-ons, error-code count (1h)   |
|`scripts/error_scan.sh -a <app> [-n <lines>]`     |Grouped H/R/L codes, 5xx counts, top exception signatures|
|`scripts/release_diff.sh -a <app> [-n <version>]` |Release N vs N-1 — author, time, description             |
|`scripts/metrics_summary.sh -a <app> [-n <lines>]`|Router p50/p95/p99, memory per dyno, request count       |
|`scripts/cost_snapshot.sh -a <app>`               |Dyno formation + add-on plan list                        |

Run in parallel during the triage signal-intake phase.

## Direct commands (when scripts aren’t enough)

### Logs

- `heroku logs -a <app> -n 1500` — recent lines (max 1500, Logplex retention is short)
- `heroku logs -a <app> --tail` — stream live
- `heroku logs -a <app> --source app --dyno web` — app output, web dynos only
- `heroku logs -a <app> --source heroku` — platform events only (H/R/L codes live here)

For windows > ~1h you need a log drain (Papertrail, Logtail, Datadog). Logplex itself does not retain.

### Dynos

- `heroku ps -a <app>` — status + uptime
- `heroku ps:type -a <app>` — current tier
- `heroku ps:restart [dyno] -a <app>` — **mutating, get approval**

### Releases

- `heroku releases -a <app>` — history
- `heroku releases:info vNNN -a <app>` — detail
- `heroku rollback vNNN -a <app>` — **mutating, get approval**

### Config & add-ons

- `heroku config -a <app>` — env vars (mask secrets in output)
- `heroku addons -a <app>` — attached services + plan
- `heroku pg:info -a <app>` / `heroku redis:info -a <app>` — add-on diagnostics

### Metrics

- One-time setup: `heroku labs:enable runtime-metrics -a <app>` — emits `sample#memory_total`, `sample#load_avg` lines
- Dashboard: `https://dashboard.heroku.com/apps/<app>/metrics/web`
- Programmatic: Platform API `GET /apps/:app/metrics` — see `references/error_codes.md` for the full code list

## Top error codes (full table in `references/error_codes.md`)

- **H10 app crashed** — process exited; find the pre-crash stack in `--source app`
- **H12 request timeout** — 30s router timeout; app is slow, not absent
- **H14 no web dynos** — formation scaled to 0; `heroku ps:scale web=1`
- **H18 server request interrupted** — client or app dropped mid-response
- **H20 app boot timeout** — 60s (web) / 75s (other) boot limit; migrations or slow imports
- **R14 memory quota exceeded** — dyno > tier limit; swapping; upsize or fix leak
- **R15 memory quota vastly exceeded** — dyno killed
- **L10 / L11 logplex drops** — you’re losing log lines; add a drain for fidelity

## Notes for error-triage agent

1. **Scope** — confirm app, then `heroku auth:whoami` + `heroku apps:info -a <app>` to verify access
1. **Signal intake** — run `health_snapshot.sh` first; parallelize `error_scan.sh` + `metrics_summary.sh`
1. **Deploy correlation** — if errors onset within 15 min of a release, run `release_diff.sh` before going deeper
1. **Mutating commands** need approval: `restart`, `scale`, `rollback`, `config:set`, `addons:destroy`, `maintenance:on`

## Cost investigation

`cost_snapshot.sh` shows formation + add-on plans. For anomalies:

- Formation changed — check `heroku releases` for recent `ps:scale` entries
- Add-on tier upgraded — `heroku addons` vs billing page
- Idle apps — review apps and preview apps left running on a team
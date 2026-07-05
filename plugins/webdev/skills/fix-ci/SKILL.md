---
name: fix-ci
description: >
  Triage and fix a failing CI check on a PR or branch. Use when the user says "CI is
  failing", "the build is red", "checks failed", "fix the pipeline", "why did CI fail",
  or any time a PR's checks are red after a push. Reads the failing run's logs via gh,
  finds the first real error, classifies the failure (caused by this branch /
  pre-existing on base / flaky or infra), reproduces it locally, fixes the cause, and
  watches the checks go green. For review COMMENTS on a PR use /webdev:review-pr — the
  two chain naturally when a PR is both red and commented.
---

# Fix CI

Turn a red check green the honest way: find the real failure, reproduce it, fix the **cause**.
Resolve project commands via `/webdev:detect-stack`.

## Hard rule: fix the cause, never the signal

Green is a consequence of correct code, not the goal itself. Never:
- delete, skip, or comment out a failing test to pass
- relax a lint/type rule or sprinkle ignore pragmas just to pass (only if the user explicitly
  decides the rule is wrong — and then as its own commit with the reasoning)
- edit the workflow to remove or soften the failing step
- push empty commits or spam reruns hoping for a different answer

## Step 1: Get onto the failing branch, then locate the run

**Fix where the failure lives.** With a PR: check out its head first — `gh pr checkout <number>`
(already on it? still sync: `git fetch && git pull --ff-only`). Skipping this means Step 5's fix
lands on whatever branch happens to be checked out while the red PR never changes. Without a PR:
confirm `git branch --show-current` is the branch whose CI is red.

Then locate the failure: `gh pr checks <number>` (add `--repo <owner>/<repo>` if needed), or
branch-only: `gh run list --branch <branch> --limit 5`.

`gh pr checks` **does not expose a run id** — for a GitHub Actions check, derive it from the
check's `link` field (`gh pr checks <number> --json name,state,link` — the `/actions/runs/<id>/`
path segment) or by head SHA: `gh run list --commit $(git rev-parse HEAD)`. Then pull only the
failure:
```bash
gh run view <run-id> --log-failed
```
An **external/status check** (a provider posting a status — no Actions run exists) has no run id
at all: follow the check's `link` to the provider's page for the failure detail instead.

Note the workflow, job, and step that failed, and **keep the run id / check name** — the recheck
in Step 7 re-checks exactly these.

## Step 2: Find the first real error

Logs are noisy and failures cascade — a missing dependency at the top produces hundreds of
downstream errors. Scan for the **first** genuine error, not the last, and identify the failure
type; it determines the fix path:

| Type | Log signal | Fix path |
|---|---|---|
| Test failure | runner output, assertion diff | Step 4 with the resolved test command |
| Lint / format | rule name + file:line | resolved lint/format command locally |
| Type-check | compiler errors | resolved typecheck command locally |
| Build | bundler/compiler abort | resolved build command locally |
| Install / deps | lockfile mismatch, unresolvable version, `npm ci` failure | reproduce install locally with CI's exact flags |
| Workflow config | YAML error, unknown action, bad secret/env reference | read the workflow file itself |
| Infra / flake | network timeout, 429/5xx from a registry, runner died, cache miss-then-crash | Step 3's flake path — don't "fix" code for this |

## Step 3: Classify before touching code

- **Caused by this branch** — the error names files/symbols this branch changed, or the check was
  green before the last push. Default assumption when in doubt. → Fix here (Step 4).
- **Pre-existing on base** — verify, don't guess:
  ```bash
  gh run list --branch <base> --workflow "<workflow-name>" --limit 3
  ```
  Base being red on the same check is necessary but **not sufficient** — read the base run's
  failed logs too (`gh run view <base-run-id> --log-failed`) and compare root causes. Same error
  at the same step → pre-existing; base red for a *different* reason does not clear this branch's
  failure. For a genuine pre-existing failure, **don't fold a base fix into this PR** — report it,
  and offer a separate `fix/` branch off base (via `/webdev:new-branch`).
- **Flake / infra** — matches the infra row above and doesn't reference project code. **One**
  rerun is allowed: `gh run rerun <run-id> --failed`. If the same failure repeats, it's real —
  reclassify and stop calling it a flake.

## Step 4: Reproduce locally before fixing

Run the local equivalent of the failing step (resolved test/lint/typecheck/build command).

- **Fails locally too** → good, you have a fast feedback loop. Fix, re-run locally until green.
- **Green locally, red in CI** → don't guess-push. Read the workflow file (`.github/workflows/…`)
  to see exactly what CI runs — command, flags, runtime version — then check the usual divergences:
  - **Version skew** — CI's node/php/python version vs local
  - **Frozen lockfile** — `npm ci` / `--frozen-lockfile` fails on a lockfile drift that a local
    plain install silently "fixed"; re-run install locally with CI's exact flags
  - **Missing env var / secret** — set locally but absent in CI (or vice versa)
  - **Case-sensitive filesystem** — an import that matches on macOS but not on Linux
  - **Test pollution** — ordering/parallelism differences; run the failing test in isolation AND
    in the full suite
  - **Timezone / locale / port assumptions** baked into tests

## Step 5: Fix and verify locally

Apply the fix at the cause. Then verify with the check that actually failed:
- **Test failure** → **invoke `/webdev:run-tests`** at the fix's blast radius.
- **Lint / typecheck / build failure** → re-run that resolved command.
- **Install / dependency failure** → re-run the **exact install command with CI's flags**
  (`npm ci`, `pnpm install --frozen-lockfile`, …) — tests passing against an already-populated
  local dependency tree prove nothing about a fresh CI install.

Must be green locally — CI is not your test runner; every guess-push costs a full CI cycle of
the user's time.

## Step 6: Commit and push

**Invoke `/webdev:commit`** — the PR already exists, so skip its open-pr step. Use the type the
fix actually is (`fix:`, `test:`, `chore(deps):`, `ci:` for workflow-file changes).

## Step 7: Watch the checks — and react to what comes back

Re-check the same workflow/job from Step 1. With a PR: `gh pr checks <number> --watch`.
Branch-only (no PR number): find the run for the pushed commit —
`gh run list --branch <branch> --commit $(git rev-parse HEAD)` — then
`gh run watch <run-id> --exit-status`. The `--exit-status` matters: without it `gh run watch`
exits 0 even when the run fails, and "the command succeeded" gets misread as green. If in doubt,
confirm the conclusion explicitly: `gh run view <run-id> --json conclusion`.
Either way, waiting ~3 min via `ScheduleWakeup` and re-checking also works — don't busy-poll.

- **Green** → done.
- **Same failure** → the fix didn't address the cause. Back to Step 2 with the fresh logs —
  do NOT push another guess on top.
- **Different failure** → progress; new iteration from Step 2.

**Iteration cap: 3 fix commits.** Still red after 3, stop and summarize — what was tried, what
the current failure says, your best hypothesis — for the user to decide. A fourth blind push is
how PRs accumulate "fix ci" commit archaeology.

## Output

- **Check**: workflow / job / step · **Classification**: caused-by-branch / pre-existing / flake
- **Root cause**: one sentence · **Fix**: files touched + commit SHA (or "rerun only")
- **Local repro**: reproduced locally / CI-only (which divergence)
- **Checks now**: green / pending / still failing (+ recommended next step)
- **Pre-existing findings** (if any): what's red on base, suggested separate branch

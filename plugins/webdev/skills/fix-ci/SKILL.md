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

## Step 1: Locate the failing run

With a PR: `gh pr checks <number>` (add `--repo <owner>/<repo>` if needed). Without one:
`gh run list --branch $(git branch --show-current) --limit 5`. Then pull only the failure:
```bash
gh run view <run-id> --log-failed
```
Note the workflow, job, and step that failed — you'll re-check exactly these later.

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
  If base is red on the same check, this branch didn't break it. **Don't fold a base fix into this
  PR** — report it, and offer a separate `fix/` branch off base (via `/webdev:new-branch`).
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

Apply the fix at the cause. Then **invoke `/webdev:run-tests`** at the fix's blast radius (for a
lint/typecheck/build failure, re-run that resolved command instead). Must be green locally —
CI is not your test runner; every guess-push costs a full CI cycle of the user's time.

## Step 6: Commit and push

**Invoke `/webdev:commit`** — the PR already exists, so skip its open-pr step. Use the type the
fix actually is (`fix:`, `test:`, `chore(deps):`, `ci:` for workflow-file changes).

## Step 7: Watch the checks — and react to what comes back

Re-check the same workflow/job from Step 1: `gh pr checks <number> --watch` (or wait ~3 min via
`ScheduleWakeup` and re-check — don't busy-poll).

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

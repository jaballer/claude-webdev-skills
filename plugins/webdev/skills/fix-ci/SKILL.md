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
Resolve project commands via the plugin scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command <test|lint|typecheck|build>`.

## Hard rule: fix the cause, never the signal

Green is a consequence of correct code, not the goal itself. Never:
- delete, skip, or comment out a failing test to pass
- relax a lint/type rule or sprinkle ignore pragmas just to pass (only if the user explicitly
  decides the rule is wrong — and then as its own commit with the reasoning)
- edit the workflow to remove or soften the failing step
- push empty commits or spam reruns hoping for a different answer

## Step 1: Guard the worktree, locate the run, then get onto the failing branch

**First, don't move over dirty state.** This step changes branches; uncommitted edits would ride
along onto the PR/fix branch and get swept into the CI-fix commit. Run `git status --short` — if
it's non-empty, stash (`git stash push -u`) or stop, the same guard `/webdev:new-branch` uses.

**Locate the failing run before switching branches** — capture its id, workflow, and job now,
while the red ref is still checked out or directly queryable. Branching first (below) would leave
a default-branch run un-findable by branch.
- **With a PR:** `gh pr checks <number>` (add `--repo <owner>/<repo>` if needed). `gh pr checks`
  **does not expose a run id** — for a GitHub Actions check, derive it from the check's `link`
  (`gh pr checks <number> --json name,state,link` — the `/actions/runs/<id>/` segment) or by head
  SHA: `gh run list --commit <head-sha>`. An **external/status check** (a provider posting a
  status, no Actions run) has no run id: follow the check's `link` to the provider for the detail.
- **Branch-only (no PR):** first pin down *which* branch is red — the branch the user named, else
  confirm the current branch is the intended one (don't assume you're already on it). Its `<base>`
  for the Step 3 pre-existing check is the default branch it would merge into (resolve as in
  `/webdev:new-branch`). Resolve that branch's **tip SHA** and query the runs *for that commit* —
  scoping to the SHA sidesteps any `--limit` window when many workflows share a push. Among
  **completed** runs, the red one is any whose `conclusion` isn't `success`/`skipped` (`failure`,
  `timed_out`, `cancelled`, `startup_failure`, `action_required`); a still-`queued`/`in_progress`
  run has a null conclusion — wait for it, don't treat it as the failure:
  ```bash
  gh run list --commit <tip-sha> --json databaseId,workflowName,status,conclusion
  ```
  For a branch-only **external/status check** (CircleCI, Buildkite — not an Actions run, so
  `gh run list` never shows it), read the commit's statuses/check-runs directly:
  `gh api repos/<owner>/<repo>/commits/<tip-sha>/status` and `.../check-runs`, then follow the
  provider link — or open a PR so `gh pr checks` surfaces it.

Then, **for a GitHub Actions run**, pull only the failure: `gh run view <run-id> --log-failed`
(`gh run view` reads Actions runs only — an external/status check has no run id, so stay on its
provider link/API from above).

**Now get onto the branch where the fix belongs.**
- **PR:** check out its head — `gh pr checkout <number>` (already on it? still sync:
  `git fetch && git pull --ff-only`). On a **fork (cross-repository) PR**, `gh pr checkout` wires
  pushes to the contributor's fork — that needs fork access or maintainer-edit permission; lacking
  it, stop and report rather than pushing anywhere else.
- **Branch-only:** confirm `git branch --show-current` is the red branch. If it's the **default
  branch** (e.g. a post-merge deploy failure handed over from `/webdev:merge-pr`), don't fix on it
  — **invoke `/webdev:new-branch`** (`fix/` prefix) now that the run id is already captured above;
  the fix still lands through a PR.

**Keep the run id, workflow, job, and check name** — the recheck in Step 7 re-checks exactly these.

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
- **Pre-existing on base** — verify, don't guess. (Skip this entirely when the red ref *is* the
  default branch — the post-merge case from Step 1. There `<base>` is the failing branch itself, so
  "also red on base" is trivially true and meaningless; that regression is yours to fix on the
  `fix/` branch, not to reclassify as pre-existing.)
  ```bash
  gh run list --branch <base> --workflow "<workflow-name>" --limit 3
  ```
  Base being red on the same check is necessary but **not sufficient** — read the base run's
  failed logs too (`gh run view <base-run-id> --log-failed`) and compare root causes. Same error
  at the same step → pre-existing; base red for a *different* reason does not clear this branch's
  failure. For a genuine pre-existing failure, **don't fold a base fix into this PR** — report it,
  and offer a separate `fix/` branch off *that* base: if the PR's base is the default branch,
  `/webdev:new-branch` handles it; if it's a non-default line (`release/1.x`, `develop`), branch
  from it directly (`git checkout <base> && git pull --ff-only && git checkout -b fix/<desc>`),
  since `/webdev:new-branch` always branches from the default branch.
- **Flake / infra** — matches the infra row above and doesn't reference project code. **One**
  rerun is allowed: `gh run rerun <run-id> --failed`, then **wait for that attempt and read its
  conclusion** (`gh run watch <run-id> --exit-status`, or `gh run view <run-id> --json conclusion`)
  — enqueueing a rerun isn't a result. If the same failure repeats, it's real — reclassify and
  stop calling it a flake.

## Step 4: Reproduce locally before fixing

Run the local equivalent of the failing step: `bash -c "$(${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command <test|lint|typecheck|build>)"`.

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
- **Test failure** → **invoke `/webdev:run-tests`** at the fix's blast radius — but when CI failed
  on the *full suite* or under CI-specific flags/runner, re-run that exact command/scope too: a
  green targeted run doesn't clear a suite-wide or flag-specific CI failure.
- **Lint / typecheck / build failure** → re-run that resolved command.
- **Install / dependency failure** → re-run the **exact install command with CI's flags**
  (`npm ci`, `pnpm install --frozen-lockfile`, …) — tests passing against an already-populated
  local dependency tree prove nothing about a fresh CI install.

Must be green locally — CI is not your test runner; every guess-push costs a full CI cycle of
the user's time.

## Step 6: Commit and push

**Invoke `/webdev:commit`** — on a fork PR its push step (step 9) targets the contributor's fork
head, not upstream, matching the fork checkout from Step 1; if the fork isn't writable it stops
rather than stranding the fix on the base repo. If a PR already exists, skip its open-pr step; on
the branch-only path there is no PR — ask whether to open one now (usually yes, so the fix and its
CI status land somewhere reviewable). Use the type the fix actually is (`fix:`, `test:`,
`chore(deps):`, `ci:` for workflow-file changes).

## Step 7: Watch the checks — and react to what comes back

Re-check the **same workflow/job from Step 1**, not just any run on the commit.

**With a PR:** `gh pr checks <number> --watch`. Right after a push GitHub can briefly report **no
checks** for the new head SHA before they register — treat a "no checks reported" error as
transient: wait ~20–30s (`sleep 30`) and retry a couple of times before concluding the
checks are genuinely absent.

**Branch-only (no PR number):** several workflows can run on one commit, so select the Step 1
workflow explicitly rather than watching the first run that comes back. Actions can take a few
seconds to register after a push — if the list comes back empty, retry with the same bounded wait
as the PR path (~20–30s, a couple of times) before concluding no run started:
```bash
gh run list --commit $(git rev-parse HEAD) --workflow "<workflow-name>" --json databaseId,conclusion
gh run watch <run-id> --exit-status
```
`--exit-status` matters: without it `gh run watch` exits 0 even when the run fails, and "the
command succeeded" gets misread as green. If in doubt, confirm explicitly:
`gh run view <run-id> --json conclusion`. Waiting ~3 min with `sleep 180` and re-checking also
works — don't busy-poll.

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

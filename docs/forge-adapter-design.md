# Forge adapter — design proposal

**Status:** proposal, nothing implemented. **Goal:** let the webdev skills work on GitLab (and
later others) without forking each skill, the same way `detect-stack` decoupled them from a
specific package manager.

> **Verification status (glab 1.119.0, checked via `--help` on macOS).** CONTRIBUTING requires
> every CLI/API claim to be verified against the real tool. Two levels are tracked below:
> **flags ✓** = the command/flag exists in `glab --help` (verified). **live ✗** = actual output
> shape and behavior against a real GitLab project — still UNVERIFIED (no GitLab project was
> available on the authoring machine). `evals/forge/verify-gitlab.sh` is a read-only, redacted
> probe that closes the **read-side** live gaps. The **write-side** verbs (create, checkout,
> reply, resolve, retry, merge, `--wait` exit codes) can't be checked read-only — see
> "Scratch-project probes". `gh` rows reflect what the skills already use.

## Problem

`gh` is hardcoded in 10 of 19 skills (~100 calls): `merge-pr`, `review-pr`, `watch-pr`, `fix-ci`,
`open-pr`, `sync-main`, `post-merge-review`, `qa-review`, `fix-bug`, `commit`. The workflow logic
(gates, sibling sweeps, "silence ≠ approval", never fix the signal) is forge-independent; the
commands and data shapes are not.

## Non-goals

- No `-gitlab` twin of each skill. Duplicated skills drift.
- No attempt to hide real semantic differences (see "Semantic gaps"). The adapter normalizes
  *shapes*; skills still branch on genuine forge differences.

## Design

1. **Target resolution — the operation's target decides the forge, not the checkout.**
   In order:
   1. An explicit change-request **URL** (which carries a host) determines **both the forge and
      the repository** for that operation. A bare `owner/repo` or `group/subgroup/repo` carries
      **no provider information** — it may exist on GitHub or GitLab — so it overrides **only the
      repository**; the provider then comes from step 2 (config or the current checkout's host),
      and if neither can say, **ask**. `watch-pr` and `merge-pr` already accept URLs and repos
      other than the checkout; a bare `<n>` must never be resolved against the current checkout
      when a URL or repo was supplied.
   2. Otherwise the current checkout: `.claude/webdev.json` `forge` (`"github"` | `"gitlab"`),
      else the `origin` host — `github.com` → github, `gitlab.com` → gitlab.
   3. Self-hosted hosts: `forgeHosts` maps host → provider, e.g.
      `{"git.example.com": "gitlab", "ghe.example.com": "github"}`. A hostname alone cannot say
      which forge it runs (GitHub Enterprise vs self-managed GitLab), so an unmapped, unknown host
      → **ask**, don't guess.
2. **`scripts/forge <verb> [args]`**, sibling to `resolve-command`. Prints normalized JSON. Skills
   call verbs, never `gh`/`glab` directly. Every verb takes a **target** (`--repo <owner/repo>`
   plus a number, or a URL) — not a bare number — and passes the repo through on every underlying
   call (the same discipline `merge-pr`/`watch-pr` apply to `gh` today).
3. **Per-forge notes** live beside the skill that needs them
   (`skills/merge-pr/forges/gitlab.md`) for edge cases that don't fit a verb.
4. **Vocabulary.** Prose says "PR/MR" or "change request"; `## Output` contracts keep a stable
   field name (`pr`) regardless of forge.

## Verb table

The inventory below is the union of every `gh` call the ten skills make today. A skill is only
"migrated" when it calls no forge CLI directly, so a verb missing here blocks that skill.

| Verb | GitHub (`gh`) | GitLab (`glab`) | Verified |
|---|---|---|---|
| `pr-view <t>` | `gh pr view --json …` | `glab mr view <n> -F json` (`--jq` also available) | flags ✓ / live ✗ |
| `pr-detail <t>` | `gh pr view --json title,body,mergedAt,mergedBy,additions,deletions,files,comments,reviews` | `glab mr view <n> -F json` + `glab mr view <n> --comments -F json` + approvals: `glab mr approvers <n> -F json` and `glab api projects/:id/merge_requests/<iid>/approval_state` (see "reviews[] normalization"). **`files`/`additions`/`deletions` are derived** from `glab mr diff <n> --raw`: files from `diff --git a/… b/…` headers, additions/deletions from `+`/`-` lines excluding the `+++`/`---` headers (approximate: a removed line whose own text starts with `--` looks like a header and is undercounted — fine for review context, not for billing). The MR JSON only has `changes_count` (a string, capped like `"1000+"`), which is not a usable substitute | flags ✓ / live ✗ (derivation checked by the probe) |
| `pr-diff <t>` | `gh pr diff` | `glab mr diff <n> --raw` | flags ✓ / live ✗ |
| `pr-list` (`--state`, `--head`, `--base`, `--limit`) → items per "`pr-list` item shape" | `gh pr list --state … --head … --base …` | `glab mr list [--all\|--merged\|--closed] -s <source> -t <target> -F json` (bare `mr list` is **open-only**) | flags ✓ / live ✗ |
| `pr-create` | `gh pr create --base --title --body` | `glab mr create --target-branch --title --description` (or `--description-file`), `--draft` | flags ✓ / live ✗ |
| `pr-edit <t>` | `gh pr edit --body …` | `glab mr update <n> --description-file …` (also `--title`, `--draft`/`--ready`) | flags ✓ / live ✗ |
| `pr-checkout <t>` | `gh pr checkout` | `glab mr checkout <n>` (`-b`, `-u/--set-upstream-to`) | flags ✓ / live ✗ |
| `pr-checks <t>` | `gh pr checks --json` (run id parsed from the check `link`) | `glab ci get --merge-request <iid> -F json` (pipeline + jobs); `glab ci status -F json` is branch-scoped | flags ✓ / live ✗ |
| `pr-update-branch <t> --strategy <merge\|rebase>` | `gh pr update-branch` (merge, the default) / `gh pr update-branch --rebase` | `rebase` → `glab mr rebase <n>`; **`merge` → unsupported**: no merge-base-into-head option found in `glab mr update`/`rebase` help, so the adapter reports `unsupported` and the skill falls back to a local `git merge` + push or asks | flags ✓ / live ✗ |
| `pr-merge <t> (--method <squash\|merge\|rebase> \| --queue) --delete-branch <bool> --expect-sha <sha> --auto <bool> [--subject <s>] [--body <b>]` | `gh pr merge --squash\|--merge\|--rebase [--delete-branch] --match-head-commit <sha> [--auto] [--subject <s>] [--body <b>]`; **`--queue`** omits every strategy flag but keeps `--match-head-commit` (the queue owns the method) | `glab mr merge <n> [--squash\|--rebase] [--remove-source-branch] --sha <sha> --auto-merge=<bool> --yes`; squash subject → `--squash-message <s>`, merge-commit message → `-m/--message <s>`; `--queue` → merge-train analogue via `--auto-merge=true` (whether the method flags are then ignored is unverified) | flags ✓ / live ✗ |
| `repo-view` (nameWithOwner, default branch, allowed merge methods) | `gh repo view --json nameWithOwner,defaultBranchRef,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` | `glab repo view -F json`; merge policy via `glab api projects/:id` (`merge_method`, `squash_option` — field names from docs, not observed) | flags ✓ / live ✗ |
| `branch-protection <branch>` → `{requiresLinearHistory, requiresMergeQueue, requiredChecks[], sources[]}` | **both** legacy protection `gh api repos/<o>/<r>/branches/<b>/protection` **and** rulesets `gh api repos/<o>/<r>/rules/branches/<b>` (active repo + org rulesets that apply to the branch, e.g. a `required_linear_history` rule); a branch with only rulesets has no legacy protection, so merge both into one result and record which `sources[]` produced each flag | GitHub rules endpoint ✓ (verified: returns `[]` with none) / GitLab: `glab api projects/:id/protected_branches` + project `merge_method` (`ff` ⇒ linear history) — from docs, not observed; live ✗ |
| `comments-list <t>` → items per "`comments-list` item shape" | REST `gh api --paginate …/pulls/<n>/comments` (inline) + `…/issues/<n>/comments` (top-level), **plus the GraphQL `reviewThreads` query** (paginated; `nodes{id isResolved comments{nodes{databaseId}}}`) to attach `threadId`/`isResolved` by matching each thread's comment `databaseId` — REST exposes neither | `glab mr note list <n>` (marked EXPERIMENTAL) or `glab mr view <n> --comments --unresolved -F json`; raw fallback `glab api --paginate --output ndjson projects/:id/merge_requests/:iid/discussions` | flags ✓ / live ✗ |
| `comment-reply` (reply **inside a thread**) | `gh api …/pulls/<n>/comments/<id>/replies` | `glab mr note create <n> --reply <discussion-id> -m …` | flags ✓ / live ✗ |
| `pr-comment <t>` (new **top-level** comment, not a thread reply — `review-pr`'s general reply) | `gh pr comment <n> -b …` / `gh api …/issues/<n>/comments` | `glab mr note create <n> -m … --resolvable=false` (`--resolvable=false` cannot combine with `--reply`) | flags ✓ / live ✗ |
| `thread-resolve` | GraphQL `resolveReviewThread` | `glab mr note resolve <discussion-id> <n>` (and `reopen`) | flags ✓ / live ✗ |
| `ci-runs` (`--commit`, `--branch`, `--workflow`) | `gh run list --commit … --branch … --workflow …` | `glab ci list --sha <sha> --ref <branch> --status <s> -F json` ("workflow" has no direct analogue) | flags ✓ / live ✗ |
| `commit-checks <sha>` (external/status checks **not** visible to `ci-runs`, e.g. CircleCI/Buildkite; used by `fix-ci` on a branch without a PR) → `[{name,state,link,source}]` | `gh api repos/<o>/<r>/commits/<sha>/status` (`statuses[]`) **and** `…/commits/<sha>/check-runs` (both verified to exist) | `glab api projects/:id/repository/commits/<sha>/statuses` — endpoint from docs, not observed; pipeline jobs also come from `glab ci get` | GitHub ✓ / GitLab endpoint ✗, live ✗ |
| `ci-logs --run <id> --job <id>` | `gh run view --log-failed` | `glab ci trace <job-id\|name> -p <pipeline-id>` — **no `--failed` equivalent**: list failed jobs first (`glab ci get -F json` / `--status failed`), then trace each | flags ✓ / live ✗ |
| `ci-rerun --run <id> [--job <id>]` | `gh run rerun <run-id> --failed` | `glab ci retry <job-id\|name> -p <pipeline-id>` — retries **one job**, not all failed jobs; loop over failed job ids | flags ✓ / live ✗ |
| `ci-watch --run <id>` | `gh run watch <run-id> --exit-status` | **`glab ci status` has no `--pipeline-id`** (branch-scoped only, so it can watch a newer pipeline than the one under triage); to watch one exact pipeline, poll `glab ci get -p <pipeline-id> -F json`. `ci status --wait` is acceptable only when the branch has a single pipeline; its exit-code behavior is unknown | flags ✓ / live ✗ |
| `issue-view <n>` | `gh issue view` | `glab issue view <n> -F json` | flags ✓ / live ✗ |
| `whoami` | `gh api user --jq .login` | `glab api user` (no dedicated command found) | flags ✓ / live ✗ |

`pr-merge` takes the **method** and the **delete-source decision** from the caller: `merge-pr`
chooses among squash/merge/rebase from config and repo policy, and deliberately omits branch
deletion when open stacked PRs use the head as their base (GitLab's behavior for dependents is
unverified). The adapter must never default either. The one exception to "method is required" is
an explicit **`--queue`** mode: when the base uses a merge queue the queue owns the method, so
`merge-pr` passes no strategy (but still pins `--expect-sha`); `--method` and `--queue` are mutually
exclusive. The optional `--subject`/`--body` carry the squash title `merge-pr` chooses (the PR
title, already conventional-commits shaped) so a migrated squash doesn't change resulting history. Caveat: on GitLab the *merge method* (merge
commit / semi-linear / fast-forward) is largely a **project setting**; `--squash`/`--rebase` only
toggle squash-before-merge and pre-merge rebase, so a caller's `--method merge` may be
unsatisfiable on a fast-forward-only project — `repo-view` must expose the project's method so
`merge-pr` can rule options out *before* confirmation, as it does on GitHub.

Corrections vs the first draft of this table: `-F/--output` is the JSON flag (not `--output json`);
`mr view --comments`, `mr note resolve|reopen|list`, and `mr create --description-file` exist, so raw
API calls are only a fallback; `ci retry` is per-job; `ci trace` has no `--failed`.

Also observed running `glab` 1.119.0 against a GitHub-remote repo (no GitLab auth): every command
exits non-zero with `none of the git remotes … point to a known GitLab host`. So `glab` only works
when a remote matches an authenticated host (or `-R`/`--hostname` is passed) — `scripts/forge` must
surface that as a clear "run `glab auth login`" message, and each `forgeHosts` entry for a
self-hosted instance has to line up with what `glab auth login --hostname` registered. Also:
`glab issue list -F` is `--output-format` (`details|ids|urls`), **not** JSON — use `--jq` or
`glab api` for issue lists; and `glab api --paginate` has no `--slurp` in 1.119.0 — use
`--output ndjson` and parse per line.

### Normalized shapes

Two verbs, split by cost. Fields are the union of what current consumers read (`merge-pr`,
`watch-pr`, `review-pr`, `fix-ci`, `commit`, `post-merge-review`).

- **`pr-view`** (cheap, gating): `number, url, title, state, isDraft, baseRef, headRef, headSha,
  isCrossRepository, mergeState` (normalized enum — see below) `, mergeStateRaw` (the forge's own
  value: GitHub `mergeStateStatus`, GitLab `detailed_merge_status`) `, mergeable, reviewState,
  mergeCommitSha` (null until merged; GitHub `mergeCommit.oid`, GitLab `merge_commit_sha` / `squash_commit_sha` — field names unverified) `,
  checks[{name,state,link,runId,jobId}]`. `mergeCommitSha` lets `merge-pr` attribute post-merge base-branch runs
  to *this* merge (`ci-runs --commit <sha>`) rather than an older red run. `runId`/`jobId` (GitHub Actions run/job; GitLab
  pipeline/job) are **stable identifiers** that `ci-logs`, `ci-rerun`, and `ci-watch` require, so
  `fix-ci` acts on the exact execution it triaged and never on a newer or unrelated one.
- **`pr-detail`** (heavier, review): everything above plus `body, mergedAt, mergedBy, additions,
  deletions, files[], comments[], reviews[]`.

- **`pr-list` item shape** (stable across forges; superset of what `open-pr`, `sync-main`,
  `qa-review`, `merge-pr` read): `number, url, title, state, baseRef, headRef, headSha, mergedAt,
  mergeCommitSha`. GitHub: `number,url,title,state,baseRefName,headRefName,headRefOid,mergedAt,mergeCommit`.
  GitLab: `iid,web_url,title,state,target_branch,source_branch,sha,merged_at,merge_commit_sha`.
- **`comments-list` item shape**: `commentId, threadId, kind: inline|top-level, isResolved,
  isOutdated, user, createdAt, body, path, line`. `user` and `createdAt` are required — `review-pr`'s
  recheck filters to comments created after its push and not authored by itself; without them a
  migrated skill re-enters the fix loop on its own replies. GitLab: `threadId` = discussion id;
  `user`/`createdAt` from each note's author/`created_at`.

**Identifiers flow between verbs.** Any verb whose output another verb consumes returns the ID that
verb needs: `comments-list` returns `{commentId, threadId, isResolved, isOutdated, body, path, line}`
(GitLab: `threadId` = discussion id) for `comment-reply`/`thread-resolve`; `pr-checks` returns the
run/job ids above.

### `reviews[]` normalization (in `pr-detail`)

`reviews[{user, state: approved|changes_requested|commented, commitSha?, submittedAt, body}]` plus
`approvals{required, given, coversHead}` where **`coversHead` is tri-state: `true | false | unknown`**.

- GitHub: from `reviews` (per-review state and commit) → `true`/`false`.
- GitLab has no per-review commit and no comment-review "state". Build `approved` entries from
  `approvers`/`approval_state` (`approved_by`, rule counts) and treat discussion notes as `commented`.
  `coversHead` is `true` **only when** the project removes approvals on new commits (any surviving
  approval then necessarily post-dates the current head). When that setting is off, the setting only
  says approvals persist — it cannot say whether one was submitted before or after the current head —
  so `coversHead` is **`unknown`**, never derived. `merge-pr` treats `unknown` like `false`: stop and
  ask, unless another verified source ties the approval to the head.
- `changes_requested` has no confirmed GitLab source — leave it unset rather than guess.

Normalized `mergeState`: `clean | blocked | behind | conflicting | unstable | unknown`. Each
forge's raw value maps onto it in one table per forge; `merge-pr` gates on the normalized value
but still reads `mergeStateRaw` for forge-specific edge cases (e.g. GitHub `HAS_HOOKS`).

## Semantic gaps (the adapter cannot paper over these)

| Area | GitHub | GitLab (partly UNVERIFIED) | Impact |
|---|---|---|---|
| Approval | single `reviewDecision` | rule-based approvals; `detailed_merge_status` (e.g. `not_approved`, `discussions_not_resolved`, `ci_must_pass`, `need_rebase`) | `merge-pr` gate table needs a per-forge column |
| Stale approval | approval may cover an older head | "remove approvals on new commits" is a project setting; when off, coverage of the current head is **unknowable** from the approval alone | `coversHead` is tri-state; `unknown` ⇒ `merge-pr` stops and asks |
| Merge queue / auto-merge | merge queue; `gh pr merge --auto` is opt-in | merge trains; **`glab mr merge` enables auto-merge by default when a pipeline is running** (`--auto-merge=false` to merge immediately) — verified in `--help` | `merge-pr` must pass `--auto-merge=<bool>` explicitly after its own gates, or it will queue instead of merging |
| Merge method | per-merge choice, gated by repo allow-flags; a merge queue owns it | project-level merge method + per-MR squash/rebase toggles | `pr-merge --method` may be unsatisfiable; `--queue` omits it; see note above |
| Forks | `gh pr checkout` wires push remote | MRs from forks differ in permissions and remote setup | shared fork logic in `commit`/`review-pr`/`fix-ci` must be re-verified |
| Threads | review threads (GraphQL) | discussions, per-note resolvable flag | `review-pr` resolve step |
| CI unit | workflow *run* | *pipeline* of *jobs*, stages | `fix-ci` log-reading step |
| Bots | Codex/Copilot/CodeRabbit as reviews | bots post as notes/discussions | `review-pr` "who counts as a reviewer" |

## Rollout

1. Run `evals/forge/verify-gitlab.sh` on a machine with a GitLab project and paste its (redacted)
   output back; fix the **read-side** `live ✗` gaps. Then run the scratch-project probes below for
   the write-side verbs.
2. Add `scripts/forge` + `forge`/`forgeHosts` keys (update `examples/webdev.json`, README key table,
   `detect-stack` Output contract — CONTRIBUTING says these stay in sync).
3. **Phase 1 (read-mostly, low risk):** `open-pr` (`pr-list`, `repo-view`, `pr-edit`, `pr-create`),
   `sync-main` (`pr-list`), `qa-review` (`pr-list`), `post-merge-review` (`pr-detail`, `pr-diff`,
   `pr-list`), `fix-bug` (`issue-view`).
4. **Phase 2 (mutating / fork-aware):** `commit` (fork push-remote logic via `pr-view`/`pr-checkout`,
   then `open-pr`), `fix-ci` (`pr-checks`, `ci-runs`, `commit-checks`, `ci-logs`, `ci-rerun`, `ci-watch`),
   `review-pr` (`comments-list`, `comment-reply`, `pr-comment`, `thread-resolve`, `whoami`), `watch-pr`,
   `merge-pr` (`pr-view`, `repo-view`, `branch-protection`, `pr-merge`, `pr-update-branch`, `ci-runs`).
5. All ten skills from "Problem" are covered; a skill counts as migrated only when a grep for
   `\bgh\b|\bglab\b` in its `SKILL.md` finds nothing outside its per-forge notes.
6. Fixture-based eval for `forge` (mirror `evals/detect-stack`), including a GitLab CI example.
7. Update skill descriptions so "open an MR" triggers the same skills.

## Scratch-project probes (write-side, manual, opt-in)

`verify-gitlab.sh` is read-only by design, so it cannot verify these. Run them by hand in a
**throwaway** GitLab project (never a real one) and record exit codes and output shapes:

- `pr-create` / `pr-edit`: `glab mr create --draft …`, then `glab mr update <n> --description-file …`
- `pr-checkout` incl. a fork MR and the resulting push remote / upstream
- `pr-comment`: `glab mr note create <n> -m … --resolvable=false` — confirm it is a top-level, non-resolvable note
- `pr-update-branch`: `glab mr rebase` on a scratch MR; confirm there is no merge-style alternative
- `ci-watch`/`ci-logs` on a specific pipeline while a newer pipeline exists on the branch
- `comment-reply` and `thread-resolve`: `glab mr note create --reply …`, `glab mr note resolve …`
- `pr-merge`: squash with `--squash-message` and confirm the resulting commit subject; `--auto-merge=true` on a project with merge trains — is the method flag ignored?
- `commit-checks`: an external commit status posted to a scratch commit (`glab api … /statuses`) appears in the mapping
- `ci-rerun`: `glab ci retry <job>` on a failed job; confirm it retries only that job
- `pr-merge`: with a **wrong** `--sha` (expect refusal + exit code), with `--auto-merge=false`
  vs default while a pipeline is running, and the delete-source flag
- `ci-watch`: `glab ci status --wait` on a failing pipeline — is the exit code non-zero?

## Open questions

- Ship `glab` support as one plugin, or a separate `webdev-gitlab` add-on plugin?
- Minimum supported `glab` version? Flags above were checked on 1.119.0; older releases used `--when-pipeline-succeeds` and lack some `mr note` subcommands (unconfirmed).
- Self-hosted GitLab: any API-version floor we should document?
- Bitbucket/Gitea: designed-for or explicitly out of scope?

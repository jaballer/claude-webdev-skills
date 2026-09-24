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

> **Editing this doc?** Run `bash evals/forge/check-design.sh` first (CI runs it too). It checks the things
> review kept finding: every verb has an output contract, every enum is defined, every `gh` call in
> the skills maps to a verb, paginated endpoints paginate, every row carries a verification tag.

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
   call verbs, never `gh`/`glab` directly. Every verb takes a fully resolved **target**
   `{host, repo, number}` (or a URL, from which all three are parsed) — never a bare number or a
   bare repo path — and the adapter passes **host and repo** on every underlying call, so a
   self-hosted URL can't silently hit a same-named project on the CLI's default host:
   - GitHub: `gh … --repo <host>/<owner>/<repo>` (the `[HOST/]OWNER/REPO` form — verified in
     `gh pr view --help`) and `gh api --hostname <host>`.
   - GitLab: `glab … -R <group/subgroup/repo or full URL>` (verified: `-R` accepts a full or Git
     URL) and `glab api --hostname <host>`.
   The resolved host comes from the URL, else `forgeHosts`/the checkout (see step 1).
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
| `pr-checks <t>` | `gh pr checks --json name,bucket,state,link,workflow` (`bucket` verified: `pass\|fail\|pending\|skipping\|cancel`; run id parsed from `link`) | `glab ci get --merge-request <iid> -F json` (pipeline + jobs); `glab ci status -F json` is branch-scoped | flags ✓ / live ✗ |
| `pr-update-branch <t> --strategy <merge\|rebase>` | `gh pr update-branch` (merge, the default) / `gh pr update-branch --rebase` | `rebase` → `glab mr rebase <n>`; **`merge` → unsupported**: no merge-base-into-head option found in `glab mr update`/`rebase` help, so the adapter reports `unsupported` and the skill falls back to a local `git merge` + push or asks | flags ✓ / live ✗ |
| `pr-merge <t> (--method <squash\|merge\|rebase> \| --queue) --delete-branch <bool> --expect-sha <sha> --auto <bool> [--subject <s>] [--body <b>]` | `gh pr merge --squash\|--merge\|--rebase [--delete-branch] --match-head-commit <sha> [--auto] [--subject <s>] [--body <b>]`; **`--queue`** omits every strategy flag but keeps `--match-head-commit` (the queue owns the method) | `glab mr merge <n> [--squash\|--rebase] [--remove-source-branch] --sha <sha> --auto-merge=<bool> --yes`; squash subject → `--squash-message <s>`, merge-commit message → `-m/--message <s>`; `--queue` → merge-train analogue via `--auto-merge=true` (whether the method flags are then ignored is unverified) | flags ✓ / live ✗ |
| `repo-view` (nameWithOwner, default branch, allowed merge methods) | `gh repo view --json nameWithOwner,defaultBranchRef,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` | `glab repo view -F json`; merge policy via `glab api projects/:id` (`merge_method`, `squash_option` — field names from docs, not observed). GitLab `allowedMergeMethods[]` is **derived**: `merge_method` `merge → [merge]`, `rebase_merge → [merge, rebase]`, `ff → [rebase]` (semi-linear/fast-forward histories), plus `squash` unless `squash_option` is `never`; an unrecognized value → the list is omitted and `merge-pr` asks | flags ✓ / live ✗ |
| `branch-protection <branch>` → `{requiresLinearHistory, requiresMergeQueue (true\|false\|unknown), requiredChecks[], sources[]}` | **both** legacy protection `gh api repos/<o>/<r>/branches/<b>/protection` **and** rulesets `gh api repos/<o>/<r>/rules/branches/<b>` (active repo + org rulesets that apply to the branch, e.g. a `required_linear_history` rule); a branch with only rulesets has no legacy protection, so merge both into one result and record which `sources[]` produced each flag | GitHub rules endpoint ✓ (verified: returns `[]` with none) / GitLab: `glab api projects/:id/protected_branches` + project `merge_method` (`ff` ⇒ linear history). **`requiresMergeQueue` on GitLab** comes from the project's `merge_trains_enabled` (from docs, not observed; the probe checks it is present): `true` ⇒ `true`; field present and false ⇒ `false`; field **absent** (e.g. merge trains unavailable on this tier/version) ⇒ **`unknown`, never `false`**. GitHub: a `merge_queue` rule in the rulesets result (rule type from docs, not observed). `merge-pr` asks before choosing `--method` vs `--queue` when the value is `unknown` — from docs, not observed; live ✗ |
| `comments-list <t>` → items per "`comments-list` item shape" | REST `gh api --paginate …/pulls/<n>/comments` (inline) + `…/issues/<n>/comments` (top-level), **plus the GraphQL `reviewThreads` query** (paginated; `nodes{id isResolved comments{nodes{databaseId}}}`) to attach `threadId`/`isResolved` by matching each thread's comment `databaseId` — REST exposes neither | `glab mr note list <n>` (marked EXPERIMENTAL) or `glab mr view <n> --comments --unresolved -F json`; raw fallback `glab api --paginate --output ndjson projects/:id/merge_requests/:iid/discussions` | flags ✓ / live ✗ |
| `comment-reply` (reply **inside a thread**) | `gh api …/pulls/<n>/comments/<id>/replies` | `glab mr note create <n> --reply <discussion-id> -m …` | flags ✓ / live ✗ |
| `pr-comment <t>` (new **top-level** comment, not a thread reply — `review-pr`'s general reply) | `gh pr comment <n> -b …` / `gh api …/issues/<n>/comments` | `glab mr note create <n> -m … --resolvable=false` (`--resolvable=false` cannot combine with `--reply`) | flags ✓ / live ✗ |
| `thread-resolve` | GraphQL `resolveReviewThread` | `glab mr note resolve <discussion-id> <n>` (and `reopen`) | flags ✓ / live ✗ |
| `ci-runs` (`--commit`, `--branch`, `--workflow`) → items per "`ci-runs` item shape" | `gh run list --commit … --branch … --workflow …` | `glab ci list --sha <sha> --ref <branch> --status <s> -F json` ("workflow" has no direct analogue) | flags ✓ / live ✗ |
| `commit-checks <sha>` (external/status checks **not** visible to `ci-runs`, e.g. CircleCI/Buildkite; used by `fix-ci` on a branch without a PR) → `[{name,state,link,source}]` | `gh api --paginate --slurp repos/<o>/<r>/commits/<sha>/status` (`statuses[]`) **and** `… /commits/<sha>/check-runs` (`check_runs[]`) — both endpoints and `--slurp` verified; **must paginate and concatenate every page** (a bare `gh api` returns only the first 30 items, so a failing external check on page 2 would be missed and `fix-ci` would conclude nothing failed) | `glab api --paginate --output ndjson projects/:id/repository/commits/<sha>/statuses` (a branch/tag name is also accepted per docs) — endpoint from docs, not observed; pipeline jobs also come from `glab ci get` | GitHub ✓ / GitLab endpoint ✗, live ✗ |
| `ci-logs --run <id> [--job <id>]` — with `--job` omitted the adapter **discovers the failed jobs of that run itself** and returns one log per job | `gh run view <run-id> --log-failed` (already failure-scoped); with `--job`, `gh run view --job <id> --log` | `glab ci get -p <pipeline-id> --status failed -F json` to list failed job ids, then `glab ci trace <job-id> -p <pipeline-id>` for each (**no `--failed` equivalent** in `ci trace`) | flags ✓ / live ✗ |
| `ci-rerun --run <id> [--job <id>]` | `gh run rerun <run-id> --failed` | `glab ci retry <job-id\|name> -p <pipeline-id>` — retries **one job**, not all failed jobs; loop over failed job ids | flags ✓ / live ✗ |
| `ci-watch --run <id>` | `gh run watch <run-id> --exit-status` | **`glab ci status` has no `--pipeline-id`** (branch-scoped only, so it can watch a newer pipeline than the one under triage); to watch one exact pipeline, poll `glab ci get -p <pipeline-id> -F json`. `ci status --wait` is acceptable only when the branch has a single pipeline; its exit-code behavior is unknown | flags ✓ / live ✗ |
| `issue-view <t>` → items per "`issue-view` shape" | `gh issue view --json number,title,body,state,url,labels` (fields verified) | `glab issue view <n> -F json` | flags ✓ / live ✗ |
| `whoami` → login string (same shape as a comment's `user`) | `gh api user --jq .login` | `glab api user --jq .username` (no dedicated command found) | flags ✓ / live ✗ |

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
- **`ci-runs` item shape**: `runId, name, status: queued|in_progress|completed,
  conclusion: success|failure|cancelled|skipped|timed_out|action_required|null, branch, headSha,
  trigger, url, createdAt` — what `fix-ci` needs to select, wait on, and later re-check the *same*
  execution, and what `merge-pr` needs to attribute post-merge runs. GitHub: `databaseId,
  workflowName, status, conclusion, headBranch, headSha, event, url, createdAt` (all verified
  `gh run list --json` fields). GitLab pipeline: `id, name?, status, ref, sha, source, web_url,
  created_at`; GitLab has one `status` field, so it splits into `status`/`conclusion`:
  `created|pending|preparing|waiting_for_resource` → `queued`, `running` → `in_progress`,
  `success|failed|canceled|skipped` → `completed` + `success|failure|cancelled|skipped`,
  `manual` → `completed` + `action_required` (mapping from docs, not observed; a pipeline has no
  "workflow", so `name` is the pipeline name when present, else null).
- **`issue-view` shape**: `number, title, body, state: open|closed, url, labels[]` — what `fix-bug`
  reads to classify a report before branching. GitLab: `iid → number`, `description → body`,
  `state` `opened → open`, `web_url → url`.
- **`comments-list` item shape**: `commentId, threadId, kind: inline|top-level, isResolved,
  isOutdated, user, createdAt, body, path, line`. `user` and `createdAt` are required — `review-pr`'s
  recheck filters to comments created after its push and not authored by itself; without them a
  migrated skill re-enters the fix loop on its own replies. GitLab: `threadId` = discussion id;
  `user`/`createdAt` from each note's author/`created_at`.

**Identifiers flow between verbs.** Any verb whose output another verb consumes returns the ID that
verb needs: `comments-list` returns the full item shape above (incl. `threadId`) for
`comment-reply`/`thread-resolve`; `pr-checks` and `ci-runs` return the run/job ids above.

### Normalized enums

Every enum used by a shape is defined here, with both mappings. **Rule: an unrecognized native
value maps to `unknown` (or the enum's neutral member), never to a passing/terminal one** — a
provider adding a state must never turn a gate green. All GitLab value sets below are from docs,
not observed; GitHub sets are verified where noted.

- **`state`** (change request): `open | merged | closed | unknown`. GitHub `OPEN|MERGED|CLOSED`
  (`OPEN` observed on `gh pr view --json state`); GitLab `opened → open`, `merged → merged`,
  `closed → closed`, `locked → open` (a merge is in progress). `watch-pr` treats `merged` and
  `closed` as terminal, so the lowercase/uppercase difference must never leak through.
- **`checks[].state`**: `pass | pending | fail | skipped | cancelled | action_required | unknown`.
  GitHub: from `gh pr checks --json bucket` (`pass→pass`, `fail→fail`, `pending→pending`,
  `skipping→skipped`, `cancel→cancelled`; `bucket` verified, `pass` observed); `action_required`
  is not a bucket, so it comes from the run's conclusion (`ci-runs`) when needed. GitLab job or
  pipeline status: `created|pending|preparing|waiting_for_resource|scheduled|running → pending`,
  `success → pass`, `failed → fail`, `canceled → cancelled`, `skipped → skipped`,
  `manual → action_required`, anything else → `unknown`.
- **`mergeable`**: `true | false | unknown`. GitHub `MERGEABLE → true`, `CONFLICTING → false`,
  `UNKNOWN → unknown` (`MERGEABLE` observed). GitLab: `has_conflicts=false` and a settled
  `detailed_merge_status` → `true`; `has_conflicts=true` → `false`; `checking|unchecked` → `unknown`.
- **`mergeState`**: `clean | blocked | behind | conflicting | unstable | unknown`. GitHub
  `mergeStateStatus`: `CLEAN → clean`, `BLOCKED|DRAFT → blocked`, `BEHIND → behind`,
  `DIRTY → conflicting`, `UNSTABLE → unstable`, `HAS_HOOKS → clean` (raw kept in `mergeStateRaw`),
  `UNKNOWN → unknown` (`CLEAN` observed). GitLab `detailed_merge_status`: `mergeable → clean`,
  `need_rebase → behind`, `conflict → conflicting`, `ci_still_running → unstable`,
  `ci_must_pass|not_approved|discussions_not_resolved|draft_status|blocked_status|requested_changes|external_status_checks → blocked`,
  `checking|unchecked → unknown`. `merge-pr` gates on `mergeState` and reads `mergeStateRaw` for
  forge-specific edge cases.
- **`reviewState`**: `approved | changes_requested | review_required | none | unknown`. GitHub
  `reviewDecision` (`APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`; empty string `→ none`, observed
  on this repo). GitLab: derived from `approval_state` — all rules satisfied → `approved`, any unmet →
  `review_required`, no rules → `none`; never `changes_requested` (no confirmed source).
- **`user`**: a **login string** everywhere it appears (`comments-list`, `reviews[]`, `whoami`):
  GitHub `.login`, GitLab `.username` — so `review-pr` can compare `whoami` to a comment's `user`.

### Output contracts (every verb)

Every verb's return value, so no consumer has to guess. Shapes are defined above; the rest are
short. `scripts/forge` validates output against these before printing; failures are
`{"error": {"code", "message", "raw"}}` with the forge's message preserved in `raw`.

| Verb | Returns |
|---|---|
| `pr-view` | the `pr-view` shape |
| `pr-detail` | `pr-view` + the `pr-detail` fields |
| `pr-diff` | raw unified diff text |
| `pr-list` | `[` `pr-list` item `]` |
| `pr-create` | `{number, url}` |
| `pr-edit` | `{number, url}` |
| `pr-checkout` | `{localBranch, pushRemote, isCrossRepository}` (what `commit`/`review-pr` need to push a fork PR correctly) |
| `pr-checks` | `[{name, state, link, runId, jobId}]` (`state` per enums) |
| `pr-update-branch` | `{updated: true}` or `{updated: false, reason: "unsupported"\|"conflict"\|…}` |
| `pr-merge` | `{result: "merged"\|"queued"\|"refused", mergeCommitSha?, reason?}` — `queued` for a merge queue/train, `refused` for a wrong `--expect-sha` or failed gate |
| `repo-view` | `{host, nameWithOwner, defaultBranch, allowedMergeMethods[], mergeMethod?}` (`mergeMethod` only where the forge has a project-level one) |
| `branch-protection` | `{requiresLinearHistory, requiresMergeQueue, requiredChecks[], sources[]}` |
| `comments-list` | `[` `comments-list` item `]` |
| `comment-reply` | `{commentId, threadId, url}` |
| `pr-comment` | `{commentId, url}` |
| `thread-resolve` | `{threadId, isResolved}` |
| `ci-runs` | `[` `ci-runs` item `]` |
| `commit-checks` | `[{name, state, link, source: "status"\|"check-run"\|"pipeline-job"}]` (`state` per enums; all pages concatenated) |
| `ci-logs` | `[{jobId, name, log}]` |
| `ci-rerun` | `{runId, jobIds[]}` (the jobs actually restarted) |
| `ci-watch` | `{status, conclusion}` (the `ci-runs` enums) once terminal |
| `issue-view` | the `issue-view` shape |
| `whoami` | a login string |

### `reviews[]` normalization (in `pr-detail`)

`reviews[{user, state: approved|changes_requested|commented, commitSha?, submittedAt, body}]` plus
`approvals{required, given, resetsOnPush, coversHead}` where **`coversHead` is tri-state: `true | false | unknown`**.

- GitHub: from `reviews` (per-review state and commit) → `true`/`false`.
- GitLab has no per-review commit and no comment-review "state". Build `approved` entries from
  `approvers`/`approval_state` (`approved_by`, rule counts) and treat discussion notes as `commented`.
  `resetsOnPush` (`true|false|unknown`) is read from the project's approval settings —
  `glab api projects/:id/approvals` → `reset_approvals_on_push` (endpoint and field from docs, not
  observed; may need Maintainer rights, so `unknown` when the call is refused; the probe checks it).
  `coversHead` is `true` **only when** `resetsOnPush` is `true` (any surviving
  approval then necessarily post-dates the current head). When that setting is off, the setting only
  says approvals persist — it cannot say whether one was submitted before or after the current head —
  so `coversHead` is **`unknown`** (also when `resetsOnPush` itself is `unknown`), never derived. `merge-pr` treats `unknown` like `false`: stop and
  ask, unless another verified source ties the approval to the head.
- `changes_requested` has no confirmed GitLab source — leave it unset rather than guess.


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
3. **Phase 1 (read-mostly, low risk):** `open-pr` (`pr-list`, `repo-view`, `pr-create`, `pr-edit`),
   `sync-main` (`pr-list`), `qa-review` (`pr-list`), `post-merge-review` (`pr-detail`, `pr-diff`,
   `pr-list`), `fix-bug` (`issue-view`).
4. **Phase 2 (mutating / fork-aware)** — verb lists come from a per-skill grep of `gh (pr|run|issue|repo|api)`
   calls; re-run it when adding a skill (`sync-main`'s `gh pr close` is a "never run" rule, not a call):
   - `commit`: `pr-view`, `pr-checkout` (fork push-remote logic), then `open-pr`.
   - `fix-ci`: `pr-view`, `pr-checkout`, `pr-checks`, `ci-runs`, `commit-checks`, `ci-logs`,
     `ci-rerun`, `ci-watch`.
   - `review-pr`: `pr-view`, `pr-checkout`, `pr-checks`, `ci-runs`, `ci-logs`, `comments-list`,
     `comment-reply`, `pr-comment`, `thread-resolve`, `whoami`.
   - `watch-pr`: `pr-view`, `pr-detail` (reviews/approvals), `repo-view`.
   - `merge-pr`: `pr-view`, `pr-detail`, `pr-checks`, `pr-list` (stacked PRs via `--base`),
     `repo-view`, `branch-protection`, `pr-merge`, `pr-update-branch`, `ci-runs`.
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
- `commit-checks`: an external commit status posted to a scratch commit (`glab api … /statuses`) appears in the mapping; also a commit with more than one page (>20) of statuses returns all pages
- `requiresMergeQueue`: a project with merge trains enabled reports `true`; one without the field reports `unknown`
- `ci-rerun`: `glab ci retry <job>` on a failed job; confirm it retries only that job
- `pr-merge`: with a **wrong** `--sha` (expect refusal + exit code), with `--auto-merge=false`
  vs default while a pipeline is running, and the delete-source flag
- `ci-watch`: `glab ci status --wait` on a failing pipeline — is the exit code non-zero?

## Open questions

- Ship `glab` support as one plugin, or a separate `webdev-gitlab` add-on plugin?
- Minimum supported `glab` version? Flags above were checked on 1.119.0; older releases used `--when-pipeline-succeeds` and lack some `mr note` subcommands (unconfirmed).
- Self-hosted GitLab: any API-version floor we should document?
- Bitbucket/Gitea: designed-for or explicitly out of scope?

# Forge adapter — design proposal

**Status:** proposal, nothing implemented. **Goal:** let the webdev skills work on GitLab (and
later others) without forking each skill, the same way `detect-stack` decoupled them from a
specific package manager.

> **Verification status.** CONTRIBUTING requires every CLI/API claim to be verified against the
> real tool. `gh` rows below reflect what the skills already use. **Every `glab` / GitLab API row
> is UNVERIFIED** — written from documentation knowledge, not run against `glab`. The first
> implementation task is to install `glab`, run each row, and fix this table.

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

1. **Forge detection.** `.claude/webdev.json` key `forge` (`"github"` | `"gitlab"`) wins. Else
   parse `git remote get-url origin`: `github.com` → github, `gitlab.com` → gitlab. A
   self-hosted host needs `forgeHost` (or an explicit `forge`). Unknown → ask, don't guess.
2. **`scripts/forge <verb> [args]`**, sibling to `resolve-command`. Prints normalized JSON.
   Skills call verbs, never `gh`/`glab` directly.
3. **Per-forge notes** live beside the skill that needs them
   (`skills/merge-pr/forges/gitlab.md`) for edge cases that don't fit a verb.
4. **Vocabulary.** Prose says "PR/MR" or "change request"; `## Output` contracts keep a stable
   field name (`pr`) regardless of forge.

## Verb table

| Verb | GitHub (`gh`) | GitLab (`glab`) — UNVERIFIED |
|---|---|---|
| `pr-view <n>` | `gh pr view --json …` | `glab mr view <n> -F json` (or `glab api projects/:id/merge_requests/:iid`) |
| `pr-create` | `gh pr create --base --title --body` | `glab mr create --target-branch --title --description` |
| `pr-checkout <n>` | `gh pr checkout` | `glab mr checkout` |
| `pr-checks <n>` | `gh pr checks --json` | `glab ci status` / MR `head_pipeline` via API |
| `pr-merge <n>` | `gh pr merge --squash --match-head-commit <sha> --delete-branch` | `glab mr merge --squash --sha <sha> --remove-source-branch` (auto-merge flag name varies by version) |
| `merged-list` | `gh pr list --state merged` | `glab mr list --merged` |
| `comments-list <n>` | `gh api --paginate …/pulls/<n>/comments` + `…/issues/<n>/comments` | `glab api --paginate projects/:id/merge_requests/:iid/discussions` |
| `comment-reply` | `gh api …/comments/<id>/replies` | POST to a discussion's `notes` |
| `thread-resolve` | GraphQL `resolveReviewThread` | `PUT …/discussions/:id?resolved=true` |
| `ci-logs <run>` | `gh run view --log-failed` | `glab ci trace <job>` / jobs API `…/trace` |
| `ci-rerun` / `ci-watch` | `gh run rerun --failed` / `gh run watch --exit-status` | `glab ci retry` / poll pipeline status |
| `issue-view <n>` | `gh issue view` | `glab issue view` |
| `whoami` | `gh api user --jq .login` | `glab api user` |

Normalized `pr-view` shape (fields skills actually read): `number, url, state, isDraft,
baseRef, headRef, headSha, isCrossRepository, mergeable, reviewState, checks[{name,state,link}]`.

## Semantic gaps (the adapter cannot paper over these)

| Area | GitHub | GitLab (UNVERIFIED) | Impact |
|---|---|---|---|
| Approval | single `reviewDecision` | rule-based approvals; `detailed_merge_status` (e.g. `not_approved`, `discussions_not_resolved`, `ci_must_pass`, `need_rebase`) | `merge-pr` gate table needs a per-forge column |
| Stale approval | approval may cover an older head | "remove approvals on new commits" is a project setting | keep the "covers current head" check; source differs |
| Merge queue | merge queue / `--auto` | merge trains, "merge when pipeline succeeds" | `merge-pr` queue branch |
| Forks | `gh pr checkout` wires push remote | MRs from forks differ in permissions and remote setup | shared fork logic in `commit`/`review-pr`/`fix-ci` must be re-verified |
| Threads | review threads (GraphQL) | discussions, per-note resolvable flag | `review-pr` resolve step |
| CI unit | workflow *run* | *pipeline* of *jobs*, stages | `fix-ci` log-reading step |
| Bots | Codex/Copilot/CodeRabbit as reviews | bots post as notes/discussions | `review-pr` "who counts as a reviewer" |

## Rollout

1. Install `glab`; verify and correct the tables above against real behavior.
2. Add `scripts/forge` + `forge`/`forgeHost` keys (update `examples/webdev.json`, README key table,
   `detect-stack` Output contract — CONTRIBUTING says these stay in sync).
3. Migrate low-risk skills first: `open-pr`, `sync-main`, `qa-review`, `post-merge-review`.
4. Then `fix-ci`, `review-pr`, `watch-pr`, `merge-pr`.
5. Fixture-based eval for `forge` (mirror `evals/detect-stack`), including a GitLab CI example.
6. Update skill descriptions so "open an MR" triggers the same skills.

## Open questions

- Ship `glab` support as one plugin, or a separate `webdev-gitlab` add-on plugin?
- Minimum supported `glab` version (flag names for auto-merge changed across releases)?
- Self-hosted GitLab: any API-version floor we should document?
- Bitbucket/Gitea: designed-for or explicitly out of scope?

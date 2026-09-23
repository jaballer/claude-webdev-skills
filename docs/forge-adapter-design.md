# Forge adapter — design proposal

**Status:** proposal, nothing implemented. **Goal:** let the webdev skills work on GitLab (and
later others) without forking each skill, the same way `detect-stack` decoupled them from a
specific package manager.

> **Verification status (glab 1.119.0, checked via `--help` on macOS).** CONTRIBUTING requires
> every CLI/API claim to be verified against the real tool. Two levels are tracked below:
> **[flags]** = the command/flag exists in `glab --help` (verified). **[live]** = actual output
> shape and behavior against a real GitLab project — **still UNVERIFIED** (no GitLab project was
> available on the authoring machine). Run `evals/forge/verify-gitlab.sh` on a machine with a
> GitLab project to close the `[live]` gaps. `gh` rows reflect what the skills already use.

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

| Verb | GitHub (`gh`) | GitLab (`glab`) | Verified |
|---|---|---|---|
| `pr-view <n>` | `gh pr view --json …` | `glab mr view <n> -F json` (`--jq` also available) | flags ✓ / live ✗ |
| `pr-create` | `gh pr create --base --title --body` | `glab mr create --target-branch --title --description` (or `--description-file`), `--draft` | flags ✓ / live ✗ |
| `pr-checkout <n>` | `gh pr checkout` | `glab mr checkout <n>` (`-b`, `-u/--set-upstream-to`) | flags ✓ / live ✗ |
| `pr-checks <n>` | `gh pr checks --json` | `glab ci get --merge-request <iid> -F json`; `glab ci status -F json` | flags ✓ / live ✗ |
| `pr-merge <n>` | `gh pr merge --squash --match-head-commit <sha> --delete-branch` | `glab mr merge <n> --squash --sha <sha> --remove-source-branch --yes` | flags ✓ / live ✗ |
| `merged-list` | `gh pr list --state merged` | `glab mr list --merged -F json` (`-s/--source-branch` filters by head) | flags ✓ / live ✗ |
| `comments-list <n>` | `gh api --paginate …/pulls/<n>/comments` + `…/issues/<n>/comments` | `glab mr note list <n>` (marked EXPERIMENTAL) or `glab mr view <n> --comments --unresolved -F json`; raw fallback `glab api --paginate projects/:id/merge_requests/:iid/discussions` | flags ✓ / live ✗ |
| `comment-reply` | `gh api …/comments/<id>/replies` | `glab mr note create <n> --reply <discussion-id> -m …` | flags ✓ / live ✗ |
| `thread-resolve` | GraphQL `resolveReviewThread` | `glab mr note resolve <discussion-id> <n>` (and `reopen`) | flags ✓ / live ✗ |
| `ci-logs <job>` | `gh run view --log-failed` | `glab ci trace <job-id\|name>` — **no `--failed` equivalent**: list failed jobs first (`glab ci get -F json` / `--status failed`), then trace each | flags ✓ / live ✗ |
| `ci-rerun` | `gh run rerun --failed` | `glab ci retry <job-id\|name>` — retries **one job**, not all failed jobs | flags ✓ / live ✗ |
| `ci-watch` | `gh run watch --exit-status` | `glab ci status --wait` (JSON output is incompatible with `--live`/`--wait`); exit-code behavior unknown | flags ✓ / live ✗ |
| `issue-view <n>` | `gh issue view` | `glab issue view <n> -F json` | flags ✓ / live ✗ |
| `whoami` | `gh api user --jq .login` | `glab api user` (no dedicated command found) | flags ✓ / live ✗ |

Corrections vs the first draft of this table: `-F/--output` is the JSON flag (not `--output json`);
`mr view --comments`, `mr note resolve|reopen|list`, and `mr create --description-file` exist, so raw
API calls are only a fallback; `ci retry` is per-job; `ci trace` has no `--failed`.

Also observed running `glab` 1.119.0 against a GitHub-remote repo (no GitLab auth): every command
exits non-zero with `none of the git remotes … point to a known GitLab host`. So `glab` only works
when a remote matches an authenticated host (or `-R`/`--hostname` is passed) — `scripts/forge` must
surface that as a clear "run `glab auth login`" message, and `forgeHost` for self-hosted instances
has to line up with what `glab auth login --hostname` registered. Also: `glab issue list -F` is
`--output-format` (`details|ids|urls`), **not** JSON — use `--jq` or `glab api` for issue lists.

Normalized `pr-view` shape (fields skills actually read): `number, url, state, isDraft,
baseRef, headRef, headSha, isCrossRepository, mergeable, reviewState, checks[{name,state,link}]`.

## Semantic gaps (the adapter cannot paper over these)

| Area | GitHub | GitLab (UNVERIFIED) | Impact |
|---|---|---|---|
| Approval | single `reviewDecision` | rule-based approvals; `detailed_merge_status` (e.g. `not_approved`, `discussions_not_resolved`, `ci_must_pass`, `need_rebase`) | `merge-pr` gate table needs a per-forge column |
| Stale approval | approval may cover an older head | "remove approvals on new commits" is a project setting | keep the "covers current head" check; source differs |
| Merge queue / auto-merge | merge queue; `gh pr merge --auto` is opt-in | merge trains; **`glab mr merge` enables auto-merge by default when a pipeline is running** (`--auto-merge=false` to merge immediately) — verified in `--help` | `merge-pr` must pass `--auto-merge=false` after its own gates, or it will queue instead of merging |
| Forks | `gh pr checkout` wires push remote | MRs from forks differ in permissions and remote setup | shared fork logic in `commit`/`review-pr`/`fix-ci` must be re-verified |
| Threads | review threads (GraphQL) | discussions, per-note resolvable flag | `review-pr` resolve step |
| CI unit | workflow *run* | *pipeline* of *jobs*, stages | `fix-ci` log-reading step |
| Bots | Codex/Copilot/CodeRabbit as reviews | bots post as notes/discussions | `review-pr` "who counts as a reviewer" |

## Rollout

1. Run `evals/forge/verify-gitlab.sh` on a machine with a GitLab project; record the JSON field names and fix the `[live]` gaps above.
2. Add `scripts/forge` + `forge`/`forgeHost` keys (update `examples/webdev.json`, README key table,
   `detect-stack` Output contract — CONTRIBUTING says these stay in sync).
3. Migrate low-risk skills first: `open-pr`, `sync-main`, `qa-review`, `post-merge-review`.
4. Then `fix-ci`, `review-pr`, `watch-pr`, `merge-pr`.
5. Fixture-based eval for `forge` (mirror `evals/detect-stack`), including a GitLab CI example.
6. Update skill descriptions so "open an MR" triggers the same skills.

## Open questions

- Ship `glab` support as one plugin, or a separate `webdev-gitlab` add-on plugin?
- Minimum supported `glab` version? Flags above were checked on 1.119.0; older releases used `--when-pipeline-succeeds` and lack some `mr note` subcommands (unconfirmed).
- Self-hosted GitLab: any API-version floor we should document?
- Bitbucket/Gitea: designed-for or explicitly out of scope?

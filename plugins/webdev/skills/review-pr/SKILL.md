---
name: review-pr
description: >
  Address and resolve GitHub pull request review comments end to end. Use whenever
  the user shares a PR URL and asks to "address comments", "fix the feedback",
  "resolve the review", "handle the bot comments", or pastes a PR URL with "fix this
  PR". Handles the full loop: read comments → verify each claim → sweep for siblings
  → fix → test → self-review → commit & push → reply inline → resolve threads → wait
  and recheck for new comments and CI status. Works with any automated reviewer (Codex, Copilot,
  CodeRabbit) and human reviewers alike.
---

# Review PR

Respond to PR review comments by making the changes, testing, committing, and replying +
resolving inline on GitHub. Resolve project commands via `/webdev:detect-stack`.

## Hard rule: commit + reply + resolve are atomic

Every commit that addresses a review comment MUST be paired with:
1. A **reply** on that comment including the new commit SHA and a one-line explanation
2. For **inline** comments: a **resolution** of the review thread (`resolveReviewThread`
   GraphQL mutation). General (PR-level) comments have no thread to resolve — a reply alone
   closes them. Rebuttal threads stay open for the reviewer (Step 11).

If the repo enforces "all conversations resolved" branch protection, an un-replied/un-resolved
fix leaves the PR un-mergeable. Even when it doesn't, resolving keeps the thread tidy. **Don't
declare this skill complete until every addressed comment has a reply, and every addressed
inline comment's thread is resolved (rebuttals excepted).** "Pushed but not replied" and
"replied but not resolved" are half-done states.

## Step 1: Parse the PR URL
Extract `owner`, `repo`, `pr_number`. Sources in priority order: (1) explicit paste, (2) chained
from `/webdev:open-pr`, (3) inferred from the current branch via `gh pr view --json url -q .url`.
If none resolves, ask.

## Step 2: Get onto the PR branch, up to date
```bash
git branch --show-current
```
If it doesn't match the PR head ref: `gh pr checkout <pr_number> --repo <owner>/<repo>`.
If it does match, still sync: `git fetch origin && git status -sb`, then `git pull --ff-only`.
If `--ff-only` refuses, stop and surface it — don't auto-rebase.
**Fork PRs:** if `gh pr view --json isCrossRepository` is true, pushes go to the contributor's
fork — `gh pr checkout` configures that automatically, but it only works with fork access or
maintainer-edit permission. Lacking either, stop and report; never push the fix to upstream.

## Step 3: Fetch all comments + build a tracking list
```bash
gh api --paginate repos/<owner>/<repo>/pulls/<pr_number>/comments   # inline (line-level)
gh api --paginate repos/<owner>/<repo>/issues/<pr_number>/comments  # general (PR-level)
```
`--paginate` is load-bearing: `gh api` returns 30 items per page, and a big bot review easily
exceeds that — an unpaginated fetch silently drops every comment past page 1 from the tracking
list.
For each, note `id`, `path`, `line`, `body`, `diff_hunk`. **Build a tracking list of every comment
ID you intend to address** — you iterate this exact list in Step 10 (reply) and Step 11 (resolve).
Nothing comes off it until both are posted. Skip purely informational comments (bot intros, reactions).

## Step 4: Verify each claim before fixing
Reviewers — especially automated ones — sometimes flag non-issues. **Read the code at the cited
path/line and confirm the claim before fixing.** Categorize each: *valid+fix* · *valid+different
fix* (reply with your alternative) · *invalid+rebut* (reply citing the code) · *ambiguous* (ask).
Don't reflexively accept — applying a reviewer's wrong fix uncritically is worse than an open thread.

## Step 5: Sweep for siblings
When a comment identifies a real issue, **grep for the same pattern before fixing only the cited
site.** Reviewers point at one example; the mistake usually repeats. Catching siblings in the same
commit is far cheaper than getting flagged for each on a follow-up round.

## Step 6: Fix each issue
Use `path`/`line`/`diff_hunk` to locate the code, understand surrounding context, apply the fix (or
your alternative), and apply it to every sibling from Step 5. **Keep fixes consistent with the
codebase's conventions** (read `CLAUDE.md` if present). Work through all fixes before testing.

## Step 7: Run tests
**Invoke `/webdev:run-tests`** scoped to the fix's blast radius (full only if it touched shared code
or a targeted run surprised you). A docs-only fix needs no run. Don't commit broken code.
**Run the resolved formatter/linter on the changed files too** — this path commits directly
(Step 9) without `/webdev:commit`'s step 3, and unformatted review fixes get re-flagged by
CI/bots on the next round, burning the recheck budget. **If the formatter modified any file,
re-run the scoped tests** — the formatted diff is what gets committed, and it's no longer the one
you just tested. If there were frontend changes, note the user may need to run the dev/build
command to see them.

## Step 8: Pre-push self-review
Read the full diff cold (`git diff`). For small fixes, check: new contradictions introduced by the
fix? stale references / "see step N" pointers? examples that no longer match the changed rule? did
the sweep go wide enough (re-grep the original anti-pattern AND any new pattern introduced)?

**For non-trivial fix commits** (>~5 lines, >1 file, introducing a flag/config key/rule/enum/route, touching
renames/deletions, or handling user input or queries — the same trivial-diff boundary as
`/webdev:commit` step 4), the bullets aren't enough — apply the full hostile read from
**`/webdev:commit` step 4** (4a rules 1–9, the 4b web-security checklist, 4c project bug-classes,
and 4d). Most review back-and-forth is bugs introduced *by the fixes themselves*; this pass is
worth it on every push.

## Step 9: Commit and push
Stage only changed files. Message:
```
fix(pr-<number>): address review comments

- <brief description of each fix>
```
Then push. For a same-repo PR, plain `git push` works — git uses the upstream `gh pr checkout`
configured. But for a **fork PR whose local branch name differs from the PR's head branch** (a PR
opened from the fork's `main`/`master`, or a checkout renamed to avoid a local collision), a
no-argument push fails under Git's default `push.default=simple` — it requires the upstream to
share the current branch's name. Push an explicit refspec to the PR head instead: get the head
branch from `gh pr view <number> --json headRefName -q .headRefName`, and the remote that
`gh pr checkout` configured from `git config branch.<local>.pushRemote` (falling back to `.remote`):
```bash
git push <pushRemote> HEAD:<headRefName>
```
(Honor `coAuthorTrailer` in `.claude/webdev.json` as in `/webdev:commit`.)

## Step 10: Reply to each comment
Inline reply:
```bash
gh api repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies \
  --method POST --field body="<reply>"
```
General reply: `gh api repos/<owner>/<repo>/issues/<pr_number>/comments --method POST --field body="..."`.
Keep replies concise and **always reference the commit SHA**. Templates:
- Fixed: `Confirmed and fixed in `<sha>`. <one-sentence summary>.`
- Different approach: `Confirmed the issue. Took a different approach in `<sha>`: <reason>.`
- Disagree (no change): `Looked at this — I think the current code is correct: <reason citing code>. Happy to revisit.`

**Verification:** iterate the Step 3 tracking list and confirm a reply exists for each addressed
comment before proceeding. Don't move on with the list un-closed.

## Step 11: Resolve the threads
Replying alone doesn't resolve. Fetch thread node IDs (distinct from comment IDs) — pull ALL
comments per thread, since the actionable comment may be a follow-up reply, not the root:
```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!,$after:String){
    repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
      reviewThreads(first:100, after:$after){
        pageInfo{ hasNextPage endCursor }
        nodes{ id isResolved comments(first:100){ nodes{ databaseId } } } } } } }' \
  -f owner=<owner> -f repo=<repo> -F pr=<pr_number>
```
`reviewThreads` caps at 100 per page (GraphQL connections can't exceed it). Step 3's paginated
REST fetch can track comment IDs whose thread lives past page 1, and those never resolve if you
stop here — so **if `pageInfo.hasNextPage` is true, repeat with `-f after=<endCursor>` and
concatenate the `nodes` before matching.** (`comments(first:100)` per thread is enough — a single
thread rarely exceeds 100 replies.)
For each tracked comment ID, find the thread whose `comments.nodes[].databaseId` **contains** it
(not just `[0]`). For each matched thread with `isResolved:false`:
```bash
gh api graphql -f query='
  mutation($threadId:ID!){ resolveReviewThread(input:{threadId:$threadId}){ thread{ isResolved } } }' \
  -f threadId=<thread_node_id>
```
**Skip resolution** for rebuttal threads where the reviewer should make the call — leave those open.
**Verification:** re-run the threads query; confirm every addressed thread (excluding rebuttals) is
now `isResolved:true`.

## Step 12: Wait and recheck — new comments AND CI status
Automated reviewers typically react to the new commit in ~2–3 min — often flagging issues the fixes
themselves introduced. **Default: recheck once before declaring done.**
1. Capture the push time: `git log -1 --format=%cI HEAD`
2. Wait ~3 min via `ScheduleWakeup` (`delaySeconds: 180`, prompt re-entering this skill at
   Step 12) when that tool exists in the environment. Where it doesn't (stock Claude Code
   installs), one bounded `sleep 180` — or `gh pr checks <pr> --watch` when checks are also
   pending — is the acceptable fallback; don't loop sleeps.
3. Re-fetch comments, filtered to those created *after* the push AND **not authored by you** (your
   Step 10 replies will trip the timestamp filter otherwise):
   ```bash
   ME=$(gh api user --jq .login)
   # BSD/macOS date shown; on GNU date use: PUSH_TS=$(date -u -d "$(git log -1 --format=%cI HEAD)" +"%Y-%m-%dT%H:%M:%SZ")
   PUSH_TS=$(date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$(git log -1 --format=%cI HEAD | sed 's/:\(..\)$/\1/')" +"%Y-%m-%dT%H:%M:%SZ")
   gh api --paginate repos/<owner>/<repo>/pulls/<pr_number>/comments \
     | jq --arg me "$ME" --arg ts "$PUSH_TS" '[.[]|select((.created_at|fromdateiso8601) > ($ts|fromdateiso8601) and .user.login != $me)]|length'
   ```
   **Pipe through real `jq`** (`gh api --jq` doesn't accept `--arg`). **Compare as numbers via
   `fromdateiso8601`** — `%cI` is local-with-offset, GitHub's `created_at` is UTC-Z; a string compare
   mis-orders them.
4. **Check CI on the same pass** — review comments aren't the only thing that stalls a PR:
   ```bash
   gh pr checks <pr_number> --repo <owner>/<repo>
   ```
   A **failing check** on the head SHA: read the failure and classify — *caused by these commits*
   → treat it as a finding and loop back like a comment; *pre-existing on base or a known flake*
   → don't chase it, report it separately for the user. Getting at the logs depends on the check
   type: for a **GitHub Actions** check, resolve the run id from the check's `link` field
   (`gh pr checks --json name,state,link` — the `/actions/runs/<id>/` segment) or
   `gh run list --commit $(git rev-parse HEAD)`, then `gh run view <run_id> --log-failed`; for an
   **external/status check** (no Actions run exists), follow the check's `link` to the provider
   instead — `gh run view` can't read those. For anything beyond a quick fix, **invoke
   `/webdev:fix-ci`** — it owns the full triage loop (first-real-error, local repro, CI-vs-local
   divergences).
   **Pending checks** → note them; they gate the merge-readiness verdict below.
5. **New comments or a caused-by-us failing check** → loop back to Step 4 with the same
   verify→sweep→fix→self-review→push→reply discipline. **Zero new and checks green** → done.

**Iteration cap: at most 2 rechecks** (≤3 commits in a row from this skill). If a reviewer is still
surfacing findings after 3 commits, summarize the remaining comments for human triage instead of
auto-pushing a 4th.

**Merge-readiness — silence ≠ approval.** The final report distinguishes three states:
- `merge-ready` — a reviewer posted an explicit positive signal on the latest SHA **and** checks are green
- `under-review` — no reviewer signal yet, or checks still pending (NOT approval; the user waits or checks)
- `findings-open` — new findings or a caused-by-us failing check (handled by the loop-back)

Never report "ready to merge" from absence of new comments alone. **Skip the recheck** if the user
said "ship and move on" or the change is trivial.

## Agent Delegation
If comments span 3+ unrelated files, analyze/fix each file group in a separate sub-agent. Fixes
complete before tests; self-review before commit; tests pass before commit.

## Output
- **PR**: `owner/repo#number` · **Comments addressed**: count (across iterations)
- **Commit SHA(s)** · **Test result** · **Replies posted** (must equal comments addressed)
- **Threads resolved**: count (excludes rebuttals left open) · **Rechecks**: 0/1/2
- **Checks on last SHA**: green / pending / failing (+ pre-existing/flaky notes)
- **Reviewer status on last SHA**: `merge-ready` / `under-review` / `findings-open`

---
name: merge-pr
description: >
  Merges a pull request the safe way — verify approvals, green checks, and resolved
  threads first, pick the repo's merge method, merge, then clean up via sync-main.
  Use when the user says "merge it", "merge the PR", "land it", "squash and merge",
  "it's approved — merge", or after /webdev:review-pr reports merge-ready. This skill
  MERGES; to address review comments use /webdev:review-pr, to fix a red check use
  /webdev:fix-ci. Never merges on its own initiative — merging is often a deploy.
---

# Merge PR

The last step of the loop: branch → … → review → **merge** → sync. Merging to the default
branch frequently triggers CI/CD or a production deploy, so this skill verifies readiness
rather than assuming it, and treats the merge itself as an outward-facing action.

## Step 1: Identify the PR

Explicit number/URL if given; otherwise the current branch's PR via
`gh pr view --json number,url`. If neither resolves, ask.

## Step 2: The pre-merge gate — verify, don't assume

```bash
gh pr view <number> --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,title,headRefOid
```

**Record `headRefOid`** — that SHA is what these gates certify, and Step 4 pins the merge to it.

Walk every gate; each has a defined stop:

| Gate | Pass | On failure |
|---|---|---|
| State | `OPEN`, not a draft | Draft → stop; ask if it should be marked ready first |
| Checks (`statusCheckRollup`) | all green | Failing → stop, **invoke `/webdev:fix-ci`**. Pending → wait (`gh pr checks --watch` or a `ScheduleWakeup` recheck), don't merge ahead of CI |
| Review (`reviewDecision`) | `APPROVED` **and the approval covers the current head** — `reviewDecision` alone can be an approval of an older diff when the repo doesn't dismiss stale reviews. Verify: `gh api graphql` for `reviews(states: APPROVED, last: 10) { nodes { commit { oid } submittedAt } }` and confirm the newest approval's `commit.oid` equals `headRefOid` (or every commit after it is from the approver). Or the repo requires no review | `CHANGES_REQUESTED` → stop, **invoke `/webdev:review-pr`**. `REVIEW_REQUIRED` → stop; a required review can't be merged around. **Approval predates the head** → report "approved, but not on the latest commits" — the user decides (re-request review, or explicitly proceed) |
| Threads | no unresolved review threads (the reviewThreads GraphQL query in `/webdev:review-pr` step 11 — **paginate**: `reviewThreads(first:100)` caps at 100 per request, so on big PRs follow `pageInfo { hasNextPage endCursor }` until exhausted; an unresolved thread on page 2 is still a gate) | List the open threads; offer `/webdev:review-pr` |
| Up to date (`mergeStateStatus`) | `CLEAN`, or `HAS_HOOKS` (GitHub Enterprise pre-receive hooks — mergeable with passing status; treat as pass). `UNKNOWN` → GitHub computes this async: re-query after a few seconds rather than failing the gate | `BEHIND` → update the branch (`gh pr update-branch`, or rebase if that's the repo's convention) — **this creates a new head: re-run the ENTIRE gate table against it**, not just checks. The update can invalidate approvals (stale-review dismissal) and changes `headRefOid`, so re-fetch reviewDecision, threads, and the new SHA before merging. `DIRTY` → conflicts; resolve on the branch locally (merge base in, resolve, test, push), never through the web editor blindly |

**No repo-required review + no reviewer signal** — the gate table can pass on a repo with no
branch protection. State that plainly ("merging unreviewed — the repo doesn't require review")
rather than implying approval existed. Silence ≠ approval here too; the user decides.

Never use `--admin` to bypass a failing gate unless the user explicitly directs it, understanding
what's being overridden.

## Step 3: Pick the merge method

Always fetch what the repo allows first:
`gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed`. Then:
1. `"mergeMethod"` in `.claude/webdev.json` (`"squash"` | `"merge"` | `"rebase"`) — authoritative,
   **but validate it against the allowed methods**: a stale/copied pin the repo forbids stops
   here with the mismatch ("webdev.json pins rebase; repo allows squash only"), before any
   confirmation — not as a `gh pr merge` failure after it.
2. Otherwise, what the repo allows and actually uses: the allowed flags above, plus a couple of recent merged PRs / `git log <base>` for which shape the history has (squashed single commits vs merge commits).
3. Only one method allowed → use it. Genuinely ambiguous → ask once. **Offer to pin the answer in `webdev.json` AFTER Step 5** — editing the file now would either dirty the tree or, if committed to the PR branch, change the head and invalidate Step 2's certified `headRefOid`.

For a squash, the squash-commit title should be the PR title (already conventional-commits
shaped per `/webdev:open-pr`) — pass `--subject` explicitly if `gh`'s default would differ.

## Step 4: Confirm, then merge

Merging is hard to undo (a revert commit is a new change, not an undo) and often deploys.
**If the user's request named this PR ("merge #12", "land it") that IS the confirmation — don't
re-ask.** If this skill was reached any other way (chained, inferred, "what's next?"), show
`title · #number · method · base` and get a yes first.

```bash
gh pr merge <number> --squash --delete-branch --match-head-commit <headRefOid>   # or --merge / --rebase
```

**`--match-head-commit` pins the merge to the SHA the gates certified** (from Step 2, re-fetched
after any branch update). If someone pushed to the PR between the gate check and this command,
the merge is refused instead of landing unverified code — on refusal, go back to Step 2 for the
new head.

**Merge-queue repos:** when the base branch requires a merge queue, the queue owns the merge
method — don't pass `--squash`/`--merge`/`--rebase`; `gh pr merge <number>` adds the PR to the
queue instead of merging immediately. Expect `state` to stay `OPEN` while queued: verify by
watching for `MERGED` (or a queue rejection) rather than assuming, and report "queued" honestly
if it hasn't landed yet.

`--delete-branch` removes the remote branch and switches the local checkout back to base. If
the local deletion part fails (dirty tree, checked-out elsewhere), the merge itself is done —
`/webdev:sync-main` in Step 6 cleans up the rest; don't retry the merge.

## Step 5: Verify the outcome

```bash
gh pr view <number> --json state,mergedAt,mergeCommit
```
Confirm `MERGED` + capture the merge/squash SHA. Note any issues auto-closed by `Closes #N`.
Then check whether **this merge** kicked off base-branch workflows (deploys) — filter to the
merge commit, not just the branch, or an older red run on a busy base gets misattributed to
this merge:
```bash
gh run list --branch <base> --commit <merge-sha> --limit 5
```
If a deploy/CI run started, report it (and its status if quickly available) — **a red run
triggered by this merge goes to `/webdev:fix-ci`**, on a fresh branch. Don't declare the loop
closed while a just-triggered deploy is visibly failing — and don't chase base failures that
predate the merge; report those separately.

## Step 6: Clean up

**Invoke `/webdev:sync-main`** — pull the merged base, prune remote refs, and (with
confirmation) delete the merged local branch if `--delete-branch` didn't already.

## What NOT to do

- Don't merge a PR the user didn't ask to merge — being merge-ready is a fact to report, not
  an instruction to act on.
- Don't bypass failing gates with `--admin`, re-request-review tricks, or force-pushes.
- Don't merge with pending checks "because they'll probably pass".
- Don't resolve other people's review threads just to clear the gate — that's the reviewer's call.

## Output

- **PR**: `owner/repo#number` — title · **Method**: squash / merge / rebase
- **Gates**: each pass/fail as checked (checks · review · threads · up-to-date)
- **Merge SHA** · **Branches deleted**: remote / local / neither
- **Issues closed**: list or none · **Post-merge runs on base**: none / started (status)
- **Cleanup**: sync-main result (or "skipped — why")

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
gh pr view <number> --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,title
```

Walk every gate; each has a defined stop:

| Gate | Pass | On failure |
|---|---|---|
| State | `OPEN`, not a draft | Draft → stop; ask if it should be marked ready first |
| Checks (`statusCheckRollup`) | all green | Failing → stop, **invoke `/webdev:fix-ci`**. Pending → wait (`gh pr checks --watch` or a `ScheduleWakeup` recheck), don't merge ahead of CI |
| Review (`reviewDecision`) | `APPROVED`, or the repo requires no review | `CHANGES_REQUESTED` → stop, **invoke `/webdev:review-pr`**. `REVIEW_REQUIRED` → stop; a required review can't be merged around |
| Threads | no unresolved review threads (count via the reviewThreads GraphQL query in `/webdev:review-pr` step 11) | List the open threads; offer `/webdev:review-pr` |
| Up to date (`mergeStateStatus`) | `CLEAN` | `BEHIND` → update the branch (`gh pr update-branch`, or rebase if that's the repo's convention) and **wait for checks to re-run on the new head** — green on a stale base proves nothing. `DIRTY` → conflicts; resolve on the branch locally (merge base in, resolve, test, push), never through the web editor blindly |

**No repo-required review + no reviewer signal** — the gate table can pass on a repo with no
branch protection. State that plainly ("merging unreviewed — the repo doesn't require review")
rather than implying approval existed. Silence ≠ approval here too; the user decides.

Never use `--admin` to bypass a failing gate unless the user explicitly directs it, understanding
what's being overridden.

## Step 3: Pick the merge method

Resolution order:
1. `"mergeMethod"` in `.claude/webdev.json` (`"squash"` | `"merge"` | `"rebase"`) — authoritative.
2. What the repo allows and actually uses: `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed`, and check a couple of recent merged PRs / `git log <base>` to see which shape the history has (squashed single commits vs merge commits).
3. Only one method allowed → use it. Genuinely ambiguous → ask once, then offer to pin the answer in `webdev.json`.

For a squash, the squash-commit title should be the PR title (already conventional-commits
shaped per `/webdev:open-pr`) — pass `--subject` explicitly if `gh`'s default would differ.

## Step 4: Confirm, then merge

Merging is hard to undo (a revert commit is a new change, not an undo) and often deploys.
**If the user's request named this PR ("merge #12", "land it") that IS the confirmation — don't
re-ask.** If this skill was reached any other way (chained, inferred, "what's next?"), show
`title · #number · method · base` and get a yes first.

```bash
gh pr merge <number> --squash --delete-branch   # or --merge / --rebase
```

`--delete-branch` removes the remote branch and switches the local checkout back to base. If
the local deletion part fails (dirty tree, checked-out elsewhere), the merge itself is done —
`/webdev:sync-main` in Step 6 cleans up the rest; don't retry the merge.

## Step 5: Verify the outcome

```bash
gh pr view <number> --json state,mergedAt,mergeCommit
```
Confirm `MERGED` + capture the merge/squash SHA. Note any issues auto-closed by `Closes #N`.
Then check whether the merge kicked off base-branch workflows (deploys):
```bash
gh run list --branch <base> --limit 3
```
If a deploy/CI run started, report it (and its status if quickly available) — **a red deploy
run goes to `/webdev:fix-ci`**, on a fresh branch. Don't declare the loop closed while a
just-triggered deploy is visibly failing.

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

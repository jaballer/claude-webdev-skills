---
name: sync-main
description: >
  Returns the local repo to a verifiably clean state on the latest default branch
  before starting the next task. Use after a PR is merged and deployed, when
  switching context between tasks, or any time you want to confirm the base is up
  to date and stale local branches are cleaned up. Trigger phrases: "sync main",
  "clean up", "back to main", "fresh start", "start the next thing", "we just
  deployed", "PR is merged what's next". This skill does NOT create a branch —
  chain to /webdev:new-branch when ready to start work.
---

# Sync Main

Get back to a known-good baseline on the default branch so the next task starts clean.
Resolve the default branch the same way `/webdev:new-branch` does (`.claude/webdev.json`
`"defaultBranch"` first — a pin beats detection — then origin/HEAD, falling back to
`main`/`master`). Call it `<base>`.

## When NOT to use

- **Mid-task on an active feature branch** — this skill switches to `<base>` and may delete
  the current branch if its PR is merged. Finish or stash work first.
- **As a substitute for `/webdev:new-branch`** — this skill never creates a branch.

## Steps

1. **Check working tree state**
   ```bash
   git status --short
   ```
   If non-empty (uncommitted, staged, or untracked), surface what's there and ask before
   continuing. Do not silently stash or discard.

2. **Note the starting branch and verify its PR status**
   ```bash
   git branch --show-current
   ```
   - On `<base>`: skip to step 3.
   - On any other branch: check whether its PR is merged before considering it safe to delete:
     ```bash
     gh pr list --state merged --head <branch-name> --json number,mergedAt,title --limit 1
     ```
     If unmerged or no PR exists, treat the branch as **active work** — switch to `<base>` for
     the sync but do **not** propose deleting it.

3. **Switch to base and fetch with prune**
   ```bash
   git checkout <base>
   git fetch --prune
   ```
   `--prune` removes remote-tracking refs for branches deleted on the remote after merge.

4. **Pull latest base (fast-forward only)**
   ```bash
   git pull --ff-only
   ```
   If the pull refuses to fast-forward, stop and surface it — the base should never have local
   commits ahead of origin. Plain `git pull` would silently merge, defeating the purpose.

5. **Identify safe-to-delete merged local branches**
   ```bash
   git branch --merged <base>
   ```
   `--merged` only checks reachability — a tip can be in the base's history without its PR ever
   being merged (cherry-picks, manual rebases, never-PR'd branches). Reachability is necessary
   but not sufficient. For each candidate, verify a merged PR exists:
   ```bash
   gh pr list --state merged --head <branch-name> --json number,mergedAt --limit 1
   ```
   - **Branch + verified merged PR** → safe to propose for deletion.
   - **Branch with no merged PR** → leave alone; surface separately as "base-reachable tip but
     unverified PR status — not proposing deletion."

   Filter out `<base>` itself unconditionally.

6. **Confirm before deleting**
   List stale branches with short context (last commit subject + age) and ask for confirmation
   **before** deleting. Default to a single confirm-all prompt.
   ```bash
   git branch -d <branch-name>
   ```
   Use `-d` (safe), never `-D`. If `-d` refuses, the branch isn't actually merged — surface it.

   **Squash-merge exception:** GitHub's squash-merge default produces branches whose tip is NOT
   reachable from base even after merge, so `--merged` won't list them and `-d` refuses
   ("not fully merged"). When `gh pr list --state merged --head <branch>` returns a merged PR
   but `-d` refuses, verify the SHA before offering `-D` (`--head` matches by branch *name*
   only, so a reused name could match an unrelated older merged PR):
   ```bash
   pr_head_oid=$(gh pr list --state merged --head <branch> --json headRefOid --limit 1 | jq -r '.[0].headRefOid')
   branch_tip=$(git rev-parse <branch>)
   # tips match  → squash-merged, tip unchanged; force-delete recoverable from reflog
   # tips differ → branch has commits the PR doesn't include; treat as active work, don't delete
   ```
   Only `-D` on explicit user confirmation AND a verified SHA match.

7. **Report final state** — see Output.

## Important Rules

- **Never auto-delete branches** — always confirm.
- **Never use `git branch -D`** unless the user explicitly requests force-delete with a reason.
- **Never stash or discard uncommitted work** automatically.
- **Never `git reset --hard` the base.** If `git pull --ff-only` refuses, the user investigates.
- **Never run destructive remote operations** (`gh pr close`, `git push --delete`). Local cleanup only.

## Output

When complete, report back:
- **Starting branch** · **Current branch** (should be `<base>`) · **Base SHA** (short)
- **Pulled**: commits fast-forwarded, or "already up to date"
- **Local branches deleted**: list, or "none"
- **Remote refs pruned**: count
- **Status**: `clean` or `warnings` with details
- **Next**: one-line nudge — e.g. "Ready for `/webdev:new-branch` when you have the next task."

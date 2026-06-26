---
name: safe-edit
description: >
  Guardrails for risky operations — classify blast radius and reversibility, then
  confirm, back up, or proceed accordingly. Use before anything destructive or hard to
  undo: force-pushing, deleting files or branches, dropping/resetting a database, running
  migrations, bulk find-and-replace, rewriting git history, or editing generated/vendored
  files. Trigger when the user says "is this safe?", "be careful here", "don't break
  anything", or when you (Claude) are about to run an irreversible command. Especially
  useful for people new to git and the shell.
---

# Safe Edit

A pre-flight check for operations that can lose work or break things. The goal isn't to slow
everything down — it's to spend caution where it's actually warranted and move freely where it
isn't. Reversible, low-blast-radius work needs no ceremony; irreversible or wide-blast-radius work
gets a confirm and, when appropriate, a backup.

## Step 1: Classify the operation

Score the pending operation on two axes:

**Reversibility** — if this goes wrong, can it be undone?
- *Reversible* — a normal edit (git tracks it), a new commit, a new branch.
- *Recoverable-with-effort* — a deleted local branch (reflog), a force-push (remote reflog, briefly).
- *Irreversible* — `rm` of an untracked file, dropping a database, deleting remote data, truncating a table, overwriting a file you never read.

**Blast radius** — how much does it touch?
- *Narrow* — one file you're actively working on.
- *Wide* — many files, a shared branch, the default branch, production data, anything other people depend on.

## Step 2: Act on the classification

| Reversibility × Blast | What to do |
|---|---|
| Reversible · narrow | **Proceed.** No confirmation needed — this is normal work. |
| Reversible · wide | Proceed, but **state what you're about to touch** so the user can object. |
| Recoverable · any | **Confirm first**, and name the recovery path ("recoverable from reflog if needed"). |
| Irreversible · narrow | **Confirm first.** Show exactly what will be lost. |
| Irreversible · wide | **Stop. Confirm explicitly, and back up first** (see Step 3). Never do this on your own initiative. |

When unsure which bucket something is in, treat it as the more dangerous one.

## Step 3: Back up before irreversible-wide operations

Before a destructive operation you can't undo, create a cheap escape hatch and tell the user it exists:
- **Code**: commit or stash current work first (`git stash` / a WIP commit) so the tree is recoverable.
- **A branch about to be force-updated**: note its current SHA, or push a backup ref.
- **Data**: a dump/export, or a copy of the file (`cp file file.bak`), before the mutation.
A 5-second backup turns an irreversible operation into a recoverable one.

## The common footguns (for newer devs)

These are the operations that most often lose work — treat each as confirm-first by default:

- `git push --force` / `--force-with-lease` to a **shared** branch — can erase others' commits. Prefer
  `--force-with-lease`, and never force-push the default branch.
- `git reset --hard` / `git checkout -- .` — silently discards uncommitted work. Stash first.
- `git clean -fd` — deletes untracked files permanently (no git history to recover from).
- Deleting a branch with `-D` — skips the merged-check. Confirm it's merged or backed up.
- `rm -rf` — irreversible and only as precise as the path. Read the path twice; never run with a variable that could be empty.
- **Dropping/resetting a database, running a down-migration, truncating a table** — in dev maybe fine, in prod catastrophic. Confirm which environment, back up first.
- **Committing secrets** — `.env`, keys, tokens. If one is already staged, stop; if already pushed, it must be rotated, not just removed.
- **Editing a migration that has already run**, or generated/vendored files (`dist/`, `node_modules/`, `vendor/`) — changes get overwritten or desync state. Edit the source, re-generate.

## Important rules

- **Read before you overwrite or delete.** If a file's contents contradict how it was described to
  you, or you didn't create it, surface that instead of proceeding.
- **Never disable safety to make an error go away** — not `--no-verify`, not `--force` to dodge a
  rejected push, not deleting a test to make the suite green. Fix the cause.
- **Match confirmation to risk, not to anxiety.** Don't ask permission for every ordinary edit; do
  stop hard before anything irreversible-and-wide.

## Output

When invoked on a specific pending operation, report:
- **Operation** · **Reversibility** · **Blast radius** · **Verdict**: proceed / confirm-first / back-up-then-confirm / don't
- **Backup taken** (if any): what and where
- **Recovery path**: how to undo it if it goes wrong

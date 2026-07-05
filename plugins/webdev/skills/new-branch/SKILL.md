---
name: new-branch
description: >
  Creates a properly-named git branch before starting any new work. Use at the
  start of every coding session, feature, bug fix, or task. Trigger whenever the
  user mentions starting something new, working on an issue, fixing a bug, or any
  time work is about to begin and no feature branch exists yet. If the user jumps
  straight into changes without a branch, pause and run this first. Phrases like
  "let's work on X", "can you fix Y", "start on issue #Z", or "I want to add A"
  are all signals to run this skill.
---

# New Branch

Before any code changes, ensure work happens on a clean, properly-named branch off the
up-to-date default branch.

## Steps

1. **Resolve the default branch** (don't assume `main`)
   ```bash
   git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'
   ```
   Falls back to `main` then `master` if origin/HEAD isn't set. A project can pin
   `"defaultBranch"` in `.claude/webdev.json` to override. Call the result `<base>` below.

2. **Check the current branch**
   ```bash
   git branch --show-current
   ```
   If already on a non-`<base>` branch, confirm with the user before proceeding — they may
   want a fresh branch anyway, or may be mid-task on existing work.

3. **Switch to base and pull latest (fast-forward only)**

   First check for uncommitted work — don't switch branches over a dirty tree silently:
   ```bash
   git status --short
   ```
   If non-empty, say what's there and ask: **carry it onto the new branch** (fine when the
   work-in-progress belongs to the new task — git carries it through the checkouts unless files
   conflict), or **stash first** (`git stash push -u`, pop after branching — the `-u` matters:
   plain `git stash push` leaves untracked `??` files in the tree, so they'd still block the
   checkout or ride along despite the stash). Never stash or discard without asking.

   ```bash
   git checkout <base> && git pull --ff-only
   ```
   Always branch from an up-to-date base. Never branch from another working branch.
   `--ff-only` aborts instead of silently creating a merge commit if the base has diverged
   from origin; if it refuses, stop and surface the divergence — the base should never be in
   that state.

   > If you just merged a PR, are coming off a stale local branch, or are unsure the base is
   > clean, **invoke `/webdev:sync-main` first** — it pulls latest, prunes remote-tracking
   > refs, and (with confirmation) deletes merged local branches.

4. **Determine the branch prefix from the work type**

   Match the prefix to the eventual commit type (conventional-commits practice). Default set
   below; a project may override via `"branchPrefixes"` in `.claude/webdev.json`.

   | Prefix | When to use |
   |---|---|
   | `feature/` | New functionality, user-facing capabilities, new endpoints/pages/integrations |
   | `fix/` | Bug fixes, regressions, broken behavior |
   | `refactor/` | Code restructure with no behavior change (renames, moves, extractions) |
   | `docs/` | Documentation-only changes |
   | `chore/` | Tooling, dependencies, config, CI, generated files |
   | `review/` | Standalone review or QA passes (e.g. `review/qa-auth-flow`) |

   When torn between `feature/` and `fix/`: new user-observable behavior → `feature/`; making
   existing behavior correct → `fix/`.

5. **Determine the branch name**
   - With a known issue number: `<prefix>/<issue-number>-<short-description>`
   - Without: `<prefix>/<short-description>`
   - Lowercase, hyphens only, under 50 characters
   - Examples: `feature/208-user-avatar-upload`, `fix/registration-redirect-loop`,
     `refactor/extract-url-helper`, `chore/upgrade-vite-5`

6. **Create and switch to the branch**
   ```bash
   git checkout -b <full-branch-name>
   ```

7. **Confirm to the user** — state the branch name and that it's ready, then proceed.

## Important Rules

- **Never commit directly to the default branch** — open a PR. Merges may trigger CI/CD or a
  production deploy, so the base must stay releasable.
- **Always pull latest base first** — avoids conflicts and starts from current state.
- **One branch per issue or feature** — don't stack unrelated changes on one branch.
- **Branch prefix should match the eventual commit prefix** — a `feature/foo` branch whose
  commit starts with `fix:` is a smell; pick the right prefix up front.

## Output

When complete, report back:
- **Branch name**: the full branch name created
- **Base**: the base branch and short SHA branched from
- **Status**: `ready` or `error` with details

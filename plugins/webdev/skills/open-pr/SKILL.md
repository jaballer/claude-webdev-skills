---
name: open-pr
description: >
  Opens a GitHub pull request with a structured, reviewable body. Use whenever the
  user says "open a PR", "create the PR", "push and open a PR", "ship it", or any
  time work is committed and pushed to a working branch but the PR isn't open yet.
  Also invoked automatically as the final step of /webdev:commit after a successful
  push. Produces a PR description in a four-section shape (Summary / Decisions baked
  in / Test plan / Follow-ups) with checkbox-formatted verification steps.
---

# Open PR

Opens a pull request with a body that's actually scannable in review. The point of the
structure isn't to fill a template — it's to give a reviewer enough context to evaluate the
change without re-deriving the design decisions or guessing what was tested.

## Prerequisites

- On a non-default working branch (confirm with `git branch --show-current`)
- The branch is pushed to origin (`git status` says "up to date with 'origin/<branch>'")
- Tests passed locally at the appropriate scope (see `/webdev:run-tests`); CI runs the full
  suite on the PR
- **User-facing change? Verification evidence exists** — `/webdev:verify` results for this diff
  (typically from `/webdev:commit` step 3½). If none exist and you can't run verify now, the
  Manual line must say so explicitly — "not verified in the running app; needs human QA" plus
  the manual script — never a silently absent or vaguely-checked Manual line.

If any aren't true, stop and resolve them first. Don't open a PR for unpushed code.

## Step 1: Gather context (run in parallel — independent)

```bash
git log <base>..HEAD --oneline          # what changed (resolve <base> as in /webdev:new-branch)
git diff <base>...HEAD --stat
gh pr list --state all --limit 5         # recent PRs for title-style reference
gh repo view --json nameWithOwner -q .nameWithOwner   # owner/repo, if you need it explicitly
```

Look for an issue number in the branch name (`feature/388-...` → `388`) or commit messages.
Confirm with the user if ambiguous.

## Step 2: Compose the PR title

Match the conventional-commits-style format used in recent merges:

```
<type>(<scope>): <short imperative description> (#<issue-number>)
```

- **Type** maps from the branch prefix: `feature/`→`feat`, `fix/`→`fix`, `refactor/`→`refactor`,
  `docs/`→`docs`, `chore/`→`chore`, `review/`→`chore` (unless dominantly one category).
- **Scope** is the area touched (`auth`, `api`, `ui`, `billing`, …) — match what `gh pr list` shows.
- **Description** imperative present tense, whole title under ~70 chars.
- **Issue number** parenthesized at the end if there's an associated issue.

## Step 3: Compose the body (four sections, in order; skip a section only if empty)

### 1 — Summary
3–5 bullets describing the change. Reviewer-facing: what it makes happen, not how. Lead with
the outcome.

### 2 — Decisions baked in
The section reviewers most want and templates almost never include. List design choices made
during implementation that aren't obvious from the code, with the alternative considered, so
the next reviewer (or your future self) doesn't re-litigate them.

```markdown
## Decisions baked in

- **Choice A over B** because [reason]. [When this would change.]
- **Pattern X used here** because [reason], matches the precedent in [file/PR].
```
Omit if there genuinely were no decisions to call out (e.g. a typo fix).

### 3 — Test plan
Checkbox list of what was verified, each independently rerunnable, with the actual resolved
commands (from `/webdev:detect-stack`):

```markdown
## Test plan

- [x] `<resolved test cmd> <scoped path>` — N/N passing (local scope per /webdev:run-tests)
- [x] `<resolved lint/format cmd>` — clean
- [x] Manual: <what you did in the browser, if applicable>
```
Check a box only for what you actually ran. The full suite runs on CI — reference it as
context, but don't pre-check it (it hasn't run at PR-open time). For UI work, the Manual line
should come from `/webdev:verify`'s observed results — state explicitly what was checked in the
running app and what still needs human eyes.

### 4 — Follow-ups (optional)
Issues filed, deferred work, or known limitations. Only include if real; don't pad.

### Footer (opt-in only)
**No AI-attribution footer by default** — the PR reflects the human author. Only if the project
sets `"prFooter": true` in `.claude/webdev.json`, end the body with:
```markdown
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## Step 4: Open the PR (heredoc so newlines/special chars survive)

```bash
gh pr create --title "<type>(<scope>): <description> (#<issue>)" --body "$(cat <<'EOF'
## Summary

- ...

## Test plan

- [x] ...
EOF
)"
```
If `gh pr create` reports the PR already exists, switch to `gh pr edit <pr-number> --body ...`.

## Important rules

- **Don't fabricate test results.** If a test wasn't run, don't claim it. Leave the box unchecked.
- **Don't pad the body.** A four-section essay on a one-line change is worse than no body. Only
  Summary is required.
- **No emojis in the title** — they can break `gh` URL encoding.
- **Include a closing keyword for auto-close.** Only `Closes #N` / `Fixes #N` / `Resolves #N` in
  the body (or a commit) triggers GitHub's auto-close on merge. The `(#N)` title suffix is
  human-readable cross-reference only and does NOT auto-close.

## Output

When complete, report back:
- **PR URL** · **Title used** · **Body sections included** · **Closes** (issue number, if any)

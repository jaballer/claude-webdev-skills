---
name: qa-review
description: >
  Broad QA review of recently merged functionality (not one specific PR). Use when the
  user wants to review recent work, smoke-test merged features, or audit the latest
  additions. Trigger on "review recent changes", "QA the latest merge", "smoke test",
  "review what was merged", "anything need fixing?", "check the recent work", "full
  review". For a deep-dive on a single PR, use /webdev:post-merge-review instead.
---

# QA Review

Comprehensive audit of recently merged functionality to catch bugs, gaps, inconsistencies, and
improvement opportunities. Resolve project commands via `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command <test|lint|typecheck|build|migrationStatus>`.

## Step 1: Get onto the up-to-date base (no branch yet)
The audit itself (Steps 2–8) is **read-only** — don't create a branch for it. But it must read
what's actually merged: **invoke `/webdev:sync-main`** first, which checks the working tree,
switches to the default branch, and fast-forwards it. Auditing from a stale local base misses
exactly the recent merges this skill exists to review. A branch is created only in Step 9, and
only if fixes are actually needed — a clean audit should leave no stray `review/*` branch behind.

## Step 2: Identify what was recently merged (parallel)
```bash
git log --oneline --merges -10
git log --oneline -20
gh pr list --state merged --limit 5
```
Read each merge's PR description and commits to understand intent.

## Step 3: Audit the changed files
For each recently merged feature/fix: read every changed file; check **completeness** (missing
migrations, seeds, tests, config?), **consistency** (do new files follow existing patterns?),
**security** (unvalidated input, missing authorization, exposed data?), and **edge cases** (empty
data, missing relations, logged-out, disabled users).

## Step 4: Run the test suite
**Invoke `/webdev:run-tests`** at full scope, which uses `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command test` to get the command. Determine: do all existing tests still pass? does new
functionality have adequate coverage (happy path, validation/failure, authorization)? Document
failures as findings — don't fix yet (Step 9).

## Step 5: Smoke test with static analysis
Run the resolved checks that apply to the stack:
- **Build / type-check** — resolve each command and run it only if one resolved. The script exits non-zero when a stack has no such command, so branch on that to record a **clean N/A skip** rather than a failed step: `if CMD="$(${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command build)"; then bash -c "$CMD"; else echo "build: N/A for this stack"; fi`, likewise for `typecheck`; confirm it compiles.
- **Lint / format check** — same pattern: `if CMD="$(${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command lint)"; then bash -c "$CMD"; else echo "lint: N/A"; fi` (the script returns check-mode commands such as `eslint`, `biome check`, `pint --test`, `phpstan analyse`). A missing optional check is N/A, not a QA failure.
- **Framework integrity** — route/view/config compile check if the framework offers one.

**Comment-quality check**: flag added comments that narrate the next line rather than explain a
non-obvious *why*, and empty/redundant docblocks. Surface in Style / Consistency Issues if present.

## Step 6: Database concerns
Run the resolved migration-status command: `CMD="$(${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command migrationStatus)" && bash -c "$CMD"` (the `&&` skips it when the stack has no migration tooling). Are new migrations
reversible? Proper indexes on frequently-queried columns? Correct foreign-key constraints?

## Step 7: Documentation alignment
Does `CLAUDE.md` / README need updating for new features? New routes/endpoints documented? New
permissions/roles reflected? Changelog entry needed?

## Agent Delegation
Parallelize Steps 3–7: **Sub-agent 1** = Step 3 (code audit); **Sub-agent 2** = Step 4 (tests +
coverage gaps); **Sub-agent 3** = Steps 5–7 (static analysis, DB, docs). Merge before Step 8.

## Step 8: Compile and present findings
- **Bugs / Issues Found** — with file:line; need fixing before the next deploy.
- **Missing Tests** — specific cases that should exist, and what each should verify.
- **Style / Consistency Issues** — deviations from project patterns.
- **Documentation Gaps** — what should be documented but isn't.
- **Recommendations** — non-bug improvements, prioritized by impact.
- **Summary** — overall: merge-ready for production, or are there blockers?

## Step 9: Fix or flag

**First, leave the base clean.** Steps 4–6 can write generated files onto the default branch
(coverage reports, test snapshots, compiled assets, schema dumps) even though the audit is
read-only in intent. Run `git status --short`: if regenerable audit artifacts appear, restore
tracked files (`git restore <paths>`) and remove untracked ones (preview with `git clean -nd`,
then `git clean -fd <paths>`) so the base is exactly as found. Otherwise they either leave the
default branch dirty (clean-audit path) or get swept into the fix commit (fix path).

- **Before applying ANY fix** — quick or substantive — **invoke `/webdev:new-branch`** with a
  `review/` prefix (e.g. `review/qa-auth-flow`). The audit ran on the default branch; edits must not.
- **Quick fixes** (typos, imports, style): apply on that branch.
- **Substantive issues**: describe clearly; let the user decide — if they say fix, same branch.
- After fixes, **invoke `/webdev:run-tests`** (targeted) to confirm nothing broke. Commit via
  `/webdev:commit`.
- **No fixes needed**: report and stop — the base is already restored to clean above, so no branch
  was created and nothing is left behind.

## Notes
- This is a review, not a rewrite — don't refactor working code or add features.
- Focus on what changed recently, not pre-existing issues (unless the merge made them worse).
- Be specific: cite file:line and the exact expected-vs-actual behavior.

## Output
- **Merges reviewed**: count + short descriptions
- **Findings**: count per category (bugs, missing tests, style, docs, recommendations)
- **Blockers**: any issues that should block the next deploy
- **Fixes applied**: count of quick fixes on the review branch (if any)
- **Test result**: pass/fail summary

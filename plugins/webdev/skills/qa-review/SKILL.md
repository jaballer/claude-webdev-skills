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
improvement opportunities. Resolve project commands via `/webdev:detect-stack`.

## Step 1: Create a review branch
**Invoke `/webdev:new-branch`** with a `review/` prefix (e.g. `review/qa-auth-flow`). Don't proceed
without a confirmed branch.

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
**Invoke `/webdev:run-tests`** at full scope. Determine: do all existing tests still pass? does new
functionality have adequate coverage (happy path, validation/failure, authorization)? Document
failures as findings — don't fix yet (Step 9).

## Step 5: Smoke test with static analysis
Run the resolved checks that apply to the stack:
- **Build / type-check** — resolved build or type-checker; confirm it compiles.
- **Lint / format check** — resolved lint in check mode (`eslint`, `biome check`, `pint --test`, `ruff check`).
- **Framework integrity** — route/view/config compile check if the framework offers one.

**Comment-quality check**: flag added comments that narrate the next line rather than explain a
non-obvious *why*, and empty/redundant docblocks. Surface in Style / Consistency Issues if present.

## Step 6: Database concerns
Check the resolved migration-status command (e.g. migrations applied/pending). Are new migrations
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
- **Quick fixes** (typos, imports, style): apply directly on the review branch.
- **Substantive issues**: describe clearly; let the user decide. After fixes, **invoke
  `/webdev:run-tests`** (targeted) to confirm nothing broke. Commit via `/webdev:commit`.

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

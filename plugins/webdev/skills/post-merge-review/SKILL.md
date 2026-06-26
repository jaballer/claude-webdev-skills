---
name: post-merge-review
description: >
  Deep-dive review of a single specific merged PR to catch issues that slipped through
  code review — bugs, missing tests, inconsistencies, doc gaps. Use when the user wants
  to review a particular PR after merge or spot-check a specific merge. Trigger on
  "review PR #123", "check what that PR changed", "post-merge review", "did anything
  slip through on PR #X". Unlike /webdev:qa-review (which audits all recent merges
  broadly), this skill focuses on one PR in depth.
---

# Post-Merge Review

Focused review of one merged PR. Resolve project commands via `/webdev:detect-stack`.

## Step 1: Identify the target PR
If the user gave a number/URL, use it. Otherwise `gh pr list --state merged --limit 10`, present
the list, and ask which to review.

## Step 2: Gather context (parallel)
```bash
gh pr view <number> --json title,body,mergedAt,mergedBy,additions,deletions,files,comments,reviews
gh pr diff <number>
```
Understand **intent** (what it tried to do), **scope** (files/subsystems), and **review feedback**
(were raised concerns fully addressed?).

## Step 3: Read every changed file in full
Read the current version of each file, not just the hunks — context catches logic errors that look
fine in isolation, missing edge cases, inconsistency with siblings, and incomplete refactors (a
rename applied in one place but not another).

## Step 4: Check for completeness
For each change, verify what applies:
1. **Data/migrations** — reversible (`down`/rollback)? correct indexes and constraints?
2. **Tests** — happy path, validation/failure cases, authorization (who can't access), edge cases
   (empty data, null relations, logged-out, disabled users)?
3. **Config / env** — new config keys reflected in the example env file / config schema?
4. **Routes/endpoints** — named, grouped, protected by the right auth/middleware?
5. **Access control** — permission/ownership checks present (no IDOR)?
6. **UI** — new views/components follow existing patterns and responsive conventions?

## Step 5: Run tests
**Invoke `/webdev:run-tests`** targeted on the PR's files, then full to check for regressions.
Document failures as findings — don't fix yet (Step 8).

## Step 6: Static analysis
Run the project's resolved checks (skip any that don't apply to the stack):
- **Build / type-check** — the resolved build or `tsc --noEmit` / framework type-checker; confirm it compiles.
- **Lint / format check** — the resolved lint command in check mode (e.g. `eslint`, `biome check`, `pint --test`, `ruff check`).
- **Framework integrity** — if the framework offers a route/view/config compile check (e.g. route list, template compile), run it to catch broken wiring.

**Comment-quality check** (linters catch formatting, not intent): scan added code for comments that
**narrate the next line** ("loop through users") rather than explain a non-obvious *why* (security
rationale, invariant, workaround), and for empty/redundant docblocks that just restate the
signature. Surface these in Issues if present.

## Step 7: Compile findings
- **PR Summary** — one paragraph: what it did, when merged, by whom.
- **Issues Found** — with file:line, categorized: **Bug** · **Security** · **Missing test** · **Style** · **Documentation**.
- **What Looked Good** — briefly; calibrates the review and acknowledges solid work.
- **Recommendations** — non-bug improvements, prioritized by impact.
- **Verdict** — **Clean** / **Minor issues** / **Needs attention**.

## Step 8: Fix or flag
Ask how to proceed:
- **Quick fixes** (typos, imports, style): **invoke `/webdev:new-branch`** with a `review/` prefix,
  apply, then **invoke `/webdev:run-tests`** to verify. Commit via `/webdev:commit`.
- **Substantive issues**: describe clearly; let the user decide fix-now vs file-an-issue.

## Agent Delegation
Parallelize for speed: **Sub-agent 1** = Steps 3+4 (read files, completeness/correctness);
**Sub-agent 2** = Steps 5+6 (tests + static analysis). Merge before compiling Step 7.

## Notes
- Reviews **one** PR (use `/webdev:qa-review` for all recent merges).
- Focus on what this PR changed; don't flag pre-existing issues unless the PR made them worse.
- Be specific: "line 42 of PostController does X but should do Y" beats "the controller has issues."
- For a large PR, review the riskiest changes first (auth, data mutations, migrations).

## Output
- **PR**: `owner/repo#number` — title · **Files reviewed**: count
- **Findings**: count per category · **Verdict**: clean / minor / needs attention
- **Test result** · **Fixes applied**: count + branch name (if any)

---
name: fix-bug
description: >
  Drives a bug fix end to end with the reproduce → failing test → fix discipline.
  Use when the user reports broken behavior: "fix this bug", "X is broken", "X stopped
  working", "users are seeing Y", pastes an error/stack trace, or points at a defect
  issue ("fix issue #N"). Bug-shaped work differs from feature-shaped work: you must
  see it fail before you change anything, and the proof of the fix is a test that goes
  red → green. For new functionality use /webdev:new-feature; for a red CI check use
  /webdev:fix-ci.
---

# Fix Bug (orchestrator)

The bug-shaped counterpart to `/webdev:new-feature`. Sequencing matters more here: the
discipline is **reproduce → root-cause → failing test → fix → sibling sweep**, in that order.
Resolve all project commands via `/webdev:detect-stack`.

## Hard rule: never fix what you haven't seen fail

A fix applied to an unreproduced bug is a guess wearing a commit message. If you cannot make
the bug happen, you cannot know the fix works — and "it looks right" is how the same ticket
comes back in two weeks. Reproduce first; if you genuinely can't, say so and gather more
information rather than shipping a speculative patch.

## 0. Branch first

**Invoke `/webdev:new-branch`** with a `fix/` prefix (issue number in the name when there is
one, e.g. `fix/412-avatar-upload-500`).

## 1. Pin down the report

Establish, from the user / issue (`gh issue view <n>` when a number exists) / error text:
- **Expected** vs **actual** behavior — one sentence each
- **Repro steps** as reported, and the environment they happened in (which user/role, which
  page/endpoint, which data)
- The **exact error** (message + stack trace) if there is one

If any of these are missing and not inferable, ask now — one question up front beats a wrong
fix later.

## 2. Reproduce it

Make the bug happen yourself before reading much code — the failure output usually localizes
the problem faster than code-reading does. Cheapest applicable route:
- an existing test you can run with the bug's inputs (resolved test command)
- a direct exercise of the path — `curl` the endpoint, run the CLI, invoke the function in a
  scratch script (use a scratch dir, don't commit it)
- the running app via the resolved dev command, following the reported steps

**Can't reproduce?** That's a finding, not a license to guess. Check environment differences
(role/permissions, data state, feature flags, locale/timezone, browser vs server), try the
non-default context, and report back what you tried and what extra detail would pin it down.
Only proceed on an unreproduced bug if the user explicitly accepts a speculative fix — label
the PR as such.

## 3. Find the root cause, not the symptom site

The line that throws is rarely the line that's wrong. Trace backwards from the failure:
what produced the bad value / wrong state / missed call? Keep asking "and what caused *that*?"
until you reach a decision the code makes incorrectly — that's where the fix belongs.
Patching at the symptom site (a null-check here, a try/catch there) leaves the real defect
in place and converts a loud bug into a quiet one.

State the root cause in one sentence before writing the fix. If you can't, you don't
understand the bug yet.

> **Check `/webdev:plan-inventory`'s triggers** before fixing: if the root cause lives in a
> value-shape invariant, shared infrastructure, or code spanning execution contexts, run the
> inventory first — bug fixes in shared code have the same blast radius as features there.

## 4. Write the failing test FIRST

Before the fix, add the test that asserts the **correct** behavior — and run it:

- It must **fail now, for the same reason as the bug** — read the failure output and confirm
  it matches the reproduction from Step 2. A test that fails differently is testing something
  else; a test that passes is vacuous.
- Name it so it documents the defect (reference the issue number where one exists).
- Put it where the project's existing tests for that unit/route live.

**Red first is the point** — a test written after the fix proves only that the test agrees
with the code, not that it would have caught the bug. If the bug genuinely can't be reached
by the project's test harness (visual layout, third-party interaction), record the manual
repro steps explicitly in the PR test plan instead — and say that's what happened.

## 5. Fix at the root cause

Minimal diff that makes the decision correct. Resist refactoring around the bug — note
tempting cleanups as follow-ups instead of expanding the diff. Run the new test: it must go
**green**, and the Step 2 reproduction must no longer reproduce.

## 6. Sweep for siblings

Bugs come in families. Before declaring done, grep for the same mistake elsewhere — the same
misused helper, the same copy-pasted block, the same wrong assumption in a sibling
implementation. Fix siblings in the same commit with the same test treatment, or list them
explicitly as follow-ups if they're genuinely separate. "Fixed the one reported instance" is
the half-done state a reviewer catches.

## 7. Verify

**Invoke `/webdev:run-tests`**: the new test(s) plus the blast radius of the changed code
(full suite only if the fix touched foundational code — that skill's canonical list).
Re-run the original reproduction one last time end to end.

## 8. Commit and PR

**Invoke `/webdev:commit`** (type `fix:`, `Closes #N` when an issue exists). In the PR body's
Summary, include the one-sentence root cause and the red → green test — that's what makes a
bug-fix PR reviewable in one pass.

## Dependency graph

```
/webdev:fix-bug
  ├── /webdev:new-branch        (fix/ prefix)
  ├── /webdev:plan-inventory    (only if the root cause trips its triggers)
  ├── /webdev:run-tests         (new test red → green, then blast radius)
  └── /webdev:commit
        └── /webdev:open-pr
```

## Key reminders

- Reproduce before reading, root-cause before fixing, red test before the fix.
- The symptom site and the fix site are usually different lines.
- If the "bug" turns out to be missing functionality or a behavior-change request, stop and
  say so — that's `/webdev:new-feature` work, and the reporter should confirm the new intent.

## Output

- **Bug**: expected vs actual (one line) · **Reproduced**: how (or "not reproduced — speculative, user-approved")
- **Root cause**: one sentence, with file:line
- **Test**: name + location, confirmed red → green
- **Siblings**: fixed in-commit / follow-ups filed / none found (state which)
- **Test result**: scope + pass/fail · **Branch** · **Commit SHA** · **PR URL**

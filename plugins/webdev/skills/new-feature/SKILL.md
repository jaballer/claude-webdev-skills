---
name: new-feature
description: >
  Drives a new piece of work from start to finish — branch, pre-implementation
  inventory (when warranted), implementation, tests, and commit/PR — by chaining the
  atomic webdev skills. Use when building any new feature, endpoint, page, component,
  or integration. Trigger when the user says "add a feature", "build X", "implement Y",
  "create a new Z", or when starting any non-trivial new functionality. Also useful
  mid-feature as a checklist to confirm nothing was missed.
---

# New Feature (orchestrator)

This skill **delegates** to atomic skills rather than re-describing them. Its job is sequencing
and making sure no phase is skipped. Resolve all project commands via `/webdev:detect-stack`.

> **Bug report, not a feature?** Use `/webdev:fix-bug` instead — the discipline differs
> (reproduce → failing test → fix), and skipping it is how speculative patches ship.

## 0. Branch first

**Invoke `/webdev:new-branch`** before writing any code. Don't proceed without a confirmed branch.

> If you just merged a PR or aren't sure the default branch is clean, **invoke
> `/webdev:sync-main` first**, then branch.

## 0.5. Plan inventory (non-trivial work only)

**Invoke `/webdev:plan-inventory`** before implementation code if the task matches any of its
triggers — consolidating/renaming/deleting surface with multiple call sites, reusing shared
infrastructure on a new surface, code spanning more than one execution context, changing a
uniqueness/scoping invariant, or introducing/tightening a value-shape rule.

Skip for: single-file fix, isolated feature touching no existing infra, UI/copy tweak, docs-only.

**The user must be able to push back on the inventory before code is written. Do not start
implementation until the inventory is acknowledged.**

## 1. Implement

Work in the project's idioms — **follow the conventions already in the codebase and the detected
framework** (file layout, naming, state management, styling) rather than importing a different
project's patterns. Walk the concerns that apply to the change; skip those that don't:

- **Data layer** — schema/migration, model/entity, or persistence changes. Include a reversible
  migration (`up`/`down`), index frequently-queried columns, and decide the backfill story for
  any new invariant (per the plan inventory).
- **Domain / business logic** — keep it out of controllers/handlers and route files; put it in
  services/use-cases/modules where the codebase already does.
- **Routes / endpoints** — name them, group them, attach the right auth/validation, match the
  existing routing convention.
- **Access control** — add the permission/role/ownership check on any new protected surface.
  Confirm object-level ownership (no IDOR).
- **Validation** — validate input at the boundary before use.
- **UI** — components/views following the existing component library, styling system, and
  responsive conventions. No bespoke one-off styling when a shared primitive exists.

Keep the change within the scope boundary you declared in the plan inventory. Anything outside
that list is scope creep — note it as a follow-up instead of expanding the diff.

## 2. Tests and quality

**Invoke `/webdev:run-tests`** scoped to the new files (full suite only for a foundational change
— see that skill). Add tests that assert the invariants surfaced in the plan inventory, including
the non-default execution context. Then run the resolved formatter/linter. For **user-facing**
changes, also **invoke `/webdev:verify`** — exercise the change in the running app before commit.

> **Agent Delegation:** the formatter and the scoped test run are independent — run them as
> parallel sub-agents. Both must pass before committing.

## 3. Commit and PR

**Invoke `/webdev:commit`** to run the pre-push self-review, stage, commit, push, and (by default)
chain to `/webdev:open-pr`. The self-review's checklist 4c will fold in any project-specific bug
classes you've defined in `.claude/bug-classes.md`.

## Dependency graph

```
/webdev:new-feature
  ├── /webdev:new-branch         (and /webdev:sync-main first, if needed)
  ├── /webdev:plan-inventory     (non-trivial work only — per triggers)
  ├── /webdev:run-tests          (scoped; full for foundational)
  └── /webdev:commit
        └── /webdev:open-pr
```

## Key reminders

- Never commit to the default branch — always a feature branch + PR.
- Inventory before code for non-trivial work; the user acknowledges it before you implement.
- Match the codebase's existing patterns over any external convention.
- State the test scope you ran and why (per `/webdev:run-tests`).

## Output

When complete, report back:
- **Branch** · **Inventory**: run (with artifacts) or skipped (why)
- **Files changed** (within the declared scope boundary)
- **Test result**: scope + pass/fail
- **Commit SHA** · **PR URL**

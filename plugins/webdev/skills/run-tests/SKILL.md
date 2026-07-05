---
name: run-tests
description: >
  Runs the project's test suite at the smallest scope that proves the change. Use when
  the user asks to "run tests", "check tests", "make sure tests pass", or before
  committing or opening a PR. Also trigger automatically after code changes that could
  affect existing functionality. Resolves the test command via /webdev:detect-stack, so
  it works on any stack (vitest, jest, phpunit, pest, pytest, …).
---

# Run Tests

Stack-agnostic. **Resolve the test command through `/webdev:detect-stack`** (which honors
`.claude/webdev.json` first, then detection) — never assume `npm test` or `phpunit`. Apply
the project's `commandPrefix` to a **detected** command (e.g. `ddev exec`); a command pinned
in `webdev.json` is already complete — use it verbatim.

## Decision Logic — default to the smallest run that proves the change

The cost of a test run is the **user's time** — a full suite can be many minutes of
wall-clock they sit through. That's the scarce resource, so spend it deliberately. And
**CI almost always runs the full suite on every PR**, so the comprehensive gate already
exists — local runs are for *fast, targeted* feedback, not to duplicate CI.

**Default — including before commit/PR — run the blast-radius-scoped tests.** Scope = the
test file(s) that directly exercise what you changed, plus a thin ring of adjacent /
integration suites. Find them by tracing: changed files → what imports/uses them (grep the
symbol, route name, config key, or flag) → the tests that hit those paths.

**Run the full suite locally only when:**
- The change is **foundational / fans out** — a shared base class or trait, middleware,
  a service-provider / app-bootstrap registration, a global config or helper read widely,
  a role/permission seeder, the test base class, a migration/schema change, or a
  dependency/framework upgrade. There the blast radius *is* most of the suite. **This is
  the canonical foundational list other webdev skills point to rather than re-enumerate.**
- A targeted run **failed somewhere unexpected** — widen to catch the cascade.
- The **user explicitly asks**.

**If full seems warranted but the change isn't clearly foundational, ASK first** — name the
scope you'd run and why; don't burn the user's time on a leaf change by default. Always
**state the scope you picked and why** in your report.

| Context | Default scope |
|---|---|
| Actively changing code | targeted: the file(s) you touched |
| Before commit/PR — leaf change (markup, copy, isolated component, localized fix) | targeted + thin adjacent ring |
| Before commit/PR — foundational change (any item in the list above) | full |
| After a CI failure or surprise | clear caches/build, then full |
| Invoked by another skill | follow that skill's scope — but a foundational change still warrants a full run even if the caller passed targeted scope |

> **Tier follows fan-out, not the noun.** Trace who consumes the change. A config value read
> across many routes is foundational; a single local value is a leaf. A shared/base component
> is foundational; a truly isolated one is a leaf.

## Running targeted vs full (resolved per stack)

Use the resolved test command, then narrow it with the runner's native filter:

| Runner | Full | Single file | Filter by name |
|---|---|---|---|
| vitest / jest | `<test>` | `<test> path/to/file.test.ts` | `<test> -t "name"` |
| phpunit | `<test>` | `<test> tests/Feature/FooTest.php` | `<test> --filter test_name` |
| pest | `<test>` | `<test> tests/Feature/FooTest.php` | `<test> --filter "name"` |
| pytest | `<test>` | `<test> tests/test_foo.py` | `<test> -k "name"` |

`<test>` is the resolved command (incl. `commandPrefix`). If tests behave unexpectedly,
clear caches/build artifacts first (framework-appropriate: `config:clear`, deleting
`.vitest`/`node_modules/.cache`, etc.), then re-run.

## When Tests Fail

1. Read the failure — it includes file and line.
2. Is the failing test one you changed, or pre-existing?
3. If an existing test fails on an intentional UI/copy change, update the assertion to match.
4. If a test fails due to a logic change, **fix the underlying code first** — don't patch the test to pass.
5. Never comment out or skip a failing test without a documented reason.
6. After fixing, re-run the failing test targeted, then its adjacent ring; widen to full only if the fix touched shared/foundational code.

## Output

When complete, report back:
- **Scope**: `full` | `targeted:<file(s)>` — and one line on *why* that scope
- **Command run**: the actual resolved command (so the user can rerun it)
- **Result**: `pass` | `fail`
- **Stats**: test count, assertion/case count
- **Failures** (if any): test name, file, line, one-line summary each

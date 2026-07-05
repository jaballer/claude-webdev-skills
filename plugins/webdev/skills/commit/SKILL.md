---
name: commit
description: >
  Commits completed work the right way — staging the right files, running tests and
  the formatter first, a hostile pre-push self-review, a conventional-commits message,
  push, and (by default) opening a PR. Use when the user says "commit", "let's commit",
  "commit these changes", "I'm ready to commit", or "commit and push". Trigger any time
  work is complete and ready to commit — don't wait to be asked about best practices.
---

# Commit

Work through these steps in order. Skipping steps (especially tests and the self-review)
risks shipping broken code. Resolve all project commands via `/webdev:detect-stack`.

## 1. Confirm you're on a working branch

```bash
git branch --show-current
```
Any non-default branch is fine. **Never commit directly to the default branch.** If you're on
it, stop and **invoke `/webdev:new-branch`** first.

## 2. Run tests

**Invoke `/webdev:run-tests`** scoped to the change's blast radius (see its Decision Logic).
Full suite locally only for a foundational change or an unexpected failure; CI runs full on the
PR. Whatever scope you run must pass before committing — fix failures before step 4.

## 3. Run the formatter / linter

Run the resolved format command (e.g. `prettier --write`, `biome format --write`, `pint`,
`ruff format`). If it modifies files, stage those too. If a linter is configured, run it and fix
violations now.

> **Agent Delegation:** steps 2 and 3 are independent — run them as parallel sub-agents (tests
> at scope · formatter). If either fails, stop and fix before step 4. If the formatter changed
> files, re-run targeted tests on them before the self-review.

## 4. Pre-push self-review (hostile read with enumeration)

Before staging, read the full diff as a cold reviewer seeing it for the first time. The goal is
to **find what's broken**, not confirm the implementation. Passing tests only prove the
behaviors that have tests; everything else rides on the code's unstated assumptions.

```bash
git status
git diff
```

### 4a. The hostile-read rules (stack-agnostic)

Apply each and **enumerate** the file/function pairs you applied it to. "I checked everything"
means the rule wasn't run — every line below must name concrete `file:line` pairs before you push.

1. **Cross-file consistency.** Are sibling functions (resolvers, query builders, validators,
   lookups) consistent in their clauses? Diff them line-by-line; don't eyeball.
2. **Destination behavior.** For every URL/route/redirect changed, did the *behavior* of the
   destination change — not just "does the link resolve" but "does it still do what callers expect"?
3. **Non-default execution context.** For every changed function, trace one scenario in the
   *less obvious* context (logged-out vs in, mobile vs desktop, background job vs request, the
   other tenant/locale/role, the error path vs happy path).
4. **Removed surface.** For every deleted route/component/export, grep for remaining inbound
   references; for every rename, grep BOTH the old and new names.
5. **Error paths.** Does each failure branch / early return leave the system in a sane state and
   mean the right thing to its caller? (JS: is every promise awaited / rejection handled?)
6. **New-concept follow-through.** When you add a feature flag, env var, config key, enum value,
   event name, or validation rule, grep for every site that should also reference it. Coverage is
   binary — partial wiring is silent breakage.
7. **Multi-list consistency.** When the same set of values appears in N>1 places (a validation
   allowlist + a UI dropdown + a switch/case), cross-check them explicitly. N copies are N drift hazards.
8. **State-space for combinable inputs.** When two inputs can express conflicting intent (file
   upload + "remove" checkbox, set + clear flags), enumerate the combinations and decide each
   explicitly. Arbitrary if/else order is the failure mode.
9. **Don't inherit unverified patterns.** When you copy a pattern from existing code (path
   construction, query shape, auth check), the act of copying is the trigger to re-read the
   *source* adversarially. "It's already used elsewhere" is not validation — and if the source
   has a bug, fix it there too.

Required output before declaring the read clean — one concrete line per rule, e.g.:
```
Rule 1 (cross-file consistency): diffed resolveRecipients() [a.ts:40] vs resolveCc() [a.ts:78]; agree except CC omits the enabled filter (intentional, noted)
Rule 4 (removed surface): grepped old name `UserCard` + new `ProfileCard` in src/ + tests/; 0 stale refs
Rule 6 (follow-through): added flag `betaExport` — wired in router [routes.ts:12], nav [Nav.tsx:30]; checked validators/jobs — none needed
...
```
If any line is empty or vague, the rule wasn't applied. **Do not push until every line is concrete.**

### 4b. Web security & correctness checklist

Generic bug classes that recur across web stacks. Run each against the diff and record the result
(`N/A — <why>` or `found + fixed at file:line`).

| # | Check | Signal in the diff | Required action |
|---|---|---|---|
| 1 | Secrets committed | API keys, tokens, passwords, `.env` values, private keys in the diff | Remove; move to env/secret store; rotate if it was real |
| 2 | Injection | String-built SQL/NoSQL, `exec`/`shell`/`eval` with interpolated input, unescaped template SQL | Parameterize / use the ORM's bindings; never interpolate user input into a command |
| 3 | Missing authz/authn | New route, endpoint, mutation, or admin action without a permission/ownership check | Add the auth guard; confirm object-level ownership (no IDOR) |
| 4 | XSS / output not escaped | User input rendered with `dangerouslySetInnerHTML`, `v-html`, `innerHTML`, `{!! !!}`, unescaped template output | Escape by default; sanitize if raw HTML is genuinely required |
| 5 | Untrusted filename in storage path | A stored filename/path derived from the client's original filename | Generate a server-side name (random/UUID) + validate type via server-side MIME, not the client extension |
| 6 | Delete-before-write on replace | `delete(old)` then `write(new)` in the same replace flow | Write new first, check the result, then delete old — a failure between them otherwise destroys the original with no replacement |
| 7 | Collision-prone unique IDs | Filenames/keys built from `time()`/timestamp/`uniqid` without entropy in a concurrent flow | Use a random/UUID primitive so near-simultaneous operations can't collide |
| 8 | N+1 / unbounded DB work | A DB/API call inside a loop, or a query without a limit on user-controlled volume | Eager-load / batch; bound the query |
| 9 | Swallowed errors | `catch {}` with no handling, ignored promise, unchecked return value | Handle, log, or rethrow — don't silently continue in a broken state |
| 10 | Input validation gap | New form/body/query param consumed without validation or type/range checks | Validate at the boundary before use |

### 4c. Project-specific bug classes (extension hook)

If the project defines its own recurring bug classes — in `.claude/bug-classes.md` or a
`## Bug classes` section of its `CLAUDE.md` — **read that file and run each of those checks too**,
recording results the same way. This is how a project layers its hard-won, codebase-specific
review knowledge on top of the generic set above without forking this skill.

### 4d. Cross-cutting
- **Internal contradictions** — did a change here leave a stale assertion elsewhere?
- **Stale references** — examples, "see step N" pointers, snippets that reference the old structure.
- **Sweep coverage** — fixed pattern X in one file? Grep for X elsewhere.

If the self-review surfaces something, fix it now — same diff, no extra commit.

## 5. Stage only the right files

Stage by name. Avoid `git add .` / `git add -A`, which can sweep in:
`.env` (secrets) · `node_modules/` · `vendor/` · `dist/` `build/` `.next/` (compiled, built by CI) ·
local caches. Confirm `.gitignore` covers them; if something gitignored shows up staged, stop.

## 6. Write a conventional-commits message

```
type(scope): short description (imperative, under 72 chars)

Optional body explaining the why, not the what.

Closes #123
```
Types: `feat` · `fix` · `refactor` · `docs` · `test` · `chore`. Imperative mood ("add", not
"added"). Reference the issue with `Closes #N` when one exists. Don't pad — if one line says it
all, that's fine.

## 7. Commit

```bash
git commit -m "$(cat <<'EOF'
feat(scope): your message here

Closes #N
EOF
)"
```
**No AI co-author/attribution trailer by default** — commits reflect the human author. A project
that wants one can opt in with `"coAuthorTrailer": true` in `.claude/webdev.json`; honor that, and
honor any tool-default trailer instruction only when this key opts in.

## 8. Push

```bash
git push -u origin HEAD
```

## 9. Open a PR

**Invoke `/webdev:open-pr`** to compose the title + four-section body and open it via `gh`.
Skip only if the user said "commit but don't PR" or it's a trivial typo/comment change.

## What NOT to do

- Don't push directly to the default branch — open a PR.
- Don't amend an already-pushed commit — make a new one.
- Don't use `--no-verify` to skip hooks — if a hook fails, fix the root cause.
- Don't claim a check passed that you didn't run.

## Output

When complete, report back:
- **Branch** · **Commit SHA** (short) · **PR URL** (if created)
- **Test result**: pass/fail summary and scope
- **Self-review**: confirmation that 4a/4b were enumerated (note anything found + fixed)

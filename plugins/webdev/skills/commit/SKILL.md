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
risks shipping broken code. Resolve project commands via the plugin scripts: run `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command format` for the formatter and `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command lint` for the linter.

## 1. Confirm you're on a working branch

```bash
git branch --show-current
```
Any non-default branch is fine. **Never commit directly to the default branch.** If you're on
it, stop and **invoke `/webdev:new-branch`** first. **Empty output means detached HEAD** — also
stop and branch first: a commit made there is reachable only via the reflog once anything else
is checked out, and `git push -u origin HEAD` can't expand a detached HEAD to a branch.

## 2. Run tests

**Invoke `/webdev:run-tests`** scoped to the change's blast radius (see its Decision Logic).
Full suite locally only for a foundational change or an unexpected failure; CI runs full on the
PR. Whatever scope you run must pass before committing — fix failures before step 5.

## 3. Run the formatter / linter

Run the resolved format command to write files. Capture it **first** — never inline the
substitution into `bash -c "$(…)"`, since `bash -c "$(false)"` exits 0 and silently turns the
gate into a no-op. Then **branch on the exit code**, because "no formatter for this stack" and
"config is broken" are different outcomes: `resolve-command` exits `3` when a stack legitimately
has no such command (a clean skip), but `2` (invalid `.claude/webdev.json`) or `4` (ambiguous
package manager) mean the setup is unsafe and the gate must abort — not silently skip:

```bash
FMT="$(${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command format)"; rc=$?
if [ "$rc" -eq 0 ]; then bash -c "$FMT"
elif [ "$rc" -eq 3 ]; then echo "format: N/A for this stack"
else echo "format: resolver error (exit $rc) — fix config before committing"; exit "$rc"; fi
```

If it modifies files, stage those too. If a linter is configured, run it with the **same
exit-code branching** (swap `format`→`lint`) and fix violations now. Only exit `3` is a clean
skip; `2`/`4` abort.

> **Agent Delegation:** steps 2 and 3 are independent — run them as parallel sub-agents (tests
> at scope · formatter). If either fails, stop and fix before step 5. If the formatter changed
> files, re-run targeted tests on them before the self-review.

## 4. Verify user-facing behavior (conditional)

If the diff has an observable surface — UI, routes, forms, API responses, rendered emails —
make sure `/webdev:verify` results exist for **this** diff before the self-review, and carry the
observed results into the PR's Manual test-plan line (see `/webdev:open-pr`):
- **Already verified this session** (an orchestrator like `new-feature`, `ship-it`, or `fix-bug`
  invoked verify just before chaining here, and the diff hasn't changed since) → **reuse those
  recorded results**; don't re-drive the app for the same diff — a second pass wastes time and
  re-runs seeding/form submits.
- **No current results** (direct `/webdev:commit` invocation, or the diff changed after the last
  verify) → **invoke `/webdev:verify`** now.
- **If verify's fail-fix loop changed code**, redo steps 2–3 at targeted scope on the changed
  files before continuing — a fix made during verification must not dodge the gates that already
  passed on the previous diff.

**Verify must come back clean to proceed.** If its overall result is `failed` — a row still failing
after the fix-and-recheck cap — **stop here**, exactly as you would on a failing test or lint gate;
don't carry a change the running app just proved broken into self-review and staging. Only
`verified`, or `partial` with nothing worse than `needs-human` rows, clears this step.

Skip only for pure refactors, docs, or backend changes fully covered by tests — but then *say*
it was skipped and why in the Output, don't leave verification silently absent.

## 5. Pre-push self-review (hostile read with enumeration)

Before staging, read the full diff as a cold reviewer seeing it for the first time. The goal is
to **find what's broken**, not confirm the implementation. Passing tests only prove the
behaviors that have tests; everything else rides on the code's unstated assumptions.

```bash
git status
git diff
```

**Scale the review to the diff.** For a **trivial diff** — ≤ ~5 changed lines in one file, no new
flag/config key/enum/rule/route, no renames or deletions, no user-input or query handling — the
full enumeration below is more ceremony than the change warrants. Fast path instead:
1. Re-read the diff cold for typos and logic slips.
2. Grep any name/reference the change touches for stale siblings.
3. Confirm no secrets or debug leftovers made it in.

Everything else gets the **full read: 5a + 5b + 5c (project bug classes) + 5d** — tiering never
drops a project's own checks. This is the same threshold `/webdev:review-pr` step 8 uses.
**When unsure, do the full read** — the threshold exists to spare one-line fixes, not to dodge
scrutiny.

### 5a. The hostile-read rules (stack-agnostic)

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

### 5b. Web security & correctness checklist

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

### 5c. Project-specific bug classes (extension hook)

If the project defines its own recurring bug classes — in `.claude/bug-classes.md` or a
`## Bug classes` section of its `CLAUDE.md` — **read that file and run each of those checks too**,
recording results the same way. This is how a project layers its hard-won, codebase-specific
review knowledge on top of the generic set above without forking this skill.

### 5d. Cross-cutting
- **Internal contradictions** — did a change here leave a stale assertion elsewhere?
- **Stale references** — examples, "see step N" pointers, snippets that reference the old structure.
- **Sweep coverage** — fixed pattern X in one file? Grep for X elsewhere.

If the self-review surfaces something, fix it now — same diff, no extra commit. **If that fix
changes an observable surface** (UI, route, form, API response), redo step 4 for the affected
rows — the verify evidence recorded before this review is now stale, and `/webdev:open-pr`'s
Manual line must reflect the diff that actually ships.

## 6. Stage only the right files

Stage by name. Avoid `git add .` / `git add -A`, which can sweep in:
`.env` (secrets) · `node_modules/` · `vendor/` · `dist/` `build/` `.next/` (compiled, built by CI) ·
local caches. Confirm `.gitignore` covers them; if something gitignored shows up staged, stop.

## 7. Write a conventional-commits message

```
type(scope): short description (imperative, under 72 chars)

Optional body explaining the why, not the what.

Closes #123
```
Types: `feat` · `fix` · `refactor` · `docs` · `test` · `chore` · `ci` (workflow/pipeline files). Imperative mood ("add", not
"added"). Reference the issue with `Closes #N` when one exists. Don't pad — if one line says it
all, that's fine.

## 8. Commit

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

## 9. Push

```bash
git push -u origin HEAD
```
**Fork (cross-repository) PRs:** if the current branch tracks a contributor's fork (checked out
via `gh pr checkout`; confirm with `gh pr view --json isCrossRepository`), `origin` is the WRONG
destination — it would create a stray branch on the upstream repo while the PR never updates. Push
an explicit refspec to the fork's PR head instead: `git push <pushRemote> HEAD:<headRefName>`,
where `<pushRemote>` is what `gh pr checkout` configured (`git config branch.<local>.pushRemote`,
else `.remote`) and `<headRefName>` is `gh pr view <number> --json headRefName -q .headRefName`. A
no-argument `git push` can fail here under Git's `push.default=simple` when the local branch name
differs from the head ref. If the push is rejected for missing fork access, stop and report —
don't reroute to upstream.

## 10. Open a PR

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
- **Verify**: run (observed results) / skipped (why — no observable surface)
- **Self-review**: tier used (`fast-path` or `full`) + confirmation 5a–5d were enumerated when full (note anything found + fixed)

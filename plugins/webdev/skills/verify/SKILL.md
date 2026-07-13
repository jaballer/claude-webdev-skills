---
name: verify
description: >
  Proves a change works by exercising the RUNNING app, not just the test suite —
  start the dev server, drive the changed behavior, observe the result. Use before
  committing user-facing work (UI, routes, forms, emails-to-preview, API responses),
  or when the user asks "does it actually work?", "check it in the browser", "try it
  out", "verify the change". Tests prove the behaviors that have tests; this proves
  the behavior a user will actually hit. Complements /webdev:run-tests — it does not
  replace it.
---

# Verify

Green tests prove the assertions that exist. This skill proves the change in the medium the
user will experience it: the rendered page, the actual HTTP response, the real form submit.
Resolve the dev command via `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command dev` and the build command via `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command build` when needed.

## Hard rule: report observations, not intentions

"Verified" means **you saw it happen** — a status code, rendered text, a screenshot. Never
mark an item verified because the code looks right or the tests pass; that's what Step 4's
`needs-human` state is for. A false "verified" is worse than an honest "couldn't check this
here."

## Step 1: Build the verification list from the diff

Read the **whole** change under verification. `<base>` is the default branch resolved as in
`/webdev:new-branch` (`.claude/webdev.json` `defaultBranch`, then `origin/HEAD`, then
`main`/`master`) — for a direct "check it in the browser" run with no caller, that's the ref to
diff against. Pre-commit (the normal `/webdev:commit` / `/webdev:new-feature` path), committed
work alone misses the point — combine: `git diff <base>...HEAD` (committed) **plus** `git diff`
and `git diff --cached` (working tree / staged), **plus untracked files** — a brand-new
route/component is still untracked and invisible to `git diff`; list them with `git status
--short`, the non-mutating way. (If you instead use `git add -N` so they surface in `git diff`,
undo it before returning — `git reset -- <paths>` — so Step 5 leaves the index exactly as found.)
Post-commit, `git diff <base>...HEAD` suffices. From that union, write down each **user-observable behavior** it touches — typically
3–7 rows:

| # | Behavior | How to reach it | Expected |
|---|---|---|---|
| 1 | New /support form submits | POST /support with valid body | 302 to /support/thanks, record created |
| 2 | Validation rejects empty email | same, email="" | 422 + field error rendered |
| 3 | Logged-out visitor | GET /support anonymous | form renders (public page) |

Cover: the **happy path**, at least one **error/validation path**, and the **non-default
context** (logged-out, other role/locale, empty state, mobile viewport) — the same contexts
`/webdev:plan-inventory` artifact 2 enumerates. Reuse those **contexts** to design your rows if an
inventory was run — not artifact 2's rows themselves, which are an execution-context map
(helper/global, context A/B), not driveable behavior/URL/expected cases.

## Step 2: Get the app running

- **Check whether it's already running first** — probe the dev URL/port before starting
  anything; a second instance fighting over the port wastes ten minutes. But a reachable port
  isn't proof it's serving *this* checkout — it may be a leftover server from another branch or
  app. Confirm it's serving the current tree (hit a route/marker unique to the diff, or a
  build/version stamp) before trusting it; restart it if you can't confirm.
- If not, start the resolved dev command **in the background**, note that you started it
  (you'll stop it in Step 5), and wait for the ready signal — don't fire requests at a
  server that's still booting.
- **Confirm you're pointed at a dev/local environment** — check the URL/host and env before
  interacting. Never verify against production, and never trigger real outward side effects
  (live emails, webhooks, payments) — use the framework's preview/test/sandbox mode for those.
- Missing data? Seed via the project's seeders/factories, not by hand-editing the database.

## Step 3: Drive each row — best available method

In order of preference:

1. **Browser automation** available in the session (Playwright MCP, a connected Chrome, or a
   project e2e harness) — use it for anything visual or interactive; take a screenshot as
   evidence for layout-affecting changes.
2. **Direct HTTP** — right for API routes, redirects, headers, and status codes. Status + body:
   `curl -s -w '\n%{http_code}'`. Redirects and response headers: `-w` alone won't show them —
   capture with `curl -s -i` (or `-D -`) and assert on the actual `Location:`/header value.
   Either way assert on body content, not just the code: a 200 error page passes a
   status-only check.
3. **The rendered-HTML compromise** — `curl` + grep for expected markup proves presence, not
   appearance. Fine for "the new field renders"; NOT sufficient for "it looks right".

Match the method to the claim: never make a **visual** claim ("looks correct", "aligned",
"responsive") from anything but a browser/screenshot.

## Step 4: Judge each row honestly

- **pass** — observed the expected result; record what was seen (code, text, screenshot ref).
- **fail** — observed the wrong result. This is a finding: fix it, then re-verify **that row
  and any row the fix could touch** (cap: 2 fix-and-recheck loops, then stop and report).
  A fix made here changed the diff — **re-run the invalidated quality gates** (targeted tests +
  formatter on the changed files; in the `/webdev:commit` flow, redo its steps 2–3) before the
  work proceeds to staging. Verification must not become the door code sneaks through untested.
- **needs-human** — can't be observed from here (subjective visual polish, a real device,
  an external service in live mode). Hand the user a numbered manual script: exact URL,
  exact steps, expected result — precise enough to run without asking anything.

## Step 5: Clean up

Stop any server **you** started (leave running ones you found alone). Remove seeded
throwaway data if it would pollute later runs. Leave the working tree exactly as the
change left it.

## When to run this

- Before `/webdev:commit` for any user-facing change — the PR's Test-plan "Manual:" line
  (see `/webdev:open-pr`) should be filled from this skill's output, not from memory.
- After `/webdev:fix-bug` step 2's reproduction — re-running the original repro through the
  live app after the fix IS this skill.
- Not needed for pure refactors, docs, or backend changes fully covered by tests — don't
  ceremony a change with no observable surface.

## Output

- **Rows**: `#` · behavior · method (browser / http / html-grep) · observed → **pass / fail / needs-human**
- **Overall**: `verified` / `partial (N needs-human)` / `failed (fixed: N, open: N)`
- **Evidence**: screenshots taken / response excerpts (so the claim is checkable)
- **Manual script for the user**: the needs-human rows, numbered, or "none"
- **Server**: reused running / started-and-stopped / left running (why)

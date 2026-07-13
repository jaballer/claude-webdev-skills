---
name: plan-inventory
description: >
  Produce a written inventory of what already exists and could break BEFORE writing
  any code, for non-trivial work. Use whenever the task involves consolidating /
  splitting / renaming / deleting routes, components, exports, or services with
  multiple call sites; reusing existing shared infrastructure (rate limiters,
  middleware, queues, caches, hooks, services) on a new surface; code that runs in
  more than one execution context (logged-in/out, server/client, prod/test, per
  tenant/locale/role); changing a uniqueness/scoping invariant; or introducing or
  tightening a value-shape rule (slug/identifier/status/enum format). Auto-invoke
  from /webdev:new-feature when triggers match. Skip for single-file bug fixes,
  isolated new features, copy/style tweaks, and docs-only changes.
---

# Plan Inventory

The purpose of this skill is to **produce a written audit of existing surface before writing
any new code.** Code outlines accept the existing surface as given; inventories audit it. Most
of the bugs a reviewer catches on non-trivial changes trace back to skipping this step — you
solved the problem you saw and shipped, then a sibling corner you never enumerated breaks.

> **Why it pays for itself:** the cost of a 5-minute inventory is one paragraph the user can
> correct. The cost of skipping it is a chain of follow-up commits, each patching one corner a
> reviewer flags, three rounds deep. Surfacing the blast radius *before* you choose contracts is
> the structural fix; a post-implementation self-review (see `/webdev:commit` step 5) catches
> some of it, but by then the contracts are already chosen — the miss is upstream.

## When to run

Run BEFORE implementation code if **any** are true:
- Consolidating, splitting, renaming, or deleting a route / component / export / service with
  multiple call sites
- Reusing existing **named** shared infrastructure (rate limiter, middleware, queue, cache key,
  global store, hook, service) on a **new** surface
- The new code runs in more than one execution context, or crosses a boundary (server↔client,
  authed↔anon, request↔background job, per-tenant↔global, per-locale, per-role)
- Changing a uniqueness or scoping invariant (DB UNIQUE constraints, identity columns, route
  bindings, cache-key scoping)
- Introducing or tightening a **value-shape invariant** — a rule about what shape a value can
  legally hold (slug/identifier format, status enum, role string, ID type)

Skip if: single-file bug fix with localized blast radius · new feature touching no existing
infra · UI/copy/style tweak · docs-only. **If unsure, run it.**

## Step 0 — Check for an existing surface doc

Before the tactical artifacts, check whether the repo already has an authoritative enumeration
of the invariant you're touching — an architecture doc, a `docs/` feature spec, an ADR, a
`.claude/bug-classes.md`, or a `## Bug classes`/architecture section in `CLAUDE.md`. If one
exists, your plan **must reference it explicitly** and call out what the change adds, modifies,
or skips. If a cross-cutting invariant (auth/identity, permissions, billing, notification
routing) has **no** such doc, **writing that enumeration is the first deliverable** — a separate
commit before any code, presented as the planning artifact for approval.

Why: the tactical artifacts below are *per-task* tables that surface the local blast radius.
Cross-cutting invariants span enough subsystems that no per-task grep finds all of them — a
durable doc is what catches "the plan named 4 call sites but the real surface was 15."

## The seven artifacts

Each is a concrete table with `file:line` references, not paragraphs of intent. Surface all of
them (or "N/A — why") to the user **before** writing code.

### 1. Inbound reference inventory
For any route, export, public symbol, URL, or component being deleted / renamed / having its
semantics changed, grep every reference (old name AND any aliases):
```bash
grep -rn "oldRouteName\|OldComponent\|/old/url-path" src app routes resources tests \
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.vue" --include="*.php" --include="*.blade.php"
```
| Reference | File:line | Intent / audience | Decision |
|---|---|---|---|
| `Link to="/contact"` | `src/components/Footer.tsx:40` | public marketing | repoint to `/support` |
| `fetch('/api/contact')` | `src/lib/forms.ts:12` | authed app | keep, alias old route 1 release |

The **intent column is load-bearing.** Auto-rewriting every match without per-reference intent
analysis is how a link that "still resolves" silently changes destination behavior for one audience.

### 2. Execution-context surface map
For every shared helper / global / hook the new code calls, name what it returns or does in
*each* relevant context. List the easy mis-read.
| Helper / global | Context A | Context B | Easy mis-read |
|---|---|---|---|
| `getCurrentUser()` | request: the authed user | background job: `null` | "always set" — wrong in a queued worker |
| `useSession()` | client: hydrated after mount | SSR: `undefined` first render | "available immediately" |
| `process.env.API_URL` | prod: absolute prod URL | test: unset/localhost | "same everywhere" |
| feature flag `betaX` | enabled tenant: on | other tenant: off | "global" when it's per-tenant |
If you can't fill a cell from the actual source, **read the source before writing the inventory.**

### 3. Shared infrastructure read
For every named rate limiter, middleware, queue, cache key, store, or service the new code
**reuses**, read its definition end to end before deciding to reuse it.
| Piece | File | Behavior in original context | Behavior in the new context | Reusable as-is? |
|---|---|---|---|---|
| `apiLimiter` (per-user bucket) | `middleware/rate.ts` | keyed by user id | anon route has no user → **all anon share one bucket / DoS surface** | No — add per-IP key |
| `requireAuth` middleware | `middleware/auth.ts` | redirects to login | API route needs 401 JSON, not redirect | No — use `requireApiAuth` |
The load-bearing question for any shared key/bucket/cache: **what does its key collapse to in the
new context?** A key that assumed a narrower scope becomes a global collision/DoS surface when broadened.

### 4. Sibling / cross-implementation consistency
When deleting one path that does the same conceptual job as another you're keeping (or merging
two into one), write all involved contracts side by side:
| | Implementation A | Implementation B | Decision |
|---|---|---|---|
| Returns | `string[]` (multi) | `string \| null` (single) | B must become multi |
| Filters inactive | yes | **no** | add to B |
| Error semantics | returns `null` | throws | pick one, apply to both |
Drift between siblings (one filters, one doesn't; one fans out, one collapses) is the load-bearing
pattern a reviewer catches and an explicit table prevents.

### 5. Output pipeline trace
For any view / template / email / serializer / API response touched, walk every dynamic value
(URLs, env-dependent values, user-supplied data, money/dates) and label whether it's correct in
the **target** context:
| Call site | Value | Context-correct? | Action |
|---|---|---|---|
| `email.tsx:30` | `\`${process.env.APP_URL}/admin\`` | depends on who renders it | use the absolute prod URL for an emailed link, not a request-relative one |
| `UserCard.tsx:18` | `{user.bio}` | raw HTML? | escape — don't `dangerouslySetInnerHTML` |
Pinning one value while leaving the pipeline in the wrong context only fixes the case you saw;
future additions inherit the same bug.

### 6. Docs-touched checklist
If renaming a symbol, restructuring a flow, or changing a route's semantics:
```bash
grep -rn "OldName\|old.route\|/old-url" docs README.md CLAUDE.md --include="*.md"
```
| Doc | What it claims | Update needed |
|---|---|---|
| `docs/api.md` | "POST /api/contact" | route is now `/api/support` |
Update in the **same PR** — repo docs are shared long-term memory; deferring makes the next reader start from a wrong model.

### 7. Value-shape invariant enumeration
Required whenever the change introduces or tightens a rule about what shape a value can hold.
This catches "I solved one corner of an invariant and shipped; a sibling corner broke three PRs
later." **Format: one row per (input source × possible value), with an explicit decision each.**
| Input source | Possible value | Acceptable? | If not, normalize to |
|---|---|---|---|
| `slugify(title)` — normal | `"hello-world"` | ✓ | — |
| `slugify(title)` — digits only | `"2026"` | ✗ collides with id-route branch | `post-2026` |
| `slugify(title)` — symbols/emoji/whitespace only | `""` | ✗ empty breaks `/posts/${slug}` | `post-{random}` |
| direct assignment / API import / admin paste | any string | bypasses the generator | normalize via the same helper |
| legacy rows (pre-invariant) | varies | per row | **backfill migration** |
| read-back into a URL/consumer | `""` / `null` | ✗ collapses the consumer | guard the consumer too |

Input sources to enumerate for *every* value-shape invariant: (1) all write entry points
(generator, direct assignment, factory/seed, mass-assignment, API/webhook import, admin paste);
(2) every edge case of the generator (empty, all-punctuation, all-emoji, all-whitespace, all-digits,
very long); (3) the discriminating predicate's edge cases (e.g. `isNumeric("1e2")` is true but
maybe shouldn't be); (4) type coercion at the boundary (query string vs typed param, `==` vs `===`);
(5) **existing data** — at least one "legacy rows" row, decided as backfill-or-N/A; (6) future/external
sources that bypass your write path; (7) the reverse direction — what shapes break the consumer.

**Required gate:** explicitly answer "**What's the backfill story?**"
- ✓ Existing data conforms → "N/A, column just created" or "verified via a count query"
- ✓ Backfill needed → migration name + brief design (chunked? collision strategy?)
- ✗ Don't ship without an answer here.

## Output

Produce all seven artifacts (or "N/A — why") in the conversation **before** any implementation
code, so the user can push back when the cost of changing direction is one paragraph:

```markdown
## Plan inventory for [task]
### 1. Inbound reference inventory      [table or N/A]
### 2. Execution-context surface map    [table or N/A]
### 3. Shared infrastructure read       [table or N/A]
### 4. Sibling consistency              [table or N/A]
### 5. Output pipeline trace            [table or N/A]
### 6. Docs-touched checklist           [table or N/A]
### 7. Value-shape invariant            [table + backfill gate, or N/A]

### Pre-flight gates (answer before any code; ✓ or why N/A)
- [ ] Scope boundary — which files do I edit vs only read? (List paths; anything else is creep.)
- [ ] Test strategy — what new tests assert artifact 7's invariants? what existing tests might regress?
- [ ] Backfill story — if artifact 7 has a legacy-rows row, what's the migration plan?
- [ ] Rollback story — if this ships wrong, what's the revert path (pure-code, or counter-migration)?
- [ ] Doc surface — which docs does the change invalidate (artifact 6)? update same PR or out of scope?
- [ ] Sibling contracts — is there a sibling with the same shape not getting the same fix? file a follow-up.

### Open questions for you
- [decisions that need user input before code starts]
```
After the user approves or amends, then write code. **Do not invert this order.**

## What this does NOT replace
- `/webdev:new-branch` — branching is independent; both run before code.
- `/webdev:run-tests` — tests run after code; this runs before.
- `/webdev:commit` step 5 — that's the *post*-implementation hostile read; this is the *pre*-implementation audit. Non-trivial work needs both.

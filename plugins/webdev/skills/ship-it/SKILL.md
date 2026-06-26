---
name: ship-it
description: >
  The guided, beginner-friendly way to take a change from idea to merged PR. Same
  workflow as /webdev:new-feature, but it explains each step in plain language, confirms
  before anything irreversible, and assumes you're new to git, branches, and pull
  requests. Use when the user says "help me ship this", "I'm new to this", "walk me
  through it", "how do I get my change live", or seems unsure about the git/PR workflow.
  For experienced users who just want the workflow run, prefer /webdev:new-feature.
---

# Ship It (guided)

This is the hand-holding version of `/webdev:new-feature`. It runs the **same** underlying skills,
but narrates what's happening and why, and pauses for confirmation at each step that's hard to
undo. The aim is that someone new to the workflow finishes with both a merged change *and* an
understanding of what just happened.

**Teach as you go.** The first time each concept comes up, explain it in one plain sentence — what
a *branch* is, what a *commit* is, what a *pull request* is, why tests run before shipping. Don't
lecture; just don't assume the knowledge.

**Apply `/webdev:safe-edit` throughout.** Before anything irreversible (force-push, deleting files,
resetting), classify and confirm per that skill. Default to confirming more often here than in the
power-user flow.

## The guided path

### 1. Make sure we're starting clean
Explain: "We don't change the main copy directly — we make a separate workspace called a *branch*,
so the working version stays safe." **Invoke `/webdev:new-branch`** (and `/webdev:sync-main` first
if the base looks stale). Show the branch name and what it means.

### 2. Decide if we need to plan first
For anything beyond a small isolated change, explain that a few minutes of looking before leaping
saves a lot of rework, and **invoke `/webdev:plan-inventory`**. Walk the user through the inventory
in plain terms and **get their okay before writing code**. For a genuinely small change, say so and
skip it — don't over-ceremony a one-line fix.

### 3. Make the change
Implement it, following the project's existing patterns (lean on `/webdev:explain-codebase` first if
the user doesn't know the codebase). Narrate what you're changing and why in plain language. Keep
the change inside the scope you agreed on — note anything tempting-but-unrelated as "later," don't
fold it in.

### 4. Check it works
Explain: "Tests are an automatic way to confirm we didn't break anything." **Invoke
`/webdev:run-tests`** at the right scope and explain the result. If something fails, walk through
the fix together rather than just silently patching it.

### 5. Save and share the work
Explain commits and PRs in one sentence each, then **invoke `/webdev:commit`** — it runs a careful
self-review, saves the change (*commit*), uploads it (*push*), and opens a *pull request* for review.
Show the PR link and explain that this is where the change gets reviewed before going live.

### 6. Handle any feedback
If a reviewer (a person or an automated bot) leaves comments, explain that this is normal and good,
then **invoke `/webdev:review-pr`** to walk through addressing them. Reassure the user that
review comments aren't criticism of them — they're how code gets better.

### 7. Done
Summarize what shipped in plain language and what happens next (a maintainer merges the PR, or the
user does once it's approved). Point out one thing they could try on their own next time.

## Tone

- Encouraging and concrete. Celebrate the small wins (first branch, first PR).
- Never make the user feel slow for not knowing something. Define terms the first time, then use them.
- Prefer showing over telling — link the actual branch, the actual PR, the actual test output.
- If the user wants to go faster once they're comfortable, point them at `/webdev:new-feature`.

## Output

When complete, report back in plain language:
- **What we built** · **Branch** · **PR link**
- **Tests**: what passed
- **What's next**: who merges it / how it goes live
- **One thing learned**: a concept the user now knows that they didn't before

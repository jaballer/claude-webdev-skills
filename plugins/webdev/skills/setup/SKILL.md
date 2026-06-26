---
name: setup
description: >
  First-run setup for a project — detects the stack, scaffolds a CLAUDE.md and an
  optional .claude/webdev.json, and explains what it configured. Use when the user
  installs this plugin in a new project, says "set up webdev here", "configure this
  project", "get started", "initialize", or when other webdev skills can't resolve
  the toolchain cleanly. Safe by default: never overwrites an existing CLAUDE.md
  without showing a diff and asking first.
---

# Setup

Gets a project ready to use the rest of the `webdev` skills, and teaches the user what each
piece is for. Designed to be the first thing run in a freshly-cloned or freshly-installed project.

## Step 1: Detect the stack

**Invoke `/webdev:detect-stack`** and present the resolved profile to the user in plain language —
what package manager, test runner, formatter, framework, and dev command it found, and anything it
*couldn't* resolve.

## Step 2: Decide whether a `.claude/webdev.json` is needed

Zero-config is the goal — **don't create a `webdev.json` just to restate what detection already gets
right.** Recommend creating one only when:
- detection was **ambiguous** (e.g. two lockfiles, no test script found), or
- the project needs a **command prefix** (DDEV, Docker, a Makefile target), or
- the user wants to **pin** commands or branch prefixes for determinism.

If one is warranted, write `.claude/webdev.json` containing **only** the keys that need pinning
(see `examples/webdev.json` in the plugin repo for the full shape), and explain each key you wrote.
Leave everything else to detection.

## Step 3: Scaffold or update `CLAUDE.md`

`CLAUDE.md` is the project's standing instructions — Claude reads it every session. **Read-before-write:**
- **No `CLAUDE.md` yet** → offer to create a starter with these sections: one-line project description,
  the stack profile from Step 1, how to run/test/build, key conventions, and a `## Bug classes`
  placeholder (the extension hook `/webdev:commit` reads). Show it and confirm before writing.
- **`CLAUDE.md` exists** → do NOT overwrite. Suggest specific additions (e.g. a missing run/test
  section, or a `## Bug classes` section) and show them as a diff for approval.

## Step 4: Offer the bug-classes hook (optional)

Explain the extension hook: a `.claude/bug-classes.md` file (or a `## Bug classes` section in
`CLAUDE.md`) lets the project add its own recurring review checks that `/webdev:commit` and
`/webdev:review-pr` fold in automatically. Offer to scaffold a stub with one or two example checks
if the project has known footguns. Don't force it.

## Step 5: Explain what comes next

Close with a short, friendly orientation — the skills the user will reach for most and when:
- `/webdev:new-feature` — build something new, start to finish
- `/webdev:ship-it` — the guided version if the git/PR workflow is new to you
- `/webdev:explain-codebase` — get oriented in unfamiliar code
- `/webdev:commit` / `/webdev:open-pr` / `/webdev:review-pr` — the commit-to-merge path

## Important rules

- **Never overwrite an existing `CLAUDE.md`, `webdev.json`, or `.gitignore`** without showing the
  change and getting explicit confirmation.
- **Don't pin in `webdev.json` what detection already handles** — over-configuration is a maintenance burden and drifts from reality.
- Keep generated files short and real — no placeholder lorem, no sections the project doesn't need.

## Output

When complete, report back:
- **Stack profile**: the resolved toolchain (and any gaps)
- **Files created/updated**: paths, with one line each on what and why
- **webdev.json**: created (which keys + why) or "not needed — detection is clean"
- **Next steps**: the 2–3 skills the user should try first

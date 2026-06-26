---
name: explain-codebase
description: >
  Orient someone in an unfamiliar codebase — what it is, the stack, where things live,
  the entry points, how to run/test/build it, and where to start reading. Use when the
  user says "explain this codebase", "help me understand this project", "give me a tour",
  "what is this", "where do I start", "how does this app work", or has just cloned a repo
  they don't know. Read-only — it explains, it doesn't change anything.
---

# Explain Codebase

Produce a clear, accurate orientation for someone seeing this project for the first time. The
audience may be new to the stack — favor plain language and concrete file paths over jargon.

**This skill is strictly read-only.** It does not edit, run mutating commands, or install anything.

## How to build the tour — read, don't guess

Ground every claim in a file you actually read. Don't infer architecture from the framework's
reputation; confirm it in the code. Work through these, in roughly this order:

1. **What is it?** Read `README.md`, `package.json`/`composer.json`/`pyproject.toml` description,
   and any `docs/` index. State the project's purpose in 1–2 sentences. If it's genuinely unclear,
   say so rather than inventing a mission.
2. **Stack** — **invoke `/webdev:detect-stack`** and report the framework, language, package
   manager, test runner, and build tool. Note the major dependencies that shape the architecture
   (ORM, state manager, UI library, auth).
3. **Layout** — map the top-level directories to their roles (`src/`, `app/`, `routes/`,
   `components/`, `tests/`, `config/`, etc.). One line each. Skip vendored/generated dirs.
4. **Entry points** — where execution starts: the server bootstrap, the router/route definitions,
   the main app component, the CLI entry, background workers. Cite the actual files.
5. **Data model** — the core entities/models/tables and their relationships, if there's a clear
   data layer. Point at the schema/migrations/models directory.
6. **How to run it** — the resolved dev, test, and build commands (from `/webdev:detect-stack`),
   plus any required setup the README calls out (env file, services, seed data). Don't run them;
   just report them accurately.
7. **Conventions** — read `CLAUDE.md`, `CONTRIBUTING.md`, lint/format config, and a couple of
   representative source files to surface the real patterns (naming, file structure, styling
   approach, how state/data flows). Cite an example file for each pattern you name.
8. **Where to start reading** — recommend the 3–5 files a newcomer should open first to understand
   the app, in order, with one line on why each matters.

## Scale to the ask

- "Quick overview" → sections 1, 2, 3, 6 only — a tight one-screen orientation.
- "Full tour" / "help me understand this deeply" → all eight, with more cited examples.
- A question about a *specific* area ("how does auth work here?") → focus the tour on that
  subsystem: trace it end to end with file:line references, skip the rest.

## Honesty rules

- If something is ambiguous or you couldn't find it, **say so** — "I didn't find a test setup" is
  more useful than a confident guess.
- Don't present the framework's *typical* structure as *this project's* structure unless you
  verified it in the files.
- Flag anything that looks surprising or risky in passing (no tests, secrets committed, a stalled
  migration) — but don't turn the tour into an audit; that's `/webdev:qa-review`.

## Output

A structured tour with clickable `path` / `path:line` references throughout:
- **What it is** (1–2 sentences) · **Stack** · **Layout** (dir → role)
- **Entry points** · **Data model** (if applicable) · **How to run / test / build**
- **Conventions** (with example files) · **Start here** (ordered reading list)
- **Open questions / things I couldn't determine** (if any)

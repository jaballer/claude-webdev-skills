# Web Dev Workflow — Claude Code Skills

A **stack-agnostic** set of [Claude Code](https://claude.com/claude-code) skills that give
any web project a consistent, well-reasoned workflow: **branch → plan → test → commit → PR
→ review**. The skills auto-detect your toolchain (package manager, test runner, formatter,
framework) so they work zero-config on a fresh Vite/Next/Laravel/Django project — and let
power users pin exact commands via a small override file.

Built by [Jabal Torres](https://jabaltorres.com). Distributed as a Claude Code plugin.

## Why

Most workflow skills are welded to one project's stack. These aren't. The *valuable* part of
a workflow — when to branch, what to audit before writing code, how small a test run proves
a change, how to self-review a diff before pushing — is the same whether you're on pnpm or
Composer. This plugin keeps that structure and pushes the stack-specific commands down into
a detection layer.

## Install

```text
/plugin marketplace add jaballer/claude-webdev-skills
/plugin install webdev@webdev-skills
```

Skills are then available namespaced as `/webdev:<name>` (e.g. `/webdev:run-tests`), and
Claude will also invoke them automatically based on what you ask for.

## How it adapts to your stack

1. **Zero config.** On a standard project, `/webdev:detect-stack` reads your lockfile and
   config to resolve the right commands. Just install and go.
2. **Explicit override (optional).** Drop a `.claude/webdev.json` in your project to pin any
   command. Anything pinned there wins; the rest is detected. See
   [`examples/webdev.json`](examples/webdev.json) — including a `commandPrefix` for
   containerized setups like DDEV/Docker.

```json
{
  "test":   "pnpm test",
  "format": "pnpm run format",
  "dev":    "pnpm dev",
  "branchPrefixes": ["feature", "fix", "refactor", "docs", "chore"]
}
```

## Skills (v0.1.0)

| Skill | What it does |
|---|---|
| `/webdev:detect-stack` | Foundation — resolves package manager, test/format/lint/dev commands, framework. Other skills call this first. |
| `/webdev:run-tests` | Runs tests at the smallest scope that proves the change; full suite only when the change fans out. |

> Roadmap below. This is an early scaffold — the workflow skills (`new-branch`, `commit`,
> `open-pr`, `review-pr`, `plan-inventory`, `new-feature`) and the beginner on-ramp skills
> are being ported next.

## Roadmap

- **Core workflow:** `new-branch`, `sync-main`, `commit`, `open-pr`, `review-pr`, `plan-inventory`, `new-feature` (orchestrator)
- **Quality:** `qa-review`, `post-merge-review`
- **Beginner / vibecoder on-ramp:** `setup` (scaffold CLAUDE.md + webdev.json), `explain-codebase`, `safe-edit` (guardrails), `ship-it` (guided happy path)

## Conventions (house style)

Skills follow a deliberate structure: **atomic vs orchestrator** split, explicit
`Invoke /webdev:<skill>` chaining, a `## Output` contract per skill, and **decision logic
instead of bare command lists**. Contributions should match it — see `CONTRIBUTING.md`.

## License

MIT

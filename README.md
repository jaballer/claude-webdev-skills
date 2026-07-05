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

Two separate steps — run each at Claude Code's main `/` prompt, one at a time:

1. **Add the marketplace.** Enter just the `owner/repo` when prompted for a source:

   ```text
   /plugin marketplace add jaballer/claude-webdev-skills
   ```

2. **Install the plugin** from that marketplace:

   ```text
   /plugin install webdev@webdev-skills
   ```

> Don't paste both lines together. The first command opens an "Add Marketplace"
> dialog whose source field expects only `jaballer/claude-webdev-skills` — pasting the
> `/plugin install …` line into it produces an "is not a valid GitHub owner/repo" error.

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

**All supported keys** (pin any subset; the rest is detected):

| Key | Used by | Meaning |
|---|---|---|
| `packageManager`, `install`, `test`, `format`, `lint`, `typecheck`, `dev`, `build` | all command-running skills | The resolved commands |
| `commandPrefix` | all command-running skills | Prepended to **detected** commands only (e.g. `ddev exec`); pinned commands are used verbatim — write them complete, prefix included |
| `migrationStatus` | `qa-review` | Migration-status command, if the stack has one |
| `defaultBranch` | `new-branch`, `sync-main`, `open-pr` | Overrides origin/HEAD detection |
| `mergeMethod` | `merge-pr` | `"squash"` / `"merge"` / `"rebase"` — overrides repo-history detection |
| `branchPrefixes` | `new-branch` | Allowed branch name prefixes |
| `coAuthorTrailer` | `commit`, `review-pr` | **Default `false`.** Opt in to an AI co-author commit trailer |
| `prFooter` | `open-pr` | **Default `false`.** Opt in to a "Generated with Claude Code" PR footer |

## Skills (v1.5.0)

**Getting started**

| Skill | What it does |
|---|---|
| `/webdev:setup` | First-run setup — detects the stack, scaffolds `CLAUDE.md` + an optional `.claude/webdev.json`, explains what it configured. Never overwrites without asking. |
| `/webdev:explain-codebase` | Read-only tour of an unfamiliar project: what it is, the stack, layout, entry points, how to run it, where to start reading. |
| `/webdev:ship-it` | The guided, beginner-friendly path from idea to merged PR — same workflow as `new-feature`, but explains each step and confirms before anything irreversible. |
| `/webdev:safe-edit` | Guardrails — classify an operation's reversibility and blast radius, then proceed / confirm / back-up-first. The common footguns, spelled out. |

**Build loop**

| Skill | What it does |
|---|---|
| `/webdev:new-feature` | **Orchestrator** — drives a whole change: branch → inventory → implement → test → commit → PR by chaining the skills below. |
| `/webdev:fix-bug` | **Orchestrator** for defects — reproduce → root-cause → failing test → fix → sibling sweep → commit/PR. Never fixes what it hasn't seen fail. |
| `/webdev:detect-stack` | Foundation — resolves package manager, test/format/lint/dev commands, framework. Other skills call this first. |
| `/webdev:plan-inventory` | Pre-implementation audit: 7 artifacts (references, execution-context, shared infra, sibling consistency, output pipeline, docs, value-shape) surfaced for approval *before* code. |
| `/webdev:run-tests` | Runs tests at the smallest scope that proves the change; full suite only when the change fans out. |
| `/webdev:verify` | Proves user-facing work in the running app — dev server up, drive the changed behavior (browser/HTTP), report only what was observed. Complements tests, doesn't replace them. |
| `/webdev:new-branch` | Creates a properly-named branch off the up-to-date default branch (auto-detected). |
| `/webdev:sync-main` | Returns the repo to a clean default branch after a merge; prunes refs and (with confirmation) deletes merged branches. |
| `/webdev:commit` | Tests, formats, runs a hostile pre-push self-review + web security checklist, writes a conventional commit, pushes, opens a PR. |
| `/webdev:open-pr` | Opens a PR with a four-section reviewable body (Summary / Decisions baked in / Test plan / Follow-ups). |

**Review loop**

| Skill | What it does |
|---|---|
| `/webdev:review-pr` | Addresses PR review comments (any bot or human) end to end: verify → sweep → fix → test → commit → reply → resolve threads → wait-and-recheck. Silence ≠ approval. |
| `/webdev:fix-ci` | Triage a red check: read the failing run's logs, classify (this branch / pre-existing / flake), reproduce locally, fix the cause, watch it go green. Never fixes the signal. |
| `/webdev:merge-pr` | Merges the safe way: gate on approvals + green checks + resolved threads + up-to-date branch, pick the repo's merge method, merge, watch post-merge runs, chain to `sync-main`. |
| `/webdev:post-merge-review` | Deep-dive review of a single merged PR — completeness, tests, security, docs, with a verdict. |
| `/webdev:qa-review` | Broad audit of all recently merged work, with parallel sub-agents and a blocker summary; fixes (if any) land on a `review/` branch. |

> **Two project extension hooks** let a repo layer its own knowledge on top without forking a
> skill: `commit`'s self-review reads `.claude/bug-classes.md` (codebase-specific bug classes),
> and `plan-inventory` references any existing architecture/feature doc as the surface checklist.

## New to this? Start here

```text
/webdev:setup            # configure the project (once)
/webdev:explain-codebase # get oriented if the code is unfamiliar
/webdev:ship-it          # make your first change, guided end to end
```

## Roadmap

The core is complete. Planned next skills, roughly in order: `update-deps` (dependency
upgrades with changelog reading and foundational-tier testing), and a `compare`/changelog
skill for release notes.

## Conventions (house style)

Skills follow a deliberate structure: **atomic vs orchestrator** split, explicit
`Invoke /webdev:<skill>` chaining, a `## Output` contract per skill, and **decision logic
instead of bare command lists**. Contributions should match it — see `CONTRIBUTING.md`.

## License

MIT

# Web Dev Workflow — Claude Code Skills

[![CI](https://github.com/jaballer/claude-webdev-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/jaballer/claude-webdev-skills/actions/workflows/ci.yml)

A **stack-agnostic** set of [Claude Code](https://claude.com/claude-code) skills that give
any web project a consistent, well-reasoned workflow: **branch → plan → test → commit → PR
→ review**. The skills auto-detect your toolchain (package manager, test runner, formatter,
framework) so they work zero-config on a fresh Vite/Next/Laravel project — and let
power users pin exact commands for any other stack via a small override file.

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

## Updating

Editing this repo — or merging PRs into it — does **not** update your installed copy. The
plugin is served from the `jaballer/claude-webdev-skills` GitHub marketplace, so changes have
to reach `main` there first, then get pulled in. From a terminal:

```bash
# 1. Refresh the marketplace from GitHub
claude plugin marketplace update webdev-skills

# 2. Update the plugin to the latest version
claude plugin update webdev@webdev-skills
```

The update applies on the next launch, not live — **restart Claude Code**, then confirm with
`claude plugin list`. You can also manage updates interactively from the `/plugin` menu.

> **Developing locally?** To iterate against your working tree, register the marketplace from a
> path instead: `claude plugin marketplace add /absolute/path/to/claude-webdev-skills`. It reuses
> the `webdev-skills` name, so remove the GitHub-sourced one first
> (`claude plugin marketplace remove webdev-skills`).

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
  "branchPrefixes": ["feature", "fix", "refactor", "docs", "chore", "review"]
}
```

**All supported keys** (pin any subset; the rest is detected):

| Key | Used by | Meaning |
|---|---|---|
| `packageManager`, `install`, `test`, `format`, `lint`, `typecheck`, `dev`, `build` | all command-running skills | The resolved commands |
| `commandPrefix` | all command-running skills | Prepended to **detected** commands only (e.g. `ddev exec`); pinned commands are used verbatim — write them complete, prefix included |
| `migrationStatus` | `qa-review` | Migration-status command, if the stack has one |
| `defaultBranch` | `new-branch`, `sync-main`, `open-pr`, `verify` | Overrides origin/HEAD detection |
| `mergeMethod` | `merge-pr` | `"squash"` / `"merge"` / `"rebase"` — overrides repo-history detection |
| `branchPrefixes` | `new-branch`, `fix-bug`, `open-pr` | Allowed branch name prefixes |
| `coAuthorTrailer` | `commit`, `review-pr` | **Default `false`.** Opt in to an AI co-author commit trailer |
| `prFooter` | `open-pr` | **Default `false`.** Opt in to a "Generated with Claude Code" PR footer |

## Skills (v1.8.0)

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
| `/webdev:watch-pr` | Polls a PR on an interval until it's approved / changes-requested / merged / closed, then notifies you or hands off to `merge-pr`. Configurable interval + on-approval action; silence ≠ approval. |
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

## Which model for which task

These skills run on whatever model your session is set to (`/model`) — a skill can't pick its
own. So the practical move is to **match your session model to the phase of work you're about to
do**, and switch when you change phases. The axis isn't "planning model vs. coding model" —
current Claude models are generalists separated by a **capability / speed / cost** tradeoff. The
question to ask is just: *is this the kind of task where a weaker model quietly gets it wrong?*

| Model tier | Reach for it when | Phases / skills | Why |
|---|---|---|---|
| **Top** (Fable 5 / Mythos) | The task is judgment-heavy, adversarial, or hard to reverse | Root-causing a stubborn bug (`fix-bug`), pre-code planning (`plan-inventory`), reversibility / blast-radius calls (`safe-edit`), hostile self-review + security gate (`commit`, `review-pr`), deep audits (`qa-review`, `post-merge-review`), merge gating (`merge-pr`) | Deepest reasoning. The cost/latency premium earns out only where a subtle wrong call is expensive — a bad root cause, a missed blast radius, a security issue slipping through. |
| **Strong default** (Opus 4.8) | You're actually writing and orchestrating code | The bulk of `new-feature` / `ship-it`, real implementation, `fix-ci` | Excellent coding and orchestration without top-tier latency. Toggle `/fast` for faster output at the same capability. A sane everyday default. |
| **Balanced** (Sonnet 5) | Routine implementation and running the loop | `new-branch`, `sync-main`, `open-pr`, `verify`, `explain-codebase`, `setup`, `watch-pr` | Cheaper and quicker for well-defined steps that don't need frontier reasoning. |
| **Fast / cheap** (Haiku 4.5) | The step is mechanical and deterministic | `detect-stack`, `run-tests` | `detect-stack` is literally a Python script; running a resolved test command needs almost no model judgment. Paying for the top tier here is pure waste. |

**Rules of thumb**

- **Don't run the top tier on everything.** Running Fable 5 through `detect-stack` or a green
  `run-tests` buys nothing but latency and cost — that anti-pattern is what this table exists to
  prevent.
- **Switch by phase, not by skill.** Bump *up* before planning or review; drop *down* for
  mechanical runs. One `/model` change per phase, not per command.
- **`/fast` is the free lunch on Opus** — faster output, same model, no capability drop.

> Model lineup current as of July 2026 (the Claude 5 family plus Opus 4.8 / Haiku 4.5). Treat the
> tiers as stable and swap the names as the lineup changes.

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

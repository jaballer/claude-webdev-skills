---
name: detect-stack
description: >
  Resolves the project's toolchain — package manager, test runner, formatter/linter,
  framework, and dev/run command — so other webdev skills issue the right commands on
  any stack. Auto-detects JS/TS and PHP; every other stack is supported through an
  explicit .claude/webdev.json override. Use at the start of any workflow that needs to
  run tests, format code, install dependencies, or start the dev server. Other webdev
  skills invoke this first. Honors an explicit .claude/webdev.json override before
  falling back to filesystem detection.
---

# Detect Stack

This is the **foundation** skill. Every other `webdev` skill that runs a project command
(`run-tests`, `commit`, `new-feature`, …) resolves the command through this plugin's
scripts rather than hardcoding `npm test` or `phpunit`.

**Supported stacks.** Auto-detection covers **JS/TS** (npm/pnpm/yarn/bun) and **PHP**
(Composer). Any other stack works too — pin its commands in `.claude/webdev.json` and
they're used verbatim. The detector intentionally stays narrow: an undetected stack
falls through to the `gaps` path and asks, rather than guessing a command it can't
stand behind.

## Resolve the stack profile

Run the bundled script in the project root:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack
```

The script:

1. Reads `.claude/webdev.json` at the project root. Any key present there is **authoritative**.
2. Detects whatever is not pinned from the repo files.
3. Applies `commandPrefix` to **detected** commands only.
4. Prints a JSON profile to stdout.

`commandPrefix` is prepended to every detected command — this is how containerized setups
work (e.g. a DDEV project sets `"commandPrefix": "ddev exec"` so a detected `pnpm test`
runs as `ddev exec pnpm test`). **Pinned commands are used verbatim — never apply the
prefix to them.** A pinned command written in `webdev.json` is complete, prefix included.
If a project pins everything, detection is skipped.

```json
{
  "packageManager": "pnpm",
  "install": "pnpm install",
  "test": "pnpm test",
  "format": "pnpm run format",
  "lint": "pnpm run lint",
  "typecheck": "pnpm exec tsc --noEmit",
  "dev": "pnpm dev",
  "build": "pnpm build",
  "commandPrefix": "",
  "branchPrefixes": ["feature", "fix", "refactor", "docs", "chore", "review"]
}
```

## Resolve a single command

For command-running skills, use the companion script to avoid re-deriving commands:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command test
${CLAUDE_PLUGIN_ROOT}/scripts/resolve-command format
```

This prints the resolved command string for that key, with `commandPrefix` applied
when appropriate. **Exit codes let a caller branch instead of guessing:**

| Code | Meaning | Caller action |
|------|---------|---------------|
| `0` | Command resolved (printed to stdout) | run it |
| `2` | `.claude/webdev.json` is invalid (bad JSON or not an object) | abort — fix config |
| `3` | No such command for this stack (legitimately absent) | clean N/A skip for optional gates |
| `4` | Ambiguous package manager (multiple JS lockfiles, not pinned) | abort — pin `packageManager` |

Only exit `3` is a safe skip. `2`/`4` mean the setup is unsafe, so an optional
gate (`format`/`lint`/`build`/`typecheck`/`migrationStatus`) must abort rather than
silently treat it as N/A. A command pinned in `webdev.json` is returned verbatim even
under a `4` ambiguity, since it doesn't depend on the detected manager.

## When detection is ambiguous

If the script returns a non-empty `gaps` array, **state what you found and ask** — don't
run a guessed command. Offer to write the resolved values into `.claude/webdev.json` so
the next run is deterministic.

## Output

Report a concise **stack profile** the caller can act on:

- **Source**: `webdev.json` | `detected` | `mixed` (which keys came from where)
- **Package manager**, **install**
- **Test command**, **format command**, **lint command**, **type-check command** (or N/A)
- **Framework** (+ version if known) · **Migration-status command** (or N/A)
- **Dev command**, **build command**
- **Workspace/package** (monorepos only): which package the profile applies to
- **Command prefix** (if any)
- **Branch prefixes** allowed
- **Gaps / ambiguities**: anything the script couldn't resolve, with a recommended next step (usually: pin it in `webdev.json`)

---
name: detect-stack
description: >
  Resolves the project's toolchain — package manager, test runner, formatter/linter,
  framework, and dev/run command — so other webdev skills issue the right commands on
  any stack (JS/TS, PHP, Python, etc.). Use at the start of any workflow that needs to
  run tests, format code, install dependencies, or start the dev server. Other webdev
  skills invoke this first. Honors an explicit .claude/webdev.json override before
  falling back to filesystem detection.
---

# Detect Stack

This is the **foundation** skill. Every other `webdev` skill that runs a project command
(`run-tests`, `commit`, `new-feature`, …) resolves the command through this plugin's
scripts rather than hardcoding `npm test` or `phpunit`.

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
when appropriate.

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

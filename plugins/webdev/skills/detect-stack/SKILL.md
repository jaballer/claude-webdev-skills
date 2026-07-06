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
(`run-tests`, `commit`, `new-feature`, …) resolves the command through this skill rather
than hardcoding `npm test` or `phpunit`. That is what makes the workflow portable.

## Resolution order — override wins, then detect

### 1. Read the override file (if present)

Look for `.claude/webdev.json` at the project root. Any key present there is **authoritative**
— do not second-guess it with detection. A typical file:

```json
{
  "packageManager": "pnpm",
  "install": "pnpm install",
  "test":    "pnpm test",
  "format":  "pnpm run format",
  "lint":    "pnpm run lint",
  "typecheck": "pnpm exec tsc --noEmit",
  "dev":     "pnpm dev",
  "build":   "pnpm build",
  "commandPrefix": "",
  "branchPrefixes": ["feature", "fix", "refactor", "docs", "chore", "review"]
}
```

`commandPrefix` is prepended to every **detected** command — this is how containerized setups
work (e.g. a DDEV project sets `"commandPrefix": "ddev exec"` so a detected `./vendor/bin/phpunit`
runs as `ddev exec ./vendor/bin/phpunit`). **Pinned commands are used verbatim — never apply the
prefix to them.** A pinned command is written complete, prefix included (as in the example file);
prepending again would produce `ddev exec ddev exec …`. If a project pins everything in
`webdev.json`, detection is skipped entirely.

### 2. Detect anything not pinned

Resolve each unknown by reading the repo. Prefer the strongest signal; if signals conflict,
say so and ask rather than guess.

**Package manager** (lockfile is the strongest signal):

| Signal | Manager | Install | Run-script form |
|---|---|---|---|
| `pnpm-lock.yaml` | pnpm | `pnpm install` | `pnpm run <s>` / `pnpm <s>` |
| `yarn.lock` | yarn | `yarn install` | `yarn <s>` |
| `bun.lock` / `bun.lockb` | bun | `bun install` | `bun run <s>` |
| `package-lock.json` | npm | `npm install` | `npm run <s>` |
| `composer.lock` / `composer.json` | composer | `composer install` | `composer <s>` |
| `poetry.lock` / `[tool.poetry]` in `pyproject.toml` | poetry | `poetry install` | `poetry run <s>` |
| `uv.lock` | uv | `uv sync` | `uv run <s>` |
| `requirements.txt` (only) | pip | `pip install -r requirements.txt` | — |

**Test runner:**
- JS/TS: `package.json` `scripts.test`; else config files (`vitest.config.*`, `jest.config.*`, `playwright.config.*`).
- PHP: `phpunit.xml` / `phpunit.xml.dist` → `./vendor/bin/phpunit`; `pest.php` → `./vendor/bin/pest`.
- Python: `pytest.ini` / `[tool.pytest]` / `tests/` → `pytest`; else `unittest`.

**Formatter / linter:**
- JS/TS: `biome.json` → biome; `.prettierrc*` → prettier; `.eslintrc*` / `eslint.config.*` → eslint.
- PHP: `pint.json` or Laravel present → `./vendor/bin/pint`; `.php-cs-fixer*` → php-cs-fixer.
- Python: `ruff.toml` / `[tool.ruff]` → ruff; `[tool.black]` → black.

**Type-check** (distinct from build — review skills run it in check mode). Run the project's
local compiler, not a global one — bare `tsc` isn't on PATH when TypeScript is a devDependency:
- JS/TS: a `typecheck`/`type-check` script in `package.json` wins; else `tsconfig.json` → the
  manager's exec form (`pnpm exec tsc --noEmit`, `npm exec tsc -- --noEmit`, `yarn tsc --noEmit`;
  Vue: `vue-tsc --noEmit`; Astro: `astro check` — same exec form); else N/A.
- PHP: `phpstan.neon*` → `./vendor/bin/phpstan analyse`; `psalm.xml` → `./vendor/bin/psalm`.
- Python: `[tool.mypy]` / `mypy.ini` → `mypy` via the manager's runner (`poetry run mypy`,
  `uv run mypy`); `pyrightconfig.json` → `pyright` likewise.

**Migration status** (only when the framework has migrations). Same rule — resolve through the
project runner, since bare `manage.py` or a global `prisma` fails outside an activated env:
- Laravel: `php artisan migrate:status` · Django: `python manage.py showmigrations` (via
  `poetry run`/`uv run` when that's the manager) · Rails: `bin/rails db:migrate:status` (the
  app binstub — bare `rails` isn't on PATH when the gem is Bundler-managed; `bundle exec rails
  db:migrate:status` also works) · standalone tools via the manager's exec form
  (`pnpm exec prisma migrate status`; Alembic has no single status command — compare
  `poetry run alembic current` against `alembic heads`, which differ when revisions are
  unapplied) when their config is present. Otherwise N/A.

**Framework** (informs conventions, scaffolding, where files live):
- JS/TS: deps in `package.json` — `next`, `nuxt`, `@remix-run`, `astro`, `svelte`/`@sveltejs/kit`, `vite`, `react`, `vue`, `express`, `@nestjs`.
- PHP: `laravel/framework` → Laravel; `symfony/*` → Symfony.
- Python: `django`, `flask`, `fastapi`.

**Dev / run command:** `scripts.dev` (JS) · `php artisan serve` or a `ddev`/`docker-compose.yml` present (PHP) · `manage.py runserver` (Django). If a `Makefile`/`Taskfile`/`justfile` defines `dev`/`test`/`start`, prefer those — they are the project's intended entry points.

**Monorepo / workspaces:** if `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json`, or a
`workspaces` field in the root `package.json` is present, commands are per-package, not global.
Resolve the profile for the package containing the files in scope (nearest `package.json` up the
tree); if the scope is unclear, list the workspace packages and ask which one applies. Prefer the
repo's task runner over `cd` — via the manager's exec form, since `turbo`/`nx` are usually
devDependencies not on PATH, and scope the run to the package in scope rather than the whole
repo: `pnpm exec turbo run test --filter=<pkg>`, `npm exec nx -- test <project>`,
`pnpm --filter <pkg> test`.

### 3. When detection is ambiguous

If two managers' lockfiles coexist, or no test runner is found, **state what you found and
ask** — don't run a guessed command. Offer to write the resolved values into
`.claude/webdev.json` so the next run is deterministic.

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
- **Gaps / ambiguities**: anything you couldn't resolve, with a recommended next step (usually: pin it in `webdev.json`)

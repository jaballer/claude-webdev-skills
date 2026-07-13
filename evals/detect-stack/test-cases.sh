#!/usr/bin/env bash
# Deterministic, no-API regression suite for the detect-stack script.
#
# Encodes the behaviors verified across PR #32's review rounds: package-manager
# and framework detection, PHP/JS command resolution, the webdev.json override
# path, and the exit-code contract (0 ok / 2 bad config / 3 no-command / 4
# ambiguous manager). Runs in CI on every push/PR — no network, no API key.
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DETECT="$REPO_ROOT/plugins/webdev/scripts/detect-stack"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }

# mk <name> — make a fresh temp project dir and echo its path.
mk() { mktemp -d; }

# assert_key <dir> <key> <expected> — `--key` prints exactly <expected> (exit 0).
assert_key() {
  local out rc
  out=$("$DETECT" --root "$1" --key "$2" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$3" ]; then pass; else
    fail "[$2] expected '$3' (exit 0), got '$out' (exit $rc)"
  fi
}

# assert_exit <dir> <key> <code> — `--key` exits with <code>.
assert_exit() {
  "$DETECT" --root "$1" --key "$2" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$3" ]; then pass; else fail "[$2] expected exit $3, got $rc"; fi
}

# assert_field <dir> <field> <expected> — full profile JSON field equals value.
assert_field() {
  local out val rc
  out=$("$DETECT" --root "$1" 2>/dev/null)
  rc=$?
  val=$(printf '%s' "$out" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$2'))" 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$val" = "$3" ]; then pass; else
    fail "[field $2] expected '$3', got '$val' (exit $rc)"
  fi
}

# assert_profile_exit <dir> <code> — full profile run exits with <code>.
assert_profile_exit() {
  "$DETECT" --root "$1" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$2" ]; then pass; else fail "[profile] expected exit $2, got $rc"; fi
}

# ---- JS / TS ----------------------------------------------------------------

d=$(mk); printf '{"scripts":{"dev":"vite","build":"vite build"},"devDependencies":{"vite":"5","vitest":"1","prettier":"3"}}' >"$d/package.json"
touch "$d/pnpm-lock.yaml" "$d/tsconfig.json" "$d/vitest.config.ts"
assert_key "$d" packageManager pnpm
assert_key "$d" test "pnpm exec vitest --run"
assert_key "$d" dev "pnpm dev"
assert_key "$d" format "pnpm exec prettier --write ."
assert_key "$d" typecheck "pnpm exec tsc --noEmit"

# Vue → vue-tsc (framework-specific typechecker beats generic tsc)
d=$(mk); printf '{"devDependencies":{"vue":"3","vite":"5"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml" "$d/tsconfig.json"
assert_key "$d" typecheck "pnpm exec vue-tsc --noEmit"

# Nuxt → nuxt typecheck before generic tsc
d=$(mk); printf '{"devDependencies":{"nuxt":"3"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml"
assert_key "$d" typecheck "pnpm exec nuxt typecheck"

# Svelte: `check` script wins; without it, svelte-check
d=$(mk); printf '{"scripts":{"check":"svelte-check"},"devDependencies":{"@sveltejs/kit":"2","svelte":"4"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml"
assert_key "$d" typecheck "pnpm check"
d=$(mk); printf '{"devDependencies":{"svelte":"4"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml"
assert_key "$d" typecheck "pnpm exec svelte-check"

# biome.jsonc recognized (not just biome.json)
d=$(mk); printf '{"devDependencies":{"@biomejs/biome":"1"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml" "$d/biome.jsonc"
assert_key "$d" format "pnpm exec biome format --write"
assert_key "$d" lint "pnpm exec biome check"

# Corepack: packageManager field resolves the manager with no lockfile
d=$(mk); printf '{"packageManager":"pnpm@8.6.0","scripts":{"test":"vitest"}}' >"$d/package.json"
assert_key "$d" packageManager pnpm
assert_key "$d" install "pnpm install"

# Yarn Classic uses `yarn run`, not `yarn exec`
d=$(mk); printf '{"devDependencies":{"vitest":"1"}}' >"$d/package.json"; touch "$d/yarn.lock" "$d/vitest.config.ts"
assert_key "$d" test "yarn run vitest --run"

# dev falls back to a `start` script (Express/CRA)
d=$(mk); printf '{"scripts":{"start":"node server.js"}}' >"$d/package.json"; touch "$d/package-lock.json"
assert_key "$d" dev "npm run start"

# ---- PHP --------------------------------------------------------------------

# Laravel + Pest → pest (Pest detected before PHPUnit)
d=$(mk); printf '{"require":{"laravel/framework":"11","pestphp/pest":"2"}}' >"$d/composer.json"; touch "$d/composer.lock" "$d/phpunit.xml"; mkdir -p "$d/tests"; printf '<?php' >"$d/tests/Pest.php"
assert_key "$d" test "./vendor/bin/pest"
assert_key "$d" framework laravel

# composer scripts win for test/format/lint/dev/build
d=$(mk); printf '{"require":{"laravel/framework":"11"},"scripts":{"test":"a","format":"b","lint":"c","dev":"d","build":"e"}}' >"$d/composer.json"; touch "$d/composer.lock"
assert_key "$d" test "composer test"
assert_key "$d" format "composer format"
assert_key "$d" lint "composer lint"
assert_key "$d" dev "composer dev"
assert_key "$d" build "composer build"

# Pint requires real evidence: laravel/framework alone is NOT enough
d=$(mk); printf '{"require":{"laravel/framework":"11"}}' >"$d/composer.json"; touch "$d/composer.lock"
assert_exit "$d" format 3
d=$(mk); printf '{"require-dev":{"laravel/pint":"1"}}' >"$d/composer.json"; touch "$d/composer.lock"
assert_key "$d" format "./vendor/bin/pint"

# .php-cs-fixer.cache (generated) is NOT treated as config; the real config is
d=$(mk); printf '{"require":{"symfony/console":"6"}}' >"$d/composer.json"; touch "$d/composer.lock" "$d/.php-cs-fixer.cache"
assert_exit "$d" format 3
d=$(mk); printf '{"require":{"symfony/console":"6"}}' >"$d/composer.json"; touch "$d/composer.lock" "$d/.php-cs-fixer.dist.php"
assert_key "$d" format "./vendor/bin/php-cs-fixer fix"

# Laravel with a frontend build resolves via the JS lockfile's manager
d=$(mk); printf '{"require":{"laravel/framework":"11"}}' >"$d/composer.json"; touch "$d/composer.lock"; printf '{"scripts":{"build":"vite build"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml"
assert_key "$d" build "pnpm build"

# ---- Override path + exit-code contract -------------------------------------

# Unsupported stack (Python) falls through to unknown, not a crash
d=$(mk); touch "$d/poetry.lock"; printf '[tool.poetry.dependencies]\ndjango="5"\n' >"$d/pyproject.toml"
assert_field "$d" packageManager unknown

# No command for a stack → exit 3 (clean/skippable)
d=$(mk); touch "$d/pnpm-lock.yaml"; printf '{}' >"$d/package.json"
assert_exit "$d" test 3

# Multiple JS lockfiles → ambiguous → exit 4 (unsafe)
d=$(mk); printf '{"scripts":{"test":"vitest"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml" "$d/package-lock.json"
assert_exit "$d" test 4

# ...but a pinned command is returned verbatim even under ambiguity
d=$(mk); mkdir -p "$d/.claude"; printf '{"scripts":{"test":"vitest"}}' >"$d/package.json"; touch "$d/pnpm-lock.yaml" "$d/package-lock.json"; printf '{"test":"make test"}' >"$d/.claude/webdev.json"
assert_key "$d" test "make test"

# A pinned custom stack (no packageManager) does not report a pm gap
d=$(mk); mkdir -p "$d/.claude"; printf '{"test":"make test","format":"make fmt"}' >"$d/.claude/webdev.json"
assert_key "$d" test "make test"

# Invalid webdev.json (bad JSON, or valid-but-not-an-object) → exit 2
d=$(mk); mkdir -p "$d/.claude"; printf '{ not json' >"$d/.claude/webdev.json"
assert_profile_exit "$d" 2
d=$(mk); mkdir -p "$d/.claude"; printf '["test"]' >"$d/.claude/webdev.json"
assert_profile_exit "$d" 2

# -----------------------------------------------------------------------------
echo "----------------------------------------"
echo "detect-stack test-cases: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1

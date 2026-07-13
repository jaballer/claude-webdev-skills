#!/bin/sh
# Manual smoke test for the detect-stack script when `claude plugin eval` is unavailable.
# Creates a temp sample repo, runs scripts/detect-stack, and checks the JSON profile.
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DETECT_STACK="$REPO_ROOT/plugins/webdev/scripts/detect-stack"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

cat > package.json <<'EOF'
{
  "name": "eval-detect-stack",
  "private": true,
  "version": "0.0.1",
  "scripts": {
    "dev": "vite",
    "build": "vite build"
  },
  "devDependencies": {
    "vite": "^5.0.0",
    "vitest": "^1.0.0",
    "prettier": "^3.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

touch pnpm-lock.yaml tsconfig.json .prettierrc vitest.config.ts

OUTPUT=$("$DETECT_STACK")

echo "Profile:"
echo "$OUTPUT"

check() {
  field="$1"
  expected="$2"
  value=$(echo "$OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['$field'])")
  if [ "$value" != "$expected" ]; then
    echo "FAIL: $field expected '$expected' got '$value'" >&2
    exit 1
  fi
  echo "PASS: $field = $value"
}

check packageManager pnpm
check test "pnpm exec vitest --run"
check dev "pnpm dev"
check build "pnpm build"
check format "pnpm exec prettier --write ."
check typecheck "pnpm exec tsc --noEmit"

echo "All checks passed."

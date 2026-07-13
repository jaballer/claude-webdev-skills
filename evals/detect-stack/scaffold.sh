#!/bin/sh
# Scaffold a minimal Vite + pnpm + TypeScript + Vitest project for the eval.
set -e

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

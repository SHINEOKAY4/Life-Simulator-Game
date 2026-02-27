---
title: Contributor Setup
---

# Contributor Setup

This guide covers a minimal local setup for contributing code, tests, and docs.

## Prerequisites

- `git` (latest stable)
- `node` and `npm` (for docs)
- Luau-compatible test runner tooling used by this repo (`busted` via LuaRocks in CI/local scripts)

## Clone + Branch

```bash
git clone <repo-url>
cd Life-Simulator-Game
git checkout -b <feature-branch>
```

## Install Docs Dependencies

```bash
npm ci --prefix docs
```

## Common Dev Commands

```bash
# Run Lua/Luau specs (wrapper script)
./run_tests.sh

# Regenerate docs content from source
npm run generate --prefix docs

# Start docs dev server
npm run start --prefix docs

# Build docs site (CI-equivalent for docs)
npm run build --prefix docs
```

## Typical Change Workflow

1. Implement service/module changes under `src/`.
2. Add or update specs under `Tests/Specs/`.
3. Update docs in `docs/content/` if behavior or APIs changed.
4. Run tests and docs build locally.
5. Commit with a focused message and open a PR.

## Testing Expectations

- Prefer behavior-focused tests over "exists" stubs.
- Cover edge cases on input validation, timing boundaries, and reward/distribution failures.
- Keep fixtures minimal and deterministic.

## Docs Expectations

- Keep player-facing system behavior documented at a high level.
- Keep API/architecture details generated from source where possible.
- Add manual pages only for context that code generation cannot express well.

## Troubleshooting

- If `busted` is missing: ensure LuaRocks bin path is on `PATH` (the repo script expects `$HOME/.luarocks/bin`).
- If docs links break: run `npm run generate --prefix docs` before `npm run build --prefix docs`.

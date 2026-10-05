# Resolve The CLI Relative To The Installed Bundle And Harden The Pack Test

## Purpose and scope

Fixes findings 8xEp and tT72 from the Phase 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop.

- 8xEp (critical): the built Node bundles inline a bare `__dirname` as a build-time absolute path, so an installed package cannot find its own `bin/md2x`.
- tT72: `scripts/test-pack.sh` falls back to `npx --yes -p typescript tsc`, which fetches an unpinned package at release time.

## Requirements

1. `dist/md2x.mjs` and `dist/md2x.cjs` locate `bin/md2x` relative to their own installed location (`../bin/md2x` from `dist/`), never a build-time absolute path. No bare `__dirname` that `bun build` inlines may reach the bundles. Use `import.meta.url` for ESM and a CJS-specific path, or a per-format `--define`/shim in the Makefile.
2. `src/node/md2x.js` still runs unbundled in tests (`src/node/md2x.js` resolves `../../bin/md2x`).
3. `scripts/test-pack.sh` fails if the installed package resolves the CLI from the repo tree. The consumer checks (ESM import, CJS require) run with the repo `bin/` unavailable, or assert that the resolved path is under `node_modules/@liquid-labs/md2x/bin/md2x`.
4. `scripts/test-pack.sh` no longer runs `npx --yes -p typescript tsc`. It uses a lockfile-pinned `typescript` devDependency (`node_modules/.bin/tsc`), or drops the network fallback in favor of the existing syntactic check.

## Validation

1. `grep` finds no absolute build-path string and no `var __dirname =` in `dist/md2x.mjs` or `dist/md2x.cjs` after `make all`.
2. `make test-pack` passes. Temporarily reintroducing the bare-`__dirname` resolution makes it fail; record that negative check in the report.
3. `grep -n 'npx' scripts/test-pack.sh` returns no network-fetching `tsc` invocation, and the TypeScript type check still runs.
4. `make qa` is green.

## References

- Finding 8xEp, in this plan's `plan/findings.yaml`.
- Finding tT72, in this plan's `plan/findings.yaml`.
- Files: `src/node/md2x.js`, `Makefile`, `scripts/test-pack.sh`, `package.json`, `bun.lock`.

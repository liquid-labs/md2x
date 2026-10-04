# Fail Closed When Dev Tools Are Not Installed

## Purpose and scope

Remediates finding 65wX: the Makefile runs bash-rollup, bats and eslint through `bunx`, which fetches an unpinned latest version from the registry when `node_modules` is missing or incomplete, bypassing `bun.lock`; `scripts/release.sh` runs `bun pm version` (whose `preversion` hook runs `make all && make qa`) with no install pre-flight. This task makes those invocations fail closed instead of fetching, and adds a frozen-install pre-flight to the release script. The work targets the plan branch `plan/bun-migration` and lands through the ordinary per-task loop.

## Requirements

1. The Makefile's bash-rollup, bats and eslint invocations (BASH_ROLLUP, BATS, and the lint and lint-fix targets) resolve only to the locally installed, lockfile-pinned binaries. When node_modules is missing, they fail with an error rather than fetching from the registry. Use node_modules/.bin/<tool>, or a bunx flag that this bun version (1.3.x) actually supports and that verifiably disables the fetch.
2. scripts/release.sh runs `bun install --frozen-lockfile` (or an equivalent frozen install) during pre-flight, before `bun pm version`. A lockfile/package.json mismatch then aborts the release.
3. No change in behavior when deps are installed: make all, make test, make lint, make lint-fix and make qa still pass.
4. Update AGENTS.md or RELEASING.md if either describes how the tools are invoked or what release pre-flight does.

## Validation

1. With node_modules moved aside, `make lint` and `make test-cli` exit non-zero, and no registry fetch happens (no download output, nothing new in the bun cache). Restore node_modules afterwards.
2. `bash -n scripts/release.sh` passes. Reading the script shows the frozen install runs before `bun pm version`.
3. After `bun install --frozen-lockfile`, make clean all test lint qa all exit 0, and `make lint-fix` leaves src unchanged.

## References

- Finding 65wX in this plan's `plan/findings.yaml`.

# Force Clean Release Install And Add Missing node_modules Guard

## Purpose and scope

Remediates findings tnIj and VtSc. tnIj: `scripts/release.sh` runs `bun install --frozen-lockfile` before `bun pm version`, but an existing stale or tampered `node_modules` that already matches versions is reused by the preversion `make all && make qa`. VtSc: with `node_modules` absent, make targets fail with a raw "No such file or directory" that never says to run `bun install`. The work targets the plan branch `plan/bun-migration` and lands through the ordinary per-task loop. `src/node/md2x.js` must not be touched.

## Requirements

1. scripts/release.sh pre-flight gives the preversion hook a node_modules installed fresh from bun.lock, and does not reuse an existing tree. Do this by removing node_modules before `bun install --frozen-lockfile`, or by using a bun 1.3.x flag combination (e.g. `--frozen-lockfile --force`) after verifying it reinstalls every package and still refuses a lockfile mismatch. The frozen install still runs before `bun pm version`, and a lockfile/package.json mismatch still aborts.
2. RELEASING.md's pre-flight description says the release does a clean or forced frozen install.
3. When node_modules/.bin (or the specific tool) is missing, make targets that use BASH_ROLLUP, BATS or ESLINT (all, test-cli, lint, lint-fix, smoke-test) fail with a clear message telling the user to run `bun install`. They still fail closed (non-zero exit, no bunx or registry fetch).
4. Nothing changes when deps are installed: make all, test, lint, lint-fix and qa still pass. src/node/md2x.js is not touched.

## Validation

1. `bash -n scripts/release.sh` passes. Reading the script shows the clean/forced frozen install before `bun pm version`. If a flag is used instead of rm, show evidence (log under .flow/validation-logs/) that it reinstalls every package.
2. With node_modules moved aside, `make lint` and `make test-cli` exit non-zero and print the `bun install` hint, with no download output. Restore node_modules afterwards.
3. After `bun install --frozen-lockfile`, `make clean all test lint qa` exits 0 and `make lint-fix` leaves src unchanged.

## References

- Finding tnIj in this plan's `plan/findings.yaml`.
- Finding VtSc in this plan's `plan/findings.yaml`.

## Status

Succeeded, 2026-10-04. Release pre-flight now runs `rm -rf node_modules` before `bun install --frozen-lockfile` (scripts/release.sh); RELEASING.md updated; Makefile gains a `$(BIN_DIR)/%` guard rule used as an order-only prerequisite of the bash-rollup, bats and eslint consumers (fails closed with a `bun install` hint). Validation: `bash -n` ok; with node_modules absent `make lint`/`test-cli`/`smoke-test`/`lint-fix` exit 2 with the hint and no download; after a frozen install `make clean all test lint qa` exits 0 and `make lint-fix` left src unchanged. Files: Makefile, scripts/release.sh, RELEASING.md.

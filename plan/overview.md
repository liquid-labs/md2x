# Bun Migration and catalyst-scripts Removal

## Purpose and scope

Remove the deprecated `@liquid-labs/catalyst-scripts` devDependency from md2x and make bun the standard dev runtime and install agent in place of npm. Scope: `package.json`, lockfile, `Makefile`, `scripts/release.sh`, `src/node` build/test/lint tooling, `.gitignore`, and docs (`AGENTS.md`, `README.md`, `RELEASING.md`, `docs/architecture.md`, `docs/project-structure.md`, `docs/md2x-spec.md`). Out of scope: the bash CLI sources under `src/cli/`, `src/node/md2x.js` behavior, and the npm registry itself (publish stays on npm; see below).

Hard constraints:

- No CLI behavior change; `src/node/md2x.js` is not edited (including its `npx md2x` command string, which the tests assert and which is consumer-facing runtime behavior).
- The `dist/md2x.js` export surface is unchanged (CJS, `shelljs` external, `main` in `package.json`).
- The bats CLI tests (`make test-cli`, depends on `all`) keep passing.

## Current status

Planned; not started. Prerequisite: bun is installed locally (`bun --version` printed 1.3.14 during planning; each task re-verifies and halts if absent). Node must remain available for bun-run tools whose shebang is `#!/usr/bin/env node` (bash-rollup, bats).

## Overview

Background research: catalyst-scripts assessment (`.flow/catalyst-scripts-assessment.md` in the main project root, untracked) (read-only; assumed npm/jest, adapted here to bun). Single phase, `bun-migration`, five tasks executed sequentially (they all touch `package.json` and/or `Makefile`, so they are not parallel-eligible; 004 and 005 run last):

1. `001-bun-install-and-build` — capture baselines, remove catalyst-scripts, delete `package-lock.json`, generate `bun.lock`, point Makefile tool invocations at `bunx`, replace `catalyst-scripts build` with `bun build` (CJS, shelljs external), drop `JS_SRC`.
2. `002-port-tests-to-bun-test` — port `src/node/md2x.test.js` from jest to `bun:test`, `test-node` becomes `bun test`, drop pretest/`test-staging`.
3. `003-direct-eslint` — direct eslint with a repo-owned config preserving the catalyst custom rules; `lint`/`lint-fix` targets; drop `JS_LINT_TARGET`.
4. `004-release-and-docs` — `release.sh`, `RELEASING.md`, `AGENTS.md`, `README.md`, `docs/*`, `.gitignore`.
5. `005-end-to-end-verification` — full clean verification run, audit and pack comparison.

Decisions made at planning time:

- `bun build --target=node --format=cjs --packages=external` is tried first; fall back to esbuild only if the export surface cannot be matched.
- npm remains only for registry operations in `release.sh` (`npm whoami`, `npm view`, `npm publish`), because bun's publish flow does not match the interactive OTP prompt contract documented in `RELEASING.md`. The task verifies whether `bun pm version` and `bun pm pack` can replace `npm version`/`npm pack`, and uses them only if they run the `preversion` hook and behave identically in a dry run.
- The `scripts` entries in `package.json` (`build`, `test`, `preversion`) keep delegating to `make`.

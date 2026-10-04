# Plan Summary: bun-migration

## What was planned and why

Remove the deprecated `@liquid-labs/catalyst-scripts` devDependency from md2x and make bun the standard dev runtime and install agent in place of npm. Scope: `package.json`, lockfile, `Makefile`, `scripts/release.sh`, `src/node` build/test/lint tooling, `.gitignore`, and docs (`AGENTS.md`, `README.md`, `RELEASING.md`, `docs/architecture.md`, `docs/project-structure.md`, `docs/md2x-spec.md`). Out of scope: the bash CLI sources under `src/cli/`, `src/node/md2x.js` behavior, and the npm registry itself (publish stays on npm; see below).

Hard constraints:

- No CLI behavior change; `src/node/md2x.js` is not edited (including its `npx md2x` command string, which the tests assert and which is consumer-facing runtime behavior).
- The `dist/md2x.js` export surface is unchanged (CJS, `shelljs` external, `main` in `package.json`).
- The bats CLI tests (`make test-cli`, depends on `all`) keep passing.

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

## What shipped

### Phase 01 — Bun Migration and catalyst-scripts Removal

1. **Switch Install to Bun and Replace the Node Build** (`001-bun-install-and-build.md`, tier `sonnet-med`) — Removed catalyst-scripts and package-lock.json, generated text bun.lock, moved Makefile to bunx plus bun build (cjs, node target, external packages, inline sourcemap). Export surface matches baseline, test-cli 144/144, bun audit clean. test-node/lint/lint-fix still reference removed CATALYST_SCRIPTS until tasks 002/003.
   Commit `144ad26`, merged at `6112f49f7dba654ead0d53969ac9d53539be8223`.

2. **Port src/node Tests to bun:test** (`002-port-tests-to-bun-test.md`, tier `sonnet-med`) — Ported md2x.test.js to bun:test with a pre-import mock.module and dynamic imports; test-node now runs bun test with coverage; test-staging remnants removed. 24 tests and bats suite pass; mock sanity check confirmed.
   Commit `686ee6f`, merged at `54ab57c103012fdbbe8162884b20374ae477468d`.

3. **Replace catalyst-scripts Lint with Direct ESLint** (`003-direct-eslint.md`, tier `sonnet-med`) — Replaced catalyst-scripts lint with direct ESLint 9 using neostandard, import-x, and catalyst custom rules ported to @stylistic (eslint.config.mjs; .mjs because package.json has no type field). Makefile lint/lint-fix use bunx eslint. make qa passes with no source edits.
   Commit `24cc238`, merged at `17935b3d810ba2ab998756953faa7ec02f7c366c`.

4. **Update release.sh, RELEASING.md, and Project Docs for Bun** (`004-release-and-docs.md`, tier `sonnet-med`) — Release script and project docs moved to bun. release.sh uses bun pm version (runs preversion; tested in scratch copy) and bun pm pack; handles unchanged bun.lock via revert_bump helper. npm retained for whoami/view/publish (OTP prompt) as documented in RELEASING.md - needs user confirmation. Full release.sh --dry-run not run (needs main branch + npm/gh login).
   Commit `11fe130`, merged at `a75c5c25cd87e842a2078c1d64d434fce344e46c`.

5. **End-to-End Verification of the Bun Migration** (`005-end-to-end-verification.md`, tier `sonnet-low`) — Verification only: all 8 acceptance checks passed (frozen bun install, make clean/all/test/lint/qa, export keys match baseline, bun audit clean vs 34 baseline findings, bun pm pack file list matches baseline, no stale-term hits).
   Commit `cba7cb7`, merged at `b5528c21b228df6df44abc7eaaaa32abffacd436`.

### Phase 02 — Remediation Round 1

1. **Fail Closed When Dev Tools Are Not Installed** (`001-harden-bunx-tool-resolution.md`, tier `sonnet-med`) — Dev tools (bash-rollup, bats, eslint) now resolve only to lockfile-pinned node_modules/.bin binaries, so a missing node_modules fails closed instead of fetching from the registry; release.sh runs bun install --frozen-lockfile in pre-flight before the version bump. Docs updated.
   Commit `b839864`, merged at `7e38d059851a0df0b6bf4eb83fa6cc1216c22936`.

2. **Drop Unused Stylistic DevDependency And Make Coverage Output Match Docs** (`002-tooling-declared-deps-and-coverage-output.md`, tier `sonnet-low`) — Dropped the unused @stylistic/eslint-plugin devDependency (bun.lock keeps only neostandard's nested copy) and added --coverage-reporter=lcov to make test-node so coverage/ is produced as AGENTS.md describes. Lint behavior unchanged.
   Commit `d17e97e`, merged at `71df622a9c53cb311ec8ba9c2176dc291d258e01`.

### Phase 03 — Remediation Round 2

1. **Force Clean Release Install And Add Missing node_modules Guard** (`001-install-state-guards.md`, tier `sonnet-med`) — Release pre-flight now removes node_modules before bun install --frozen-lockfile (before bun pm version). Makefile adds a $(BIN_DIR)/% pattern rule as an order-only prerequisite so targets fail closed with a 'run bun install' hint when a dev tool is missing. src/node/md2x.js untouched.
   Commit `ca6a28c`, merged at `6771d289f579acdd28e64527317d43bc84f22deb`.

## Key decisions

_No `## Why this shape` section is recorded in `plan/overview.md`, so this plan's cross-task rationale was never written down. Per-task outcomes are under "What shipped" above._

## Findings

- **`Iud2`** — **Bun blocked one postinstall script during 'bu** — dismissed — 2026-10-04 — reason: Not actionable: blocked postinstall is most likely unrs-resolver via eslint-plugin-import-x; native bindings arrive via optionalDependencies, lint/qa/frozen install pass without it, and leaving it blocked is the safe default (do not add trustedDependencies).

- **`5VxP`** — **Task 003's grep check references eslint.confi** — dismissed — 2026-10-04 — reason: Stale: task 003 is complete and its outcome already records the eslint.config.mjs naming; the grep line is a one-time validation in a finished task and task 005's stale-term grep passed.

- **`65wX`** — **bunx may fetch unpinned tools if no install** — fixed — ref: `phase-02-remediation-01/001-harden-bunx-tool-resolution.md` — 2026-10-04

- **`DyR1`** — **Unused @stylistic devDep in package.json** — fixed — ref: `phase-02-remediation-01/002-tooling-declared-deps-and-coverage-output.md` — 2026-10-04

- **`dhr8`** — **Docs claim coverage/ dir bun test lacks** — fixed — ref: `phase-02-remediation-01/002-tooling-declared-deps-and-coverage-output.md` — 2026-10-04

- **`ya0J`** — **src/node/md2x.js shells out via unpinned npx** — promoted — ref: `ya0J` — 2026-10-04

- **`tnIj`** — **Release may use stale node_modules** — fixed — ref: `phase-03-remediation-02/001-install-state-guards.md` — 2026-10-04

- **`VtSc`** — **Missing node_modules error lacks bun install** — fixed — ref: `phase-03-remediation-02/001-install-state-guards.md` — 2026-10-04

- **`L6HU`** — **release.sh --dry-run wipes node_modules** — dismissed — 2026-10-04 — reason: By design: dry-run reaches bun pm version, whose preversion hook (make all && make qa) needs the dev tools, so it needs the same fresh frozen install as a real release; skipping it would test a different tree. Failed install fails closed via the Makefile guard.

## Remediation

- Rounds used: 2 (resolved max_rounds: 3).
- Remediation tasks added: 3 (resolved max_added_tasks: 10).
- Remediation phases:
  - `remediation-01` — 2 task(s)
  - `remediation-02` — 1 task(s)
- Security review required: yes (at least one remediation phase carries `security_review: required`).

## Final Task State

# TODO

## Purpose and scope

Tracking document for the active plan.

## Tasks

### Phase 01 — Bun Migration and catalyst-scripts Removal

- [x] [001-bun-install-and-build.md](./phase-01-bun-migration/001-bun-install-and-build.md) — tier `sonnet-med` · branch `plan/bun-migration-01-001` · commit `144ad26` · merge `6112f49f7dba654ead0d53969ac9d53539be8223`
- [x] [002-port-tests-to-bun-test.md](./phase-01-bun-migration/002-port-tests-to-bun-test.md) — tier `sonnet-med` · branch `plan/bun-migration-01-002` · commit `686ee6f` · merge `54ab57c103012fdbbe8162884b20374ae477468d`
- [x] [003-direct-eslint.md](./phase-01-bun-migration/003-direct-eslint.md) — tier `sonnet-med` · branch `plan/bun-migration-01-003` · commit `24cc238` · merge `17935b3d810ba2ab998756953faa7ec02f7c366c`
- [x] [004-release-and-docs.md](./phase-01-bun-migration/004-release-and-docs.md) — tier `sonnet-med` · branch `plan/bun-migration-01-004` · commit `11fe130` · merge `a75c5c25cd87e842a2078c1d64d434fce344e46c`
- [x] [005-end-to-end-verification.md](./phase-01-bun-migration/005-end-to-end-verification.md) — tier `sonnet-low` · branch `plan/bun-migration-01-005` · commit `cba7cb7` · merge `b5528c21b228df6df44abc7eaaaa32abffacd436`

### Phase 02 — Remediation Round 1

- [x] [001-harden-bunx-tool-resolution.md](./phase-02-remediation-01/001-harden-bunx-tool-resolution.md) — tier `sonnet-med` · branch `plan/bun-migration-02-001` · commit `b839864` · merge `7e38d059851a0df0b6bf4eb83fa6cc1216c22936`
- [x] [002-tooling-declared-deps-and-coverage-output.md](./phase-02-remediation-01/002-tooling-declared-deps-and-coverage-output.md) — tier `sonnet-low` · branch `plan/bun-migration-02-002` · commit `d17e97e` · merge `71df622a9c53cb311ec8ba9c2176dc291d258e01`

### Phase 03 — Remediation Round 2

- [x] [001-install-state-guards.md](./phase-03-remediation-02/001-install-state-guards.md) — tier `sonnet-med` · branch `plan/bun-migration-03-001` · commit `ca6a28c` · merge `6771d289f579acdd28e64527317d43bc84f22deb`

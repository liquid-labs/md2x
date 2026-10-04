# Port src/node Tests to bun:test

## Purpose and scope

Migrate `src/node/md2x.test.js` (263 lines, `jest.mock('shelljs', ...)`, `jest.fn`, `jest.spyOn`, `jest.clearAllMocks`) to bun's built-in runner so jest, babel-jest and babel are not needed. Files: `src/node/md2x.test.js`, `Makefile` (`test-node`), `.gitignore`, and `test-staging/` removal. Depends on task 001 (bun install in place).

## Requirements

1. Verify `bun --version`; halt if absent.
2. In the test, `import { afterEach, beforeEach, describe, expect, jest, mock, spyOn, test } from 'bun:test'` as needed (bun provides a `jest` compat object with `jest.fn`, `jest.clearAllMocks`, `jest.spyOn`; prefer these for a minimal diff where they work, otherwise use `mock`/`spyOn`). Remove the `/* global ... jest */` header.
3. Mocking: `jest.mock` is hoisted by babel under jest; bun does not hoist static imports above `mock.module`. Call `mock.module('shelljs', () => ({ default : { config : {}, exec : jest.fn(), tempdir : ..., mkdir, rm, ShellString } }))` BEFORE loading `./md2x`, and load the module under test with a top-level `await import('./md2x')` (and import the mocked `shelljs` default the same way, after the mock). Verify whether the `__esModule : true` wrapper is still needed for the default-import interop under bun and keep only what is necessary. Update the explanatory comment to describe the bun mechanism. Keep the lint style (stroustrup braces, aligned colons, no function-paren space) since task 003 will lint this file.
4. All existing test cases and assertions are preserved one-for-one (same names, same expectations); no coverage regression. Confirm mock state is reset between tests (`jest.clearAllMocks` or `mockClear` on each mock).
5. Makefile `test-node`: replace both catalyst lines with a single `bun test ./src/node --coverage` (coverage text reporter acceptable; add `--coverage-reporter=text` and `--coverage-dir=coverage` if desired so `coverage/` stays gitignored output). Ensure the test file is not picked up by the `bun build` input (`index.js` only imports `md2x.js`, so it is not).
6. Delete the `test-staging` entry from `.gitignore`; delete the local `test-staging/` directory if present; remove the commented-out `NODE_TEST_*` lines in the Makefile.
7. Remove nothing else (eslint stays in task 003). If jest/babel packages were direct devDependencies (they should not be after 001), confirm they are absent from `package.json`.

## Validation

- `bun test ./src/node` passes with the same number of tests as before (compare against `grep -c "test(" ` in the original file via git: `git show HEAD:src/node/md2x.test.js`).
- `make test-node` passes; `make test` (cli + node) passes.
- `ls test-staging` fails (gone); `grep -rn "jest\|babel\|test-staging\|pretest" Makefile package.json .gitignore src` returns nothing, except the unavoidable `jest` import from `bun:test` if used.
- Sanity check that the mock really bites: temporarily change one asserted command string in the test, confirm failure, then revert.

## Status

- Outcome: succeeded (2026-10-04).
- Validation: `bun test ./src/node` 24 pass / 0 fail; `make test-node` and `make test` pass; mock sanity check (altered an asserted command string) produced 1 failure, then reverted; `test-staging` absent; only remaining `jest` references are the `bun:test` import and `jest.fn`/`jest.spyOn` usages.
- Files: `src/node/md2x.test.js`, `Makefile`, `.gitignore`.
- Decisions: the `__esModule : true` wrapper was dropped (not needed under bun); `afterEach` retained because the test file uses it.

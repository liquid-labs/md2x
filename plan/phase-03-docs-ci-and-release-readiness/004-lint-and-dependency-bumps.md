# Lint And Dependency Bumps

## Purpose and scope

Make `eslint .` pass, extend `make lint` to cover the repository's JS and MJS files, and adopt ESLint 10 if it is compatible. Covers audit item R10. Touches `eslint.config.mjs`, the `Makefile` lint targets, `package.json` (devDependencies only), `bun.lock`, and any JS or MJS files that currently fail lint.

This task starts the serial `package.json` / `bun.lock` / `Makefile` chain. [Package metadata](./005-package-metadata-and-pack-verification.md) depends on it, and the [spec and AGENTS.md update](./008-spec-agents-and-structure-docs.md) follows it.

## Requirements

- Run `bun run eslint .` (or `node_modules/.bin/eslint .`) on the merged Phase 1 and 2 code and record the failures. Fix them in code or config; do not blanket-disable rules. Any inline disable needs a one-line justification.
- Extend the `Makefile` `lint` and `lint-fix` recipes from `$(NODE_SRC)` to the whole repository's JS and MJS files (equivalent to `eslint .`, honoring the config's `ignores`). The `ignores` list must still exclude `dist/**`, `coverage/**`, `node_modules/**`, `bin/**`, and `worktrees/**` and `plan/**` if present.
- Try upgrading `eslint` to 10. Check peer-dependency compatibility of `neostandard` and `eslint-plugin-import-x` first (`bun info`, release notes). Adopt ESLint 10 only if `bun install` resolves cleanly with no peer warnings that break lint and `eslint .` is clean. Otherwise stay on 9 and say why in the report. Also bump other safe devDependencies if a plain `bun update` of them keeps `make qa` green; avoid unrelated churn.
- Do not touch `dependencies`, `files`, `exports`, or metadata fields; those belong to Phase 2 and the next task.
- Commit `bun.lock` changes with `package.json`. Use `bun install --frozen-lockfile` after the change to confirm the lockfile is consistent.

## Validation

- `node_modules/.bin/eslint .` exits 0.
- `make lint` exits 0 and its recipe covers the whole repo (inspect the Makefile; introduce a deliberate lint error in a scratch MJS file outside `src/node`, confirm `make lint` fails, and remove it).
- `bun install --frozen-lockfile` succeeds.
- `make qa` passes, and the bats suite also passes under the bash 3.2 override where `/bin/bash` is 3.x.
- `git diff --stat` shows only the files named in scope.

## Metadata

architectural_impact: false

## Assumptions

- Phase 2 replaced `shelljs`, so the dependency list is already final; this task must not re-add it.
- The `Makefile` and `package.json` have been modified by Phase 2; re-read the current versions before editing.

## References

- [Audit coverage](../notes/audit-coverage.md): row R10.
- [Sequencing and file ownership](../notes/sequencing-and-file-ownership.md)

## Status

Succeeded (2026-10-05). `eslint .` was failing only on `eslint.config.mjs` key-spacing (20 errors, fixed with `--fix`). `make lint` / `make lint-fix` now run `eslint .`; ignores gained `worktrees/**`, `plan/**`, `.flow/**`. ESLint stays on 9: `neostandard@0.13.0` (latest) peers `eslint ^9.0.0`, so 10 is incompatible. `bun outdated` shows no other updates, so `package.json`/`bun.lock` are unchanged. The shelljs bump item is superseded (already removed). Validation: eslint, make lint (negative test fails as expected), frozen install, make qa, make test-pack, and bash 3.2 test-cli all pass. Files: `eslint.config.mjs`, `Makefile`.

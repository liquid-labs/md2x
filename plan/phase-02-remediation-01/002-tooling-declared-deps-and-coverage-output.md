# Drop Unused Stylistic DevDependency And Make Coverage Output Match Docs

## Purpose and scope

Remediates findings DyR1 and dhr8. DyR1: package.json declares `@stylistic/eslint-plugin ^5.10.0` but eslint.config.mjs never imports it; the `@stylistic/*` rules come from neostandard's bundled copy (2.11.0), so the declared version is not the one that runs. dhr8: AGENTS.md says `make test-node` writes a gitignored `coverage/` directory, but bun's `--coverage-dir` only applies to the lcov reporter, so with the text reporter alone none is produced. The work targets the plan branch `plan/bun-migration` and lands through the ordinary per-task loop.

## Requirements

1. Remove `@stylistic/eslint-plugin` from package.json devDependencies and regenerate bun.lock with `bun install`. bun.lock keeps only the neostandard-nested @stylistic entry.
2. Lint behavior is unchanged: the @stylistic/* rules in eslint.config.mjs still resolve and still enforce.
3. Make `make test-node` produce the coverage/ directory that AGENTS.md:24 describes. Add `--coverage-reporter=lcov` alongside the existing text reporter in the Makefile test-node recipe, so the console text report stays.
4. If bun does not write coverage/ even with lcov, reword AGENTS.md:24 and :66 to match what actually happens instead. docs/project-structure.md has no such claim and needs no change.

## Validation

1. `grep -n stylistic package.json` returns nothing. bun.lock has no top-level @stylistic/eslint-plugin@5.x entry. `bun install --frozen-lockfile` succeeds.
2. `make lint` exits 0 and `make lint-fix` leaves src unchanged. A scratch file that breaks @stylistic/key-spacing or brace-style is still flagged (delete it afterwards).
3. After `rm -rf coverage && make test-node`, coverage/lcov.info exists, the text report still prints, and `git status` shows coverage/ ignored.

## References

- Finding DyR1 in this plan's `plan/findings.yaml`.
- Finding dhr8 in this plan's `plan/findings.yaml`.

## Status

succeeded, 2026-10-04. Removed unused `@stylistic/eslint-plugin` devDependency (package.json, bun.lock); added `--coverage-reporter=lcov` to the Makefile test-node recipe. Validation: frozen install ok, make lint/lint-fix clean, scratch file flagged by @stylistic/object-curly-spacing and brace-style, coverage/lcov.info produced and gitignored. AGENTS.md unchanged.

# Followup status notes

Investigation of the five followups against the tree at plan creation. Line numbers drift; implementers re-verify with grep.

## 32b8

- Item 1: `import lists` at `src/cli/md2x.sh:38`; `list-add-item` calls at about lines 277, 281, 336. The same dependency is also used by `src/cli/test/manual/visual-smoke-test.sh` (`import strict`, `import lists`, one `list-add-item` at line 43). Dropping the devDependency breaks `make smoke-test` unless that script is converted too. `bun.lock` holds the workspace entry (line 9) and the package entry (line 57); `@liquid-labs/bash-rollup` has no dependency on the toolkit, so removal is safe.
- Item 2: already done. `md2x.sh` writes the filter with `<<'MD2X_LUA_EOF'`. Remaining optional work: a bats guard (extracted filter equals `src/cli/lib/md2x-links.lua`).
- Item 3: the discovery/resolution block runs from "process args" (about line 255) to the end of the empty-directory warnings (about line 380) in `md2x.sh`. `src/cli/test/bats/input-discovery.bats` already exercises it.
- Item 4: `md2x-percent-encode` (`src/cli/lib/link-filter.sh`) forks `printf` in a command substitution, and `printf | tr`, per byte; `md2x-lookup-record` (`src/cli/lib/output-plan.sh`) is a linear scan over a growing string per registered target (quadratic overall); `md2xAsync` (`src/node/md2x.js`) accumulates stdout/stderr without a cap while the sync path passes `maxBuffer: MAX_BUFFER` (64 MiB).

## HdEH

- Item 1 (docs): the spec's `--infer-version` bullet (`docs/md2x-spec.md`, Constraints and assumptions) already contains the trade-off sentence about dropped global/system config and `safe.directory`. Verify it and the README's version-inference section; the optional `safe.directory` warning-text improvement belongs to task 001 if wanted.
- Items 2 to 4 (code): `md2x-infer-config-refusal` and `md2x-infer-config-keys` in `src/cli/lib/preflight.sh`. `core.worktree` is not on the key allowlist, but it is only scanned in the repository git resolved *to*, so a hostile repo redirecting to a benign one is not caught.

## FUld

- Item 1: `scripts/release.sh` dry run calls `revert_bump` and later runs `bun publish --dry-run` at the pre-bump version.
- Item 2: `SECURITY.md` "Expected response" still promises "within a few days". The private-reporting setting is a maintainer action.
- Item 3: `CHANGELOG.md` Added states the CI workflow "runs the suite under macOS, Linux, bash 3.2, and a legacy Pandoc" as fact.
- Item 4: `.github/workflows/ci.yml` has no `timeout-minutes` or `concurrency`; the legacy-pandoc job uses `dpkg -i` without `apt-get -f install`.
- Item 5: needs a Linux host or first CI run; out of scope.

## S0YR

- Item 1: the legacy-pandoc CI job (2.0.6) now exists, so the floor is exercised once CI has run; the work is wording (README, spec, `preflight.sh` comment) staying honest about "intended until run".
- Item 2: `RELEASING.md` "Manifests and artifacts" already lists `bin/md2x`, `dist/md2x.mjs`, `dist/md2x.cjs`, `dist/index.d.ts`; verify against `package.json` `files`.

## 5E3C

All items live in `docs/architecture.md` plus the guard comment at `src/cli/md2x.sh:16-17`. Verify each against the current text before editing.

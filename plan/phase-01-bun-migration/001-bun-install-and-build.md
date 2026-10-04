# Switch Install to Bun and Replace the Node Build

## Purpose and scope

Remove `@liquid-labs/catalyst-scripts`, move dependency management from npm to bun, and replace the `catalyst-scripts build` rollup/babel step with `bun build`. Files: `package.json`, `package-lock.json` (delete), `bun.lock` (new), `Makefile` (variables and the `$(NODE_DIST)` recipe), `.gitignore`. Test and lint recipes are left for tasks 002 and 003 (they will be broken until then; that is expected).

## Requirements

1. Verify `bun --version` works. If bun is absent, halt and report; do not install it.
2. Capture baselines BEFORE changing anything, into the scratchpad (not the repo): copy the existing built bundle from the main checkout (`/Users/zane/playground/liquid-labs/md2x/dist/md2x.js`; if missing, build it first in the main checkout with the old toolchain without modifying tracked files) to `<scratch>/dist-baseline.js`; record `node -e "console.log(Object.keys(require('<scratch>/dist-baseline.js')))"` and, from the main checkout, `npm pack --dry-run` file list and `npm audit` summary.
3. `package.json`: remove `@liquid-labs/catalyst-scripts` from devDependencies; leave the other devDependencies, `dependencies`, `files`, `main`, `bin`, `liq`, and the three scripts as is. Add an `engines` entry only if you can justify a node floor; otherwise skip.
4. Delete `package-lock.json`; delete and ignore any stray `node_modules`; run `bun install` to generate `bun.lock` (text lockfile; if bun emits a binary `bun.lockb`, use `bun install --save-text-lockfile` or the current equivalent so `bun.lock` is produced). Keep the lockfile tracked.
5. `Makefile`: replace `NPM_BIN:=npm exec` with `BUNX:=bunx` (rename uses accordingly), remove `CATALYST_SCRIPTS`, make `BASH_ROLLUP` and `BATS` use `bunx` (the old `--` npm comment is dropped; check whether bunx needs `--` or not for bats flags such as `--print-output-on-failure`). Replace the `$(NODE_DIST)` recipe with a `bun build $(NODE_SRC)/index.js --target=node --format=cjs --packages=external --outfile=$@` style command (add `--sourcemap=inline` only if the old bundle had it and it does not change the export surface; the old bundle used inline sourcemaps). Remove `JS_SRC=...`. Leave `test-node`, `lint`, `lint-fix` untouched for now.
6. Verify the new `dist/md2x.js` against the baseline: same export keys (`md2x` only), `typeof require('./dist/md2x.js').md2x === 'function'`, `shelljs` and `path`/`node:path` are `require`d rather than bundled. Differences in bundler interop wrappers are acceptable; a changed export surface is not (then fall back to esbuild with `--bundle --platform=node --format=cjs --packages=external`, adding it as a devDependency, and note the reason).
7. `.gitignore`: leave `test-staging` for task 002 to remove. Do not touch `src/` here.

## Validation

- `bun --version` succeeds.
- `rm -rf node_modules && bun install` succeeds using only bun; `git status` shows `package-lock.json` deleted, `bun.lock` added, no `bun.lockb` left behind or tracked.
- `grep -rn catalyst-scripts package.json bun.lock Makefile` returns nothing.
- `make clean && make all` succeeds; `node -e "console.log(Object.keys(require('./dist/md2x.js')))"` prints `[ 'md2x' ]` (matching the baseline).
- `make test-cli` passes (bats cases against the rebuilt `bin/md2x`), confirming `bunx bats` and `bunx bash-rollup` work.
- `bun audit` output recorded; note whether catalyst-subtree findings are gone (final comparison is task 005).

## Status

- Outcome: succeeded (2026-10-04).
- Validation: bun 1.3.14; `rm -rf node_modules && bun install` ok (bun.lock text lockfile, package-lock.json removed, no bun.lockb); no `catalyst-scripts` in package.json/bun.lock/Makefile; `make clean && make all` ok, exports `[ 'md2x' ]`, `md2x` is a function, `shelljs` and `node:path` required (not bundled); `make test-cli` 144/144 ok; `bun audit`: No vulnerabilities found (baseline `npm audit`: 34 vulnerabilities, all catalyst-subtree).
- Changed: `package.json`, `bun.lock`, `package-lock.json` (deleted), `Makefile`. Inline sourcemap kept (`--sourcemap=inline`), export surface unchanged.
- Baselines for task 005: `/Users/zane/playground/liquid-labs/md2x/.flow/bun-migration-baselines.md`.

# End-to-End Verification of the Bun Migration

## Purpose and scope

Run the full acceptance checks from the clarified request against the finished tree and report pass/fail per item; fix nothing beyond trivial typos (anything larger is reported as a failure for the manager). Read-mostly task. Depends on tasks 001-004.

## Requirements

Run each check from a clean state and record exact output summaries:

1. `bun --version`.
2. Bun-only install: `rm -rf node_modules && bun install --frozen-lockfile` succeeds; `package-lock.json` absent; `bun.lock` present and tracked; no `bun.lockb`.
3. `make clean && make all && make test && make lint` all exit 0 (this includes the bats CLI suite via `test-cli` and `bun test` for `src/node`), then `make qa`.
4. `node -e "console.log(Object.keys(require('./dist/md2x.js')))"` prints `[ 'md2x' ]` and `bun -e "console.log(Object.keys(require('./dist/md2x.js')))"` agrees; compare to the baseline recorded in task 001's report (the old bundle exports only `md2x`).
5. `bun audit`: report remaining findings; confirm none belong to the former catalyst subtree (`@babel/cli`, `chokidar`, `braces`/`micromatch`, `lodash`, `moment`, `rollup-plugin-license`, `jest-*`). Compare with the pre-change `npm audit` baseline (34 findings: 1 moderate, 33 high per the assessment). Findings from `bash-rollup`, `bash-toolkit`, `bats` or new eslint deps are reported separately, not as failures.
6. `bun pm pack --dry-run` file list equals the old `npm pack --dry-run` list from the main checkout baseline (only `bin/md2x`, `dist/md2x.js`, `package.json`, `LICENSE.txt`, `README.md` and whatever npm always includes).
7. `grep -rIn "catalyst-scripts\|test-staging\|package-lock\|JS_SRC\|JS_LINT_TARGET\|pretest" --exclude-dir=plan --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=worktrees --exclude=bun.lock .` returns nothing.
8. `git status` shows only intended changes (no stray `test-staging/`, `bun.lockb`, or scratch files); `bash -n scripts/release.sh` passes.

## Validation

The report lists every numbered check with pass/fail and evidence. Any failure sets status to partial with the failing item and suspected owning task (001-004).

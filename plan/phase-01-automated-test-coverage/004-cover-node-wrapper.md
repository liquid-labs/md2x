# Cover Node Wrapper

## Purpose and scope

Add Jest unit coverage for the Node library wrapper (`src/node/md2x.js`, re-exported by `src/node/index.js`): how it marshals its options object into CLI flags, what it returns, how it handles the `markdown`-string staging path, and how it propagates a non-zero CLI exit. `shelljs` is mocked, so no case shells out, builds anything, or touches the filesystem for real.

Scope is `src/node/md2x.test.js` (which task 001 created with a single trivial case) and, if useful, a sibling test file. No changes to `src/node/md2x.js`, `src/node/index.js`, the `Makefile`, `package.json`, or the CLI.

No standard skill covers this; the [Requirements](#requirements) section below is the procedure.

## Requirements

Cover at least:

1. **Argument marshaling.** For a representative options object, assert the exact command string handed to `shell.exec`. The wrapper always prepends `--list-files` and `--output-format <format>` (defaulting to `pdf`), then appends, in the order the source applies them, `--flatten-dirs`, `--infer-title`, `--infer-version`, `--no-toc`, `--title '<title>'`, `--single-page`, `--output-path '<path>'`, followed by the single-quoted, space-joined `sources`. Cover: defaults only; each boolean flag individually; `title` and `outputPath` quoting; and multiple `sources`.
2. **Return value.** With a mocked result whose `toString()` yields a multi-line path list, the function returns an array of those paths with empty entries dropped.
3. **Error propagation.** With a mocked result whose `code` is non-zero, the call throws an `Error` whose message includes both the exit code and the mocked `stderr` — per `docs/md2x-spec.md` § Node library.
4. **Non-fatal stderr.** With `code === 0` and non-empty `stderr`, the call returns normally and forwards stderr to `console.error` (spy on it).
5. **The `markdown` staging path.** When `markdown` is supplied instead of `sources`, the wrapper creates a staging directory under `shell.tempdir()`, writes the content to a `.md` file there, appends that file to the command, and removes the staging directory afterwards — **including when the command fails** (the `finally`). Assert the cleanup happens in both the success and the throwing case.

### Implementation guidance

- Jest runs against the Babel-compiled copies under `test-staging/`, not `src/node/` directly, so the test file imports its subject as `./md2x`. `catalyst-scripts pretest` rebuilds `test-staging/` before each run; never edit anything under `test-staging/`.
- Mocking `shelljs` is the fiddly part. It is CommonJS, imported as a default import and mutated at module load (`shell.config.silent = true`). A manual factory mock is the reliable shape — something along the lines of `jest.mock('shelljs', () => ({ __esModule: true, default: { config: {}, exec: jest.fn(), tempdir: jest.fn(), mkdir: jest.fn(), rm: jest.fn(), ShellString: jest.fn() } }))` — since Babel's interop resolves the default import to `.default`. If that proves wrong for this Babel/Jest combination, adjust; do not work around it by refactoring `src/node/md2x.js`.
- `shell.ShellString(markdown).to(stagingFile)` is a chained call: the mock's `ShellString` must return an object with a `to` method (and `exec` if you exercise the commented-out path — you should not).
- Reset mocks between cases so command-string assertions cannot leak across tests.

### Spec discrepancies

The wrapper has at least two behaviours that look like defects rather than intended design. **Do not fix them here, and do not silently encode them as "correct" expectations.** Write the case to document current behaviour with an explicit comment naming the discrepancy, and report each as a candidate followup:

- `if (!title && sourceSpec === '-')` can never be true: `sourceSpec` is built as `'${sources.join("' '")}'`, so `sources: ['-']` yields the quoted string `'-'`, never the bare `-`. The `title = 'Report'` default is therefore unreachable.
- On the `markdown` path with no `title`, the staging file is named `` `${title}.md` `` with `title` undefined, producing `undefined.md` and hence an `undefined.<fmt>` output.

If you find further divergences from `docs/md2x-spec.md` § Node library, handle them the same way.

## Validation

- `make test-node` (and `make test`) passes with a zero exit status; every new case is reported by Jest as run, not skipped.
- No case invokes a real subprocess: with `shelljs` mocked, `shell.exec` is never the real implementation. Confirm no `bin/md2x`, `dist/`, `test-out/`, or temp output appears as a side effect of the run (`git status` clean apart from expected gitignored artifacts).
- Every requirement 1–5 above has at least one corresponding case; map cases to requirements in your task report.
- `git diff --stat` shows changes confined to test files under `src/node/` — `src/node/md2x.js` and `src/node/index.js` unmodified, no `Makefile` or `package.json` change.
- Each documented spec discrepancy carries an in-test comment and appears in your task report as a candidate followup.
- `make lint` passes (the linter covers `src/node`, and test files live there).

## Assumptions

- Task 001 has landed the Jest wiring (`catalyst-scripts pretest` / `test` via the `Makefile`) and a trivial passing `src/node/md2x.test.js` you are expanding.
- Jest 27 with `testEnvironment: node` and `collectCoverage: true`, configured by `@liquid-labs/catalyst-scripts`; `coverage/` and `test-staging/` are already gitignored.
- Tasks 002, 003, and 005 may be running in parallel; none of them touch `src/node/`.

## References

- [`docs/md2x-spec.md`](../../docs/md2x-spec.md) § Node library — the signature, return contract, throw contract, and the documented surface asymmetry (`--list-files` always applied; `--quiet`, `--to-stdout`, `--keep-intermediate` unavailable).
- [`docs/architecture.md`](../../docs/architecture.md) § Node library wrapper — the pass-through design that makes mocking `shelljs` the right boundary.
- `src/node/md2x.js` — the subject; the command-construction block is lines 25–52 and the result handling lines 54–78.
- [Test tooling survey](../notes/test-tooling-survey.md) § "Node wrapper → Jest, via `catalyst-scripts`" — how the staging pipeline works and why the import path is `./md2x`.

## Checkpoint hints

- After the argument-marshaling cases.
- After the return-value and error-propagation cases.
- After the `markdown` staging-path cases.

## Status

**Outcome: succeeded** — 2026-07-29.

Filled in `src/node/md2x.test.js` (task 001's trivial case retained as the first `test`) with 17 Jest cases covering all five requirements. `shelljs` is mocked with the manual factory shape the task doc's guidance suggested (`__esModule: true, default: { config, exec, tempdir, mkdir, rm, ShellString }`); no case shells out, and `jest.mock('shelljs', …)` is written *after* the `import shell from 'shelljs'` / `import { md2x } from './md2x'` lines to satisfy the project's `import/first` lint rule — this is safe because `babel-plugin-jest-hoist` (bundled in `babel-jest`) hoists `jest.mock` calls above all imports at compile time regardless of source order, so the mock is still installed before `shelljs` is required.

### Requirement → case mapping

1. **Argument marshaling** — `describe('argument marshaling', …)`: defaults-only; non-default `format`; `test.each` over the five boolean flags (`flattenDirs`, `inferTitle`, `inferVersion`, `noToc`, `singlePage`) individually; `title`/`outputPath` quoting and ordering; multiple `sources` space-joining/quoting; plus the followup-`udVi` documentation case below.
2. **Return value** — `describe('return value', …)`: multi-line stdout with a blank line, asserts the blank entry is dropped.
3. **Error propagation** — `describe('error propagation', …)`: non-zero `code`, asserts the thrown `Error`'s message contains both the format, the exit code, and the mocked `stderr`.
4. **Non-fatal stderr** — `describe('non-fatal stderr', …)`: `code === 0` with non-empty `stderr`; asserts the normal return value and a `console.error` spy call with the stderr text.
5. **`markdown` staging path** — `describe('markdown staging path', …)`: success case (staging dir created under the mocked `shell.tempdir()`, `ShellString(...).to(...)` called with the staging file, `shell.exec` command asserted verbatim including the staging-file append, `shell.rm('-r', stagingDir)` called once) and a failure case (`shell.exec` mocked to a non-zero result; asserts the call throws **and** that `shell.rm` still fires with the same staging directory — the `finally` cleanup).

### Spec discrepancies encountered (candidate followups — not fixed here)

Both were already tracked as followups per the dispatch context; each got its own test case with an in-code comment documenting **current** (buggy) behavior rather than presumed-intended behavior:

- **`udVi`** — `sourceSpec` is always the quoted string `'${sources.join("' '")}'`, so `sources: ['-']` never equals the bare `-` string the guard `if (!title && sourceSpec === '-')` checks for. The `title = 'Report'` default is unreachable. Test: `'never applies the unreachable default title for a lone "-" source (followup udVi)'`. This is also why the branch's assignment (`src/node/md2x.js` line 27) shows up as the sole uncovered line in the coverage report (97.43% stmts / 94.73% branch / 100% funcs) — it cannot be exercised without changing the production code, which is out of this task's scope.
- **`egcc`** — on the `markdown` path with no `title`, the staging filename is built as `` `${title}.md` `` before any title default could apply, so it is literally `undefined.md`. Test: `'stages to "undefined.md" when no title is given (followup egcc)'`.

No further divergences from `docs/md2x-spec.md` § Node library were found beyond the two flagged above.

### Validation

- `make test-node` and `make test`: both pass, all 17 cases reported as run (none skipped), zero exit status.
- No real subprocess: `shell.exec` is the Jest mock throughout (never the real shelljs implementation); confirmed no `bin/md2x`, `dist/`, `test-out/`, or stray temp output — `test-staging/` and `coverage/` are the only artifacts `make test-node` produces and both are already `.gitignore`d.
- `git diff --stat` (in this worktree) shows only `src/node/md2x.test.js` changed; `src/node/md2x.js`, `src/node/index.js`, `Makefile`, and `package.json` are untouched.
- `make lint` passes (initial draft had two `key-spacing` alignment errors and an `import/first` ordering error on the `jest.mock` factory object/placement; both fixed by hand, no `--fix` run needed in the end).

### Affected files

- `src/node/md2x.test.js`

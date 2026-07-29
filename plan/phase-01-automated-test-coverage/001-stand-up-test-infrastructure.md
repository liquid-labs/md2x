# Stand Up Test Infrastructure

## Purpose and scope

Establish everything the rest of this phase writes tests against: an automated bash test harness for the CLI with stub `pandoc` / `gs` / `pdftk` executables, the Jest wiring for the Node wrapper, and the `Makefile` / `package.json` changes that make `make test` (and therefore `npm test`) a deterministic, non-interactive command. Also relocates today's interactive `src/cli/test/test.sh` to an opt-in target so it is no longer what `make test` runs.

This task owns **all** build wiring and **all** shared test helpers for the phase. Tasks 002–005 add only test files, so this task must leave the helper surface complete enough that they do not need to touch it.

No standard skill covers this; the [Requirements](#requirements) section below is the procedure.

Read [the test tooling survey](../notes/test-tooling-survey.md) in full before starting — it contains the runner comparison, the exact stub side effects required to survive the CLI's `errexit` mode, and the determinism hazards.

## Requirements

### 1. CLI test harness

- Add [bats-core](https://github.com/bats-core/bats-core) as a devDependency: `npm install --save-dev bats`. Verify with `npx bats --version`.
  - **If the npm registry is unreachable**, you are pre-authorized to fall back to a minimal in-repo bash harness instead: a helper file providing test registration plus `assert_success`, `assert_failure`, `assert_output_contains`, and `assert_file_exists`, and a runner that exits non-zero if any case fails. Report the substitution prominently in your task report — later tasks read the landed harness's own files to learn its conventions, but the manager needs to know the decision changed.
- Lay the CLI tests out under `src/cli/test/`, keeping the existing `tiny-doc.md` fixture where it is. A layout such as `src/cli/test/bats/*.bats` for cases, `src/cli/test/helpers/` for shared bash helpers, and `src/cli/test/stubs/` for the stub executables is suggested; pick one and be consistent, since four other tasks will follow it.
- The harness must **not** go through `bash-rollup` and must not `import` anything from `@liquid-labs/bash-toolkit` — it exercises the already-built `bin/md2x`, so it needs no rollup step.

### 2. Stub external binaries

Provide executable stubs for `pandoc`, `gs`, and `pdftk` that a test puts on `PATH` ahead of the real ones. Each stub appends its `argv[0]` and full argument vector to the log file named by an environment variable (`MD2X_TEST_STUB_LOG` or similar) so tests can assert on what the CLI asked for.

Each stub must reproduce the side effects `generate-page.sh` depends on, or the CLI will abort under `set -o errexit`:

- **`pandoc`** — create the file named by `-o`, and create the file named by `--log` (`pandoc-log.log` in the CWD; the CLI `rm`s it unless `--keep-intermediate`). Writing a recognizable placeholder into the `-o` file is useful for `--to-stdout` assertions.
- **`gs`** — create the file named by `-o` (the `${OUTPUT_PATH}/${TITLE}-overlay.pdf`; also `rm`'d unless `--keep-intermediate`).
- **`pdftk`** — for a `dump_data` invocation, print a numeric `NumberOfPages: N` line and a `PageMediaDimensions: <x> <y>` line (both are fed into `$(( ))` arithmetic, so they must parse as integers); for a `multistamp … output <file>` invocation, create `<file>`.

Do not stub `perl` or `jq`.

### 3. Shared helpers

Provide, at minimum:

- A setup helper that creates a per-case temporary working directory **outside the repository**, `cd`s into it, and points `PATH` at the stub directory. The temp CWD is not optional: `src/cli/md2x.sh` line 135 probes `git status --porcelain` and `package.json` **from the CWD** on every invocation, so running from the repo root makes `VERSION` depend on whether the tree happens to be dirty. Outside a work tree it deterministically resolves to `working`.
- A teardown helper that removes the temp directory.
- A helper resolving the absolute path of the built `bin/md2x` (tests `cd` away from the repo, so a relative path will not work).
- A helper for asserting against the stub argument log (e.g. "the last `pandoc` invocation included `--toc`", "some `gs` invocation's argument vector contains `Version: working`").
- A helper for building a small fixture tree inside the temp directory.
- A `PATH`-without-a-given-stub helper, so task 003 can test the `exit 2` missing-binary contract.

### 4. Node test wiring

- Wire Jest through the project's existing `catalyst-scripts` pipeline rather than adding a direct `jest` devDependency or a hand-written `jest.config.js`: `JS_SRC=src/node npx catalyst-scripts pretest` (Babel-compiles `src/node` into `test-staging/`) followed by `JS_SRC=src/node npx catalyst-scripts test` (runs Jest against `test-staging`). Match how the `Makefile` already invokes `catalyst-scripts build` and `catalyst-scripts lint`.
- Add `src/node/md2x.test.js` with one trivial passing case (e.g. the module exports `md2x` as a function) purely to prove the wiring executes. Task 004 fills this file in.
- Colocated `src/node/*.test.js` is the right location: the `Makefile`'s `NODE_FILES` already excludes `*.test.js` and `*/test/*` from the build inputs.

### 5. Make and npm wiring

- `make test` must run both suites, non-interactively, exiting non-zero if either fails. Separate `test-cli` and `test-node` targets that `test` depends on are suggested, so a developer can run one surface.
- The CLI suite depends on the built `bin/md2x`, so its target must depend on the existing build targets, as `test:` does today.
- `npm test` continues to delegate to `make test`; do not change `package.json`'s `test` script's meaning.
- `make qa` (`test lint`) must keep working.

### 6. Relocate the interactive smoke test

- Move `src/cli/test/test.sh` to a clearly-marked manual location (e.g. `src/cli/test/manual/visual-smoke-test.sh`) and expose it as an opt-in `make smoke-test` target that keeps its existing `bash-rollup` step and its `test-out/` staging. Do not delete it — it retains value as a "does the output actually look right" check — but nothing in the default `test` path may invoke it.
- Add a header comment to the relocated script stating that it is interactive, macOS-specific (`open -Fn`, `lsof`), and not part of `make test`.

### 7. Documentation

Update `AGENTS.md`'s "Build and test" section: the new commands, what `make test` now runs, the fact that the bulk of the suite uses stub external binaries and so does not require a working Pandoc PDF pipeline, and how to run the opt-in visual smoke test. Do **not** touch the "Known issues" section — task 002 owns that.

Update `docs/project-structure.md`'s description of `src/cli/test/` to match the new layout.

## Validation

- `npx bats --version` succeeds (or the fallback harness's runner does), and `bats` appears in `package.json` `devDependencies` with `package-lock.json` updated.
- `make all` succeeds.
- `make test` runs to completion with a zero exit status, **without** opening any application and **without** waiting on stdin. Confirm the non-interactivity concretely by running it with stdin closed: `make test < /dev/null`.
- `make test` exits non-zero when a case fails: temporarily break one assertion, confirm the failure propagates through `make`, then restore it.
- `make test` passes with the real `pandoc` PDF pipeline unavailable — that is this machine's actual state (Pandoc's `weasyprint` engine is absent), so simply passing locally demonstrates it.
- `make test-node` alone runs Jest and reports the trivial case passing; `test-staging/` and `coverage/` are produced and are already covered by `.gitignore` (verify `git status` is clean of them).
- `make smoke-test` still rolls up and launches the interactive script (you may abort it once it opens a viewer — confirm only that the target resolves and starts).
- `make lint` and `make qa` still pass.
- `git status` shows no new untracked build artifacts that `.gitignore` does not already cover.
- `grep -rn 'test\.sh' Makefile AGENTS.md docs/` returns no reference to the old default-test path.

## Assumptions

- `npm install` has been run in the task worktree; `node_modules/.bin/jest` and `node_modules/.bin/babel` already resolve (both are present transitively via `@liquid-labs/catalyst-scripts`).
- `pandoc`, `gs`, `pdftk`, `jq`, and `perl` are on `PATH`; Pandoc's `weasyprint` PDF engine is **not**, so a real PDF conversion fails on this machine. Nothing in this task may depend on one succeeding.
- The CLI's unquoted word-splitting (`for ROOT_DIR in $SEARCH_DIRS`, unquoted `find ${ROOT_DIR}`) means paths with spaces are already broken. Keep every fixture and temp path space-free; do not attempt to repair that here.

## References

- [Test tooling survey](../notes/test-tooling-survey.md) — runner decisions, required stub side effects, determinism hazards.
- `src/cli/lib/generate-page.sh` — the file whose `rm`/`mv`/arithmetic expectations dictate what each stub must create.
- `src/cli/md2x.sh` lines 91–96 (preflight), 135 (version probe), 149–182 (the conversion loop).
- `Makefile` — existing `build` / `lint` / `test` target shapes to mirror.
- `node_modules/@liquid-labs/catalyst-scripts/config/jest.config.js` — the Jest config that will apply (`testEnvironment: node`, `collectCoverage: true`, `rootDir: process.cwd()`, and a `package.json` `catalyst.jestConfig` override hook).
- `docs/md2x-spec.md` — the behavioural contract later tasks assert against.

## Checkpoint hints

- After adding the `bats` devDependency and confirming `npx bats --version`.
- After the stub executables and helpers exist and one hand-run bats case passes.
- After the `Makefile` / `package.json` wiring makes `make test` green end to end.
- After relocating the interactive script and adding `make smoke-test`.
- After the `AGENTS.md` and `docs/project-structure.md` updates.

# Test Coverage and Mirrored-Output Bugfix

## Purpose and scope

This plan does two things:

1. **Fixes followup `aI57`** — the hardcoded `/policy/` path strip in the non-`--flatten-dirs` (mirrored-output) branch of `src/cli/md2x.sh`, which silently no-ops for any input path without a `/policy/` segment and places output under a mirror of the input's *full* path instead of its path relative to the search root it was found under.
2. **Replaces md2x's manual test artifact with an automated, non-interactive suite** covering both external surfaces — the bash CLI and the Node library wrapper — wired into `make test` / `npm test` so it runs deterministically with no human at the keyboard.

The two are sequenced together deliberately: the `aI57` fix lands with direct regression coverage — cases that are red against the current implementation and green after the fix — rather than the tests being decoupled from the fix.

### What must change

- `src/cli/md2x.sh` derives the mirrored output subdirectory from the search root a file was found under: the directory argument given on the command line, or the input file's own directory when the file was named directly. The full contract, worked examples, and edge cases are in [the mirrored output path contract note](./notes/mirrored-output-path-contract.md).
- An automated CLI test suite (bats-core) and an automated Node test suite (Jest, via the project's existing `catalyst-scripts` pipeline) exist and run from `make test` / `npm test`.
- Today's interactive `src/cli/test/test.sh` moves to an opt-in target; it is no longer what `make test` runs.
- `AGENTS.md` gains the new test commands and loses the "Known issues" bullet pointing at `aI57`.

### What must not change

- md2x's flag surface. No new CLI flags, no renames, no changes to `--flatten-dirs`, `--single-page`, or stdin behaviour beyond the mirrored-path derivation itself.
- The Node wrapper's public signature (`docs/md2x-spec.md` § Node library) and its pass-through architecture — the CLI stays the single source of truth for conversion behaviour.
- The build outputs and their pipeline: `bin/md2x` via `bash-rollup`, `dist/md2x.js` via `catalyst-scripts`. `bin/` and `dist/` remain generated and gitignored; sources under `src/` remain the only hand-edited files.
- The three declared external runtime dependencies. This plan does not add a fourth, and does not change the preflight check.

### Success criteria

- `make test` (and therefore `npm test`) runs to completion non-interactively, deterministically, and exits non-zero on any failure. It never opens a viewer application or waits on stdin.
- The suite passes on a machine that has `pandoc`, `gs`, and `pdftk` but **cannot** perform a real PDF conversion (which is the state of the maintainer's machine today — see followup `BfN6`, Pandoc's `weasyprint` engine is absent).
- The regression cases enumerated in [the contract note](./notes/mirrored-output-path-contract.md) fail against the pre-fix CLI and pass after.
- Both surfaces are covered: CLI option parsing and behaviour (format validation, `--single-page`, `--flatten-dirs` vs. mirrored output, stdin `-`, `--infer-title` / `--infer-version` / `--no-toc` / `--quiet` / `--list-files` / `--to-stdout` / `--help`, exit codes for a missing binary and for bad input paths) and the Node wrapper (argument marshaling, returned file list, error propagation on non-zero CLI exit).

### Key decision: stub the external-tool boundary

The bulk of the suite runs the CLI against **stub `pandoc` / `gs` / `pdftk` executables on a test-controlled `PATH`** that record their argument vectors and fabricate the files their real counterparts would produce; a smaller, separately-targeted end-to-end set exercises the real toolchain and *skips* rather than fails when it is unavailable.

Rationale, grounded in `docs/architecture.md`: md2x's own logic is argument construction, source-list resolution, and output-path derivation — it orchestrates three subprocesses and owns no rendering. Stubbing that boundary tests md2x rather than Pandoc, keeps the suite fast and reproducible, and is the only way to test the spec's `exit 2` missing-binary contract at all (it requires controlling `PATH`). It is also a hard requirement for the suite to be green anywhere: real PDF conversion does not work on the maintainer's own machine today. The accepted trade-off is that the stub suite cannot catch a Pandoc-side regression or a flag that is malformed but still accepted — which is what the gated end-to-end task covers, at whatever fidelity the running machine allows. Full reasoning, the runner comparison, and the determinism hazards test authors must work around are in [the test tooling survey](./notes/test-tooling-survey.md).

## Current status

Not started. Phase 01 begins first, with task 001 (`stand-up-test-infrastructure`) as a hard prerequisite for every other task in the phase — it establishes the harness, the stub executables, and the `make` wiring that the remaining tasks write tests against.

Pre-conditions:

- `npm install` must have run in the task worktree. Task 001 additionally needs npm registry access to add the `bats` devDependency; a pre-authorized fallback for an unreachable registry is specified in [the survey note](./notes/test-tooling-survey.md#bash-cli--bats-core) and in the task document.
- `pandoc`, `gs`, `pdftk`, `jq`, and `perl` are on `PATH` on the current machine; Pandoc's `weasyprint` PDF engine is **not**, so no task may assume a real PDF conversion can succeed.
- Followup `aI57` is outstanding on the working branch. It is resolved by Phase 01 task 002, which reports the resolution for the manager to remove via `followups_remove` rather than editing `plan/followups.yaml` itself.

## Overview

### Phase 01 — Automated Test Coverage

Stands up the test infrastructure, lands the `aI57` fix with its regression coverage, and fills in behavioural coverage for both surfaces.

- **001 — Stand Up Test Infrastructure** *(prerequisite for all of 002–005)*. Adds the bats-core devDependency, the CLI test layout under `src/cli/test/`, the stub `pandoc`/`gs`/`pdftk` executables and shared helpers, and one or two sanity cases. Adds the Node-side Jest wiring (`catalyst-scripts pretest` / `test`) plus a trivial passing `src/node/md2x.test.js` to prove it. Rewires the `Makefile` and `package.json` so `make test` runs both suites non-interactively, and relocates today's interactive `test.sh` to an opt-in `make smoke-test` target. This task owns **all** build wiring and shared helpers so that 002–005 only add test files.
- **002 — Fix Mirrored Output Path Derivation**. The `aI57` fix in `src/cli/md2x.sh`, plus the bats regression cases that are red before it and green after. Also removes the `AGENTS.md` "Known issues" bullet and reports the followup resolution.
- **003 — Cover CLI Option Behavior**. Bats cases for the rest of the CLI surface: output-format validation, `--single-page` concatenation, stdin `-`, `--infer-title`, `--infer-version`, `--no-toc`, `--quiet`, `--list-files`, `--to-stdout`, `--help`, and the exit codes for a missing binary and a bad input path. Explicitly does **not** assert mirrored-output paths — those belong to 002.
- **004 — Cover Node Wrapper**. Jest cases for `src/node/md2x.js`: option-to-flag marshaling, the returned file list, the `markdown`-string staging path and its cleanup, and the thrown `Error` carrying exit code and stderr on a non-zero CLI exit. `shelljs` is mocked, so nothing shells out.
- **005 — Add Gated End To End Tests**. A small real-toolchain set that converts the `tiny-doc.md` fixture with the actual `pandoc`/`gs`/`pdftk` and skips cleanly when the toolchain (or Pandoc's PDF engine) is unavailable.

**Sequencing.** 002, 003, 004, and 005 all depend on 001 and on nothing else; they touch disjoint files and are parallel-eligible with one another. 002 owns `src/cli/md2x.sh` and every mirrored-output assertion; 003, 004, and 005 add only new test files, so a test written outside 002 must use inputs whose placement is invariant under the fix (see the survey note's determinism hazards).

### Phase 02 — Documentation Updates

- **001 — Update Architecture Docs**. Reviews `docs/architecture.md` and `docs/md2x-spec.md` against what Phase 01 landed — principally the now-precise mirrored-output contract (spec UC3) and the arrival of an automated test surface — and updates them where they no longer describe the system.

## Related documents

- [Test tooling survey](./notes/test-tooling-survey.md) — existing conventions, runner decisions, the stub-boundary rationale, and determinism hazards.
- [Mirrored output path contract](./notes/mirrored-output-path-contract.md) — the `aI57` analysis, intended contract, edge cases, and fail-before/pass-after cases.
- [`docs/md2x-spec.md`](../docs/md2x-spec.md) — the behavioural contract the suite asserts against.
- [`docs/architecture.md`](../docs/architecture.md) — component boundaries and the fail-fast error model.
- [`AGENTS.md`](../AGENTS.md) — build/test/lint conventions the new targets fit into.

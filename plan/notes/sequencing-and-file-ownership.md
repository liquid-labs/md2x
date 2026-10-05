# Sequencing and File Ownership

## Purpose and scope

Guidance for the phase-decomposition agents on serialization constraints and on a suggested split of each phase into single-session tasks. It is advisory. The decomposing agent owns the final task breakdown. The constraints come from which files each piece of work touches.

## Hot files

- `src/cli/md2x.sh` is touched by nearly every Phase 1 and Phase 2 CLI change. Tasks that edit it must be serialized within a phase; give each a hard dependency on the previous one.
- `src/cli/lib/generate-page.sh` is touched by the work-directory, stdin, CSS, title, link/image, and hygiene work. Serialize it with the same chain.
- `src/cli/test/stubs/pandoc` and `src/cli/test/helpers/common.bash` change whenever pandoc arguments or the harness change. These go with the task that changes the arguments.
- `package.json`, `bun.lock`, and `Makefile` are touched by the Node packaging work (P2), the `--version` build-time injection (P2), lint and dependency bumps (P3), and package metadata (P3). Serialize them.
- `AGENTS.md`, `README.md`, and `docs/*.md`: consolidate edits into the Phase 3 docs tasks so they do not conflict. Code tasks update only the `--help` text, which lives in `md2x.sh`, for flags they add or change.

## Phase 1: correctness and regression tests (suggested split, serial chain)

1. Error helper and exit-code contract. Migrate every `echoerrandexit` call site. Move dependency failures, including the three `ensure-weasyprint` failure functions, to the dependency exit code. Add TTY-gated color and `NO_COLOR`. Update the affected bats assertions.
2. Project-owned option parser. Explicit short table with B5 fixed. GNU getopt probing without `brew`. Help before getopt. Friendly getopt errors with a usage hint. No `perl`. Regression tests for every short flag, for rejected `-q`/`-l`/`-n`/`-i`, for help without brew or getopt, and for abbreviation behavior.
3. Bash 3.2 compatibility. sh guard, `nounset`-safe arrays, the process-substitution parse hazard, failure propagation from the main loop, and the harness interpreter override. Run the whole suite under `/bin/bash`.
4. Per-run work directory. B1, S13, N6. Regressions: `-t README README.md two.md` keeps `README.md`; a cwd `input.md` survives; no `pandoc-log.log` and no `*-combined.pdf` in the cwd; `--keep-intermediate` prints the directory.
5. stdin fidelity. B2: indentation, backslashes, a final line without a newline, and empty stdin.
6. Inline HTML CSS. B3.
7. Title sanitization. S7 in all four sinks, including the minimal Node fix; N8 robustness.

## Phase 2: interface contract (suggested split)

Serial chain on `md2x.sh` and `generate-page.sh`:

1. `--version` with build-time injection; help text additions: exit codes, homepage, `--keep-intermediate` parity, removal of the "other formats" claim. Touches the `Makefile` `CLI_BIN` recipe, which must now depend on `package.json`.
2. Input discovery and argument validation. S2 remainder, S15, N1, N3, N7. N7 may touch `toc-preprocess.py`.
3. `-o/--output` and `--to-stdout` semantics. S14, S10 `-p` normalization, output path that is a file.
4. Output collision protection. S4.
5. Link and image resolution with the Lua filter. S5, S6, R7, missing-resource warnings, single-page source markers. Gated real-pandoc bats tests.
6. stderr and version hygiene. S3, the remaining S8 leak sites, N5 cleanup, N9 pandoc floor.

Parallel-eligible with that chain:

- WeasyPrint CSS warning pruning (S12). Touches only `src/cli/lib/github.css` plus a gated e2e assertion.
- Node wrapper modernization (S11, R2, R4, R9, R12, user decision 7). Touches `src/node/**`, `package.json`, `bun.lock`, and the `Makefile` `NODE_DIST` recipe. It must follow item 1 because both edit the `Makefile`, and it relies on P1's stdin fix and exit codes.

## Phase 3: docs, CI, and release readiness (suggested split)

Parallel-eligible starters, independent of each other:

- GitHub Actions CI: `.github/workflows/` only.
- Community docs: `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`.
- psgq slug-probe optimization: `toc-preprocess.py` and its bats file.

Serial chains:

- Lint config and dev-dependency bumps (`eslint.config.mjs`, `package.json`, `bun.lock`, `Makefile` lint target), then package metadata (`package.json`). Then RELEASING.md, `scripts/release.sh`, and the dry run, which needs the final package metadata and `CHANGELOG.md`.
- README overhaul (after the community docs, since it links them), then spec, AGENTS.md, and project-structure updates (after CI and lint, so AGENTS.md describes them), then the flag-table drift test (after both the README and the spec).

## Validation conventions every task should inherit

- `make qa` passes. That is the bats suite, `bun test`, and lint.
- Where `/bin/bash` is 3.x (macOS), the bats suite also passes under the Phase 1 interpreter override.
- Real-toolchain bats cases (`real-toolchain-e2e.bats` and any new gated files) are run locally when pandoc, gs, pdftk, and WeasyPrint are available. This development host has them.
- Each task's regression tests fail before the fix and pass after it. The task report states that this was checked.

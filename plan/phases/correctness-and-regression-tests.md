# Correctness and Regression Tests

## Goals

Fix the six user-named must-fix defects. Each one destroys user data, corrupts output, fails silently, or is a security problem:

1. `--single-page -t X` deletes the user's `X.md` (B1)
2. stdin corruption and a silent exit on empty stdin (B2)
3. unstyled HTML caused by a deleted `TMPDIR` CSS link (B3)
4. a silent exit 0 under macOS `/bin/bash` 3.2 (B4)
5. the wrong `-s` meaning and hidden auto-shorts (B5)
6. an unsanitized `--title` in the filename, YAML, PostScript, and Node staging sinks (S7), including non-ASCII and PostScript-special titles that must not crash `gs` (N8 robustness)

Each fix ships with a regression test that fails before the fix. The existing 144 bats tests caught none of these defects.

This phase comes first because it also lays the foundations that later phases build on:

- the error-reporting helper and exit-code contract
- the project-owned option parser, which removes the hard runtime dependency on `brew` and `perl`
- bash 3.2 compatibility, with a harness interpreter override
- the per-run work directory for all intermediates

## Inputs

- Current sources: `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`, `src/cli/lib/ensure-weasyprint.sh`, `src/cli/lib/parameters.sh`, `src/node/md2x.js`.
- The rolled-in bash-toolkit option parser and error helpers, which are being replaced.
- The bats harness (`src/cli/test/helpers/*`, `src/cli/test/stubs/*`) and the existing 144 cases.
- Decisions in [design decisions](../notes/design-decisions.md): the exit-code contract and short-flag set, both confirmed by the user ([exit codes](../notes/exit-code-contract-answer.md), [short flags](../notes/short-flag-set-answer.md)); bash 3.2 support; the work directory; stdin; HTML CSS; title handling.
- The [brew and getopt resolution](../notes/brew-and-getopt-resolution.md) finding.

## Outputs

- A project-owned error helper with no ANSI color off a TTY, `NO_COLOR` support, and the `md2x: ` prefix. A documented-in-code exit-code contract (0 success, 1 runtime, 2 usage, 3 dependency), applied to every existing exit path, including the WeasyPrint bootstrap failure paths.
- A project-owned option parser module with an explicit short-flag table:
  - `-s` is `--to-stdout`.
  - `-q`, `-l`, `-n`, and `-i` are gone.
  - GNU getopt is resolved without `brew`, and `--help` works without getopt.
  - getopt errors are friendly and include a usage hint.
  - GNU abbreviation behavior is kept.
- A CLI that runs correctly under bash 3.2 and newer, has a POSIX guard for non-bash and too-old shells, and propagates failures from the main loop. The bats harness can run the whole suite under a chosen interpreter.
- One per-run work directory holding every intermediate. Nothing but the requested outputs is written to the cwd, and `--keep-intermediate` prints the directory.
- Byte-exact stdin handling. Empty stdin is a usage error.
- HTML output with inline CSS and no `TMPDIR` reference.
- Title-safe sinks: filename validation, literal `-M title=`, PostScript escaping with control characters stripped, and a Node staging path never derived from `title`. A PDF run with a non-ASCII or PostScript-special title (`\`, `(`, `)`) succeeds. The header and footer features of N8 are deferred ([N4/N8 scope answer](../notes/n4-n8-scope-answer.md)) and are not part of this phase.
- New regression bats cases for every defect above, plus updated stubs and harness. `make qa` is green.

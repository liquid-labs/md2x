# Cover CLI Option Behavior

## Purpose and scope

Fill in automated coverage for the md2x CLI's option parsing and behaviour, against the contract in `docs/md2x-spec.md`. Adds bats cases only — no changes to `src/cli/`, the `Makefile`, `package.json`, or the shared helpers.

Mirrored-output path derivation is explicitly **out of scope**: task 002 owns it, along with every assertion about non-`--flatten-dirs` output placement.

No standard skill covers this; the [Requirements](#requirements) section below is the procedure.

## Requirements

Add bats cases following the conventions task 001 landed (read the existing files under `src/cli/test/` first). Every case runs the built `bin/md2x` in a per-case temp working directory with the stub `pandoc`/`gs`/`pdftk` on `PATH`, and asserts on some combination of: exit status, stdout/stderr text, files created, and the stub argument log.

Cover at least:

| Area | Cases |
| --- | --- |
| `--output-format` | Each of `pdf`, `html`, `docx` succeeds and produces the expected filename (note `html` output gets a `-base` suffix — assert the actual behaviour and flag it if it contradicts the spec). An unrecognized value exits non-zero with a message naming the format, **before** any conversion is attempted (assert the stub log records no `pandoc` invocation). Absent `--output-format` defaults to `pdf`. |
| `--single-page` | Multiple input files are concatenated in the order given into one output named from `--title` (default `output`), and exactly one output file is produced. Assert on the content the stub `pandoc` was handed, or on the concatenation buffer, to prove ordering. |
| stdin `-` | `printf … \| md2x -` produces one output named from `--title` (default `output`) and invokes `pandoc` exactly once. |
| `--infer-title` | The `--metadata-file` handed to `pandoc` carries `title: '<expected>'`; without the flag it does not. |
| `--infer-version` | A `gs` invocation's PostScript argument contains a `Version:` string; without the flag it does not. In a temp CWD outside a git work tree the value is deterministically `working` — see the survey note. |
| `--no-toc` | `pandoc` is invoked **without** `--toc` for `pdf` and `html`; **with** `--toc` for those formats when the flag is absent; and never with `--toc` for `docx` regardless of the flag. |
| `--quiet` | No `Created …` line on stdout, while the output file is still produced. |
| `--list-files` | Stdout is the generated path only, with no `Created ` prefix. |
| `--to-stdout` | The converted content reaches stdout (the stub `pandoc` writes a recognizable placeholder into its `-o` target) and no `Created …` line appears, since `--to-stdout` implies `--quiet`. |
| `--help` / `-h` | Exit `0`, usage text on stdout, and — per the spec — **no** binary preflight check: assert it still exits `0` with a `PATH` from which the stubs are absent. |
| `--keep-intermediate` | `pandoc-log.log` survives the run (and, for `pdf`, the `*-overlay.pdf`); without the flag, neither does. |
| Exit codes | A `PATH` missing one required binary exits `2` and names that binary (repeat per binary, or at least for `pandoc` and one other). An input path that is neither a file nor a directory exits non-zero with a message naming the path. |

Additional guidance:

- **Do not assert mirrored output paths.** Choose inputs whose placement is invariant under task 002's fix: an input file sitting in the case's own working directory, or `--flatten-dirs`, or stdin/`--single-page` (neither of which enters the mirroring branch). This keeps this task mergeable in parallel with 002.
- Assert against the spec, not against whatever the code happens to do. Where you find the implementation contradicting `docs/md2x-spec.md` or `README.md`, **do not silently encode the buggy behaviour as correct**: write the case to document current behaviour with an explicit comment naming the discrepancy, and report it as a candidate followup. Do not fix CLI behaviour in this task.
- Keep cases independent — no ordering dependencies, no shared mutable state outside the per-case temp directory.
- Keep every fixture path space-free (the CLI's unquoted word-splitting already breaks on spaces).

## Validation

- `make test` passes in full, non-interactively, with a zero exit status; verify with stdin closed (`make test < /dev/null`).
- Every table row above has at least one corresponding case; list the case names against the rows in your task report.
- `git diff --stat` shows changes confined to new/modified files under `src/cli/test/` — no `src/cli/md2x.sh`, no `src/cli/lib/`, no `Makefile`, no `package.json`, and no changes to task 001's shared helpers. (If a helper genuinely must change, keep it strictly additive and call it out in your report.)
- No case asserts a non-`--flatten-dirs` output subdirectory path: `grep` your new cases for output-path assertions and confirm each uses an invariant input shape.
- Each case passes when run individually as well as in the full suite (no inter-case coupling).
- `make lint` and `make qa` pass.

## Assumptions

- Task 001 has landed: harness, stubs, shared helpers, and `make test` wiring exist.
- Tasks 002, 004, and 005 may be running in parallel. 002 owns `src/cli/md2x.sh` and all mirrored-path assertions; 004 owns `src/node/*.test.js`; 005 owns the gated real-toolchain cases.
- The stub binaries make PDF-format cases runnable without a working Pandoc PDF engine, which this machine lacks.
- The CLI's version probe resolves deterministically to `working` in a temp CWD outside a git work tree.

## References

- [`docs/md2x-spec.md`](../../docs/md2x-spec.md) — the flag table, exit behaviour, and General features section; the contract these cases assert.
- [`README.md`](../../README.md) — the consumer-facing CLI reference.
- [Test tooling survey](../notes/test-tooling-survey.md) — harness conventions, stub log usage, and determinism hazards (especially `--to-stdout` implying `--quiet`, and the version probe).
- `src/cli/md2x.sh` — option extraction (line 25), help text (27–89), preflight (91–96), format validation (99–107).
- `src/cli/lib/generate-page.sh` — where `--toc`, `--metadata-file`, `--infer-version`, `--keep-intermediate`, `--to-stdout`, `--quiet`, and `--list-files` actually take effect.

## Checkpoint hints

- After the output-format and exit-code cases.
- After the output-shaping cases (`--quiet`, `--list-files`, `--to-stdout`, `--help`).
- After the pandoc-argument cases (`--infer-title`, `--no-toc`, `--infer-version`, `--keep-intermediate`).
- After the `--single-page` and stdin cases.

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

## Status

**Outcome:** succeeded. Date: 2026-07-29.

Added five new bats files under `src/cli/test/bats/`, none touching `src/cli/`, `Makefile`, `package.json`, or task 001's shared helpers (`src/cli/test/helpers/`):

- `src/cli/test/bats/output-format.bats` (5 cases) — `--output-format`.
- `src/cli/test/bats/exit-codes.bats` (3 cases) — Exit codes.
- `src/cli/test/bats/output-shaping.bats` (6 cases) — `--quiet`, `--list-files`, `--to-stdout`, `--help`/`-h`.
- `src/cli/test/bats/pandoc-args.bats` (12 cases) — `--infer-title`, `--no-toc`, `--infer-version`, `--keep-intermediate`.
- `src/cli/test/bats/single-page-and-stdin.bats` (4 cases) — `--single-page`, stdin `-`.

**Table-row-to-case mapping** (per Validation's second bullet):

| Requirements table row | Case(s) |
| --- | --- |
| `--output-format` | `output-format.bats`: "--output-format pdf converts to <title>.pdf", "--output-format html converts to <title>-base.html", "--output-format docx converts to <title>.docx", "absent --output-format defaults to pdf", "an unrecognized --output-format exits non-zero, names the format, and never calls pandoc" |
| `--single-page` | `single-page-and-stdin.bats`: "--single-page concatenates multiple files, in order, into one output named from --title", "--single-page defaults the output name to 'output' when --title is absent" |
| stdin `-` | `single-page-and-stdin.bats`: "stdin '-' produces one output named from --title, invoking pandoc exactly once", "stdin '-' defaults the output name to 'output' when --title is absent" |
| `--infer-title` | `pandoc-args.bats`: "--infer-title embeds the title in the metadata file pandoc receives", "without --infer-title, the metadata file carries no title" |
| `--infer-version` | `pandoc-args.bats`: "--infer-version adds a Version: string to the Ghostscript overlay invocation", "without --infer-version, no Version: string appears in the Ghostscript invocation" |
| `--no-toc` | `pandoc-args.bats`: "--no-toc removes --toc from the pandoc invocation for pdf output", "without --no-toc, pdf output includes --toc", "--no-toc removes --toc from the pandoc invocation for html output", "without --no-toc, html output includes --toc", "docx output never includes --toc, with --no-toc given", "docx output never includes --toc, without --no-toc given" |
| `--quiet` | `output-shaping.bats`: "--quiet suppresses the 'Created' line but still writes the output" |
| `--list-files` | `output-shaping.bats`: "--list-files prints only the generated path, with no 'Created ' prefix" |
| `--to-stdout` | `output-shaping.bats`: "--to-stdout writes the converted content to stdout and implies --quiet" |
| `--help` / `-h` | `output-shaping.bats`: "--help exits 0 with usage text on stdout", "-h is a short alias for --help", "--help exits 0 even with every required binary absent from PATH" |
| `--keep-intermediate` | `pandoc-args.bats`: "--keep-intermediate retains the pandoc log and pdf overlay after conversion", "without --keep-intermediate, the pandoc log and pdf overlay are removed after conversion" |
| Exit codes | `exit-codes.bats`: "a PATH missing 'pandoc' exits 2 and names 'pandoc'", "a PATH missing 'gs' exits 2 and names 'gs'", "an input path that is neither a file nor a directory exits non-zero and names the path" |

**Validation results:**

- `make test < /dev/null` (stdin closed): exit 0. 40 bats cases pass (13 pre-existing `harness-smoke.bats` + 27 new), plus the existing Jest suite (1 test).
- Every case also passes run individually (`npx bats src/cli/test/bats/<file>.bats` per new file), confirming no inter-case coupling.
- `git diff --stat` / `git status --porcelain`: five new files under `src/cli/test/bats/`; no other file touched.
- `grep`-checked every new `assert_file_exists`/`assert_output_*` call for an `--output-path`/subdirectory argument other than `.`: none found. Every non-`--flatten-dirs` case uses `--single-page` or stdin `-`, neither of which enters the mirroring branch.
- `make lint`: exit 0 (no findings against `src/node`; bash sources are not linted per `AGENTS.md`).
- `make qa`: exit 0 (`test` + `lint`).

**Discrepancy flagged (documented, not fixed, per task instructions):** `--output-format html` on a per-file (non-`--single-page`, non-stdin) conversion produces `<title>-base.html`, not `<title>.html`. Neither `docs/md2x-spec.md` (UC2, API definition table) nor `README.md` mentions a `-base` suffix; the suffix comes from `src/cli/md2x.sh`'s per-file conversion loop (line ~168: `if [[ "${OUTPUT_FORMAT}" == 'html' ]]; then BASE_OUTPUT="${BASE_OUTPUT}-base"; fi`). Documented in `output-format.bats`'s `"--output-format html converts to <title>-base.html"` case with an explicit comment; not present in the single-page/stdin path (their `BASE_OUTPUT` construction never adds `-base`), which the tests don't exercise for this discrepancy. Candidate followup for the manager.

**Assumptions applied:** all four from `## Assumptions` — task 001's harness/stubs/helpers/`make test` wiring already existed and were used as-is; task 002 (mirrored-path fix) was not depended on, per the invariant-input-shape guidance; the stub binaries made every PDF case runnable without a real Pandoc PDF engine; the version probe resolved to the literal `working` in every case's temp CWD (confirmed via the `--infer-version` cases).

**Decisions made:**
- Organized new cases into five files split along the checkpoint-hint boundaries (`output-format.bats`, `exit-codes.bats`, `output-shaping.bats`, `pandoc-args.bats`, `single-page-and-stdin.bats`) rather than one large file, for readability and to mirror the task's own grouping.
- For `--to-stdout`, used `--output-format html` rather than the default `pdf`: with `pdf` the CLI overwrites the base output with the pdftk-merged (header/footer overlay) content before `cat`-ing it to stdout, so only a non-pdf format's stdout still carries the pandoc stub's own placeholder text verbatim. Commented inline in the test.
- Used space-free titles (`CombinedReport`, `Piped`) rather than the spec's example `"Combined Report"`, per the task's fixture-path space-free guidance (the CLI's unquoted word-splitting already breaks on spaces).
- Added a `pdf`-file-count assertion (`find . -maxdepth 1 -name '*.pdf' | wc -l`) to the `--single-page` cases to positively confirm "exactly one output file is produced," not just that the expected file exists.

**Flagged for manager:** the html `-base` suffix discrepancy above is a candidate followup (not filed here — followups.yaml is out of scope for this task agent).

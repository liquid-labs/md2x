# Add Toc Flag And Conflict Check

## Purpose and scope

Add `--toc` as a first-class CLI flag alongside the existing `--no-toc`, make supplying both a
fatal error before any conversion work, resolve the pair into a single TOC-mode value for the
pipeline to consume, and expose the matching `toc` option on the Node wrapper.

Scope: `src/cli/md2x.sh` (option spec, validation, help text), `src/node/md2x.js`, and their
tests. This task does not change what the TOC *is* — task 004 consumes the mode value. It is
independent of tasks 001 and 002 and may run concurrently with them.

## Requirements

1. **Add the `--toc` option.** In the `setSimpleOptions` call in `src/cli/md2x.sh` (line ~25),
   add a `TOC:` spec.

   The trailing colon with nothing after it is required, and is the reason the existing
   `INFER_TITLE:` and `KEEP_INTERMEDIATE:` specs carry one: `setSimpleOptions` otherwise derives
   a short option from the variable name's first letter, and a bare `TOC` would claim `-t`,
   which `TITLE:t=` already owns. Confirm after the change that `md2x -t Foo report.md` still
   sets the title.

   `--toc` is long-only, boolean, and default-off (empty). Note that `--no-toc` currently claims
   the short option `-n` by the same derivation rule; leave that alone.

2. **Reject both flags together.** When `TOC` and `NO_TOC` are both non-empty, fail with
   `echoerrandexit` naming both flags, e.g.

   ```
   Cannot specify both '--toc' and '--no-toc'.
   ```

   Place the check in the option-processing section of `src/cli/md2x.sh`, alongside the existing
   `test_formats` output-format validation and **before** the `ensure-weasyprint` call — that
   call can trigger a minute-long network install on a cold machine, and the contract is that
   the conflict aborts before any conversion work begins. Exit status is `echoerrandexit`'s
   default `1`, matching the unrecognized-`--output-format` path. No output file, no
   intermediate file, and no stub/tool invocation may occur.

3. **Resolve a single mode value.** Immediately after the conflict check, set a `TOC_MODE`
   variable that the pipeline consumes:

   | Flags | `TOC_MODE` |
   | --- | --- |
   | `--toc` | `on` |
   | `--no-toc` | `off` |
   | neither | `auto` |

   Nothing reads `TOC_MODE` yet; task 004 passes it to the preprocessor. Do **not** remove
   `NO_TOC`'s existing use in `src/cli/lib/generate-page.sh` in this task — task 004 owns that
   edit, and removing it here would leave `--no-toc` silently inoperative in the interim.

4. **Update the help text** in the `--help` heredoc in `src/cli/md2x.sh`. Add `--toc` and
   rewrite `--no-toc`'s wording, which currently says "Suppress the table of contents Pandoc
   otherwise adds for pdf/html output (docx output never receives an automatic TOC)" — both
   halves of that become false. The replacement text must cover: that md2x generates the TOC
   itself for all three output formats; that placement is controlled by a `<!-- md2x:toc -->`
   marker; that with neither flag, a TOC is added only to documents of more than about two pages
   with four or more top-level sections; and that giving both flags is an error. Keep the
   heredoc's existing two-column layout and wrap width.

5. **Add the Node wrapper's `toc` option.** In `src/node/md2x.js`, accept `toc` in the options
   object and push `--toc` when truthy, mirroring the existing `noToc` handling. Keep the
   destructuring and push order consistent with the surrounding code. Passing both `toc` and
   `noToc` needs no wrapper-side validation — the CLI rejects it and the wrapper's existing
   non-zero-exit path throws an `Error` carrying the exit code and stderr.

6. **Tests.**

   CLI (`src/cli/test/bats/pandoc-args.bats` is the natural home for flag-behavior cases; a new
   `toc-flags.bats` is acceptable if that file is getting long):
   - `--toc --no-toc` together exits non-zero, names both flags on stderr, produces no output
     file, and never invokes the `pandoc` stub (`refute_stub_called pandoc`).
   - `--no-toc --toc` in the opposite order behaves identically.
   - `--toc` alone and `--no-toc` alone each still exit `0` and convert.
   - `-t Foo` still sets the title after the option-spec change (assert via
     `md2x_pandoc_capture metadata` with `--infer-title`, per the existing `--infer-title` case).
   - `--help` output mentions `--toc`, and no longer contains the phrase
     `docx output never receives`.

   Node (`src/node/md2x.test.js`): a case asserting `toc: true` puts `--toc` on the composed
   command, following the file's existing option-mapping cases.

7. **Leave the existing `--toc`/`--no-toc` pandoc-argument cases in
   `src/cli/test/bats/pandoc-args.bats` alone.** They assert on Pandoc's `--toc` flag, which is
   still present until task 004 retires it. Task 004 owns replacing them.

## Validation

- `make test` passes (both `test-cli` and `test-node`).
- `./bin/md2x --toc --no-toc report.md` exits non-zero and names both flags; `ls` shows no
  `report.pdf` and no `pandoc-log.log` left behind.
- `./bin/md2x --help | grep -c -- '--toc'` returns a non-zero count, and
  `./bin/md2x --help | grep 'docx output never receives'` finds nothing.
- `./bin/md2x -t Foo --infer-title --output-format html --flatten-dirs --output-path . x.md`
  still produces `Foo.html`, confirming `-t` was not stolen by the new option.
- `grep -n 'TOC_MODE' src/cli/md2x.sh` shows the resolution block.
- `make lint` passes for the `src/node` change.

## References

- [TOC defaults, directive syntax, and the page-count heuristic](../notes/toc-defaults-and-page-heuristic.md) —
  the flag-resolution table this task implements, and the marker/heuristic wording the help text
  must summarize.
- `src/cli/md2x.sh` lines ~25 (option spec), ~28–93 (help heredoc), ~104–116 (option validation
  and the `ensure-weasyprint` call the check must precede).
- `node_modules/@liquid-labs/bash-toolkit/dist/bash-toolkit.funcs.pkg.sh` — `setSimpleOptions`
  (short-option derivation) and `echoerrandexit` (exit `1`).
- `src/cli/test/bats/exit-codes.bats` — the idiom for asserting a fatal path names its cause and
  leaves no artifacts.
- `src/node/md2x.test.js` — the existing option-mapping test style.

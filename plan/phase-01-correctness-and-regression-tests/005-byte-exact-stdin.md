# Byte-Exact Stdin

## Purpose and scope

Fix B2. Today `md2x -` reads stdin with `while read LINE`, without `IFS=` or `-r`. That strips leading indentation, eats backslashes, and drops a final line that has no trailing newline. Empty stdin exits 0 with nothing written. This task makes stdin a byte-exact copy into the work directory, and makes empty stdin a usage error. No standard skill covers this; follow the role doc and the requirements below.

In scope: `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`, and the stdin bats cases.

Out of scope:

- mixing `-` with other arguments (Phase 2, S15)
- the Node wrapper's stdin use (Phase 2)
- the UTF-8 and NUL check (Phase 2, N7)

## Requirements

- `role_doc: plugins/flow/roles/developer-bash.md`
- **Capture.** When the sole argument is `-`, copy stdin byte for byte into the work directory with `cat > "${WORK}/stdin.md"`, using whatever name task 004 gave the work-directory variable.
  - The `while read LINE` loop goes away.
  - The capture must happen after the work directory exists. If that means moving the work-directory creation earlier, keep task 004's rule that a usage error found before capture does not leave a work directory behind.
- **Empty stdin.** A zero-byte capture is a usage error. Report it through task 001's usage helper: exit 2, a `md2x: ` message such as `no input on stdin`, and the usage hint.
  - Whitespace-only input is not empty, and converts normally.
- **Retire `INPUT`.** `generate-page()` always reads `MD_FILE`. For stdin that is the captured file.
  - Replace every `[[ -z "${INPUT}" ]]` / `[[ -n "${INPUT}" ]]` mode test in `md2x.sh` (the `--title` precedence gate and the main-loop branches) with an explicit stdin-mode flag.
  - Remove the `printf '%s\n' "${INPUT}"` branch in `generate-page.sh`.
- **No added newline.** The bytes reaching the TOC preprocessor are exactly the bytes read from stdin. The old path appended a newline.
  - Confirm that the TOC preprocessor itself copes with a document that has no trailing newline.
  - If the preprocessor's output differs only by a final newline, record that in the report. Do not change `toc-preprocess.py`; it is owned by the Phase 3 psgq task.
- **Regression tests.** Add these in `single-page-and-stdin.bats`, driving stdin through `md2x_run - < file` or a `printf` pipe. Each must fail on the pre-change code.
  - A document with a 4-space-indented code line keeps the indentation in pandoc's captured input.
  - A line containing `two\nslash`, with a literal backslash, keeps the backslash.
  - A final line `last` with no trailing newline is present in pandoc's captured input.
  - Empty stdin (`< /dev/null`) exits 2 with the hint, and creates no output file.
  - Use pandoc's captured input from the stub capture directory. Compare it exactly where possible; the stub's `$(cat …)` capture strips trailing newlines, so compare content, not the final newline.
- **Real toolchain.** Add one gated case to `real-toolchain-e2e.bats`: indented code from stdin renders as `<pre>`/`<code>` in HTML.
- Keep the code bash 3.2-compatible. Run the suite under `MD2X_TEST_BASH=/bin/bash`.

## Validation

- `make qa` passes, and the bats suite also passes under `MD2X_TEST_BASH=/bin/bash`.
- `grep -n "INPUT" src/cli/md2x.sh src/cli/lib/generate-page.sh` returns no references to the retired `INPUT` variable. Names such as `INPUT_*` used for something else are fine; list any in the report.
- `printf '# T\n\n    indented\n\n  two\\nslash\n' | bin/md2x -F html -p out -` with the real toolchain produces HTML containing a `<pre>` block and `two\nslash`.
- `printf '# T\n\nlast' | bin/md2x -F html -p out -` produces HTML containing `last`.
- The new regression cases fail against the pre-change build. Confirm this and report it.

## Assumptions

- Tasks 001 to 004 are complete. The work directory and its cleanup trap exist.

## References

- [Design decisions: stdin](../notes/design-decisions.md#stdin).
- `.flow/audit-interface.md` B2, under the project root: the reproduction commands used in Validation.
- `src/cli/test/helpers/common.bash` `md2x_run`: it inherits stdin, so a redirect drives the `-` mode.

## Status

succeeded, 2026-10-04. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` pass. New stdin regression cases fail on pre-change code (4 of 5; whitespace-only case passes both ways by design) and pass now. Real-toolchain checks produce `<pre>`, `two\nslash` and `last`. `toc-preprocess.py` keeps a missing final newline unchanged. Retired `INPUT` is gone; remaining `INPUT_LABEL` is the error-message label. Files: `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`, `src/cli/test/bats/single-page-and-stdin.bats`, `src/cli/test/bats/real-toolchain-e2e.bats`.

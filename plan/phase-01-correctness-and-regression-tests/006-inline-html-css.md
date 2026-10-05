# Inline HTML CSS

## Purpose and scope

Fix B3. HTML output today carries `<link rel="stylesheet" href="…/md2x-css.XXXXXX.css">`, which points at a temp file deleted at exit, so every HTML file is unstyled once the run ends. This task embeds the bundled GitHub CSS inline as a `<style>` block, so HTML output never references `TMPDIR` or the work directory. No standard skill covers this; follow the role doc and the requirements below.

In scope:

- `src/cli/lib/generate-page.sh`
- `src/cli/md2x.sh`, only if the CSS setup moves
- the pandoc stub
- the affected bats cases and real-toolchain e2e cases

Out of scope:

- Embedding images, or a self-contained HTML option. Both are filed as out of scope.
- Pruning WeasyPrint warnings from `github.css` (Phase 2, S12).

## Requirements

- `role_doc: plugins/flow/roles/developer-bash.md`
- **HTML.** For `--output-format html`, do not pass `--css`. Instead:
  - Write a work-directory file, such as `style.html`, holding `<style>`, the embedded `${CSS}` content, and `</style>`.
  - Pass it with `--include-in-header`.
  - Keep the existing `markdown-body` wrapper (`--include-before-body`/`--include-after-body`).
- **PDF.** PDF may keep `--css <work-dir>/github.css`. WeasyPrint reads it during the run, and that file is in the work directory after task 004.
  - Moving PDF to the inline approach is allowed only if the real-toolchain PDF output is unchanged. If you try it, compare the rendered result and record the comparison in the report. Otherwise leave PDF as it is.
- **DOCX.** Behavior is unchanged. The current `--css` argument has no effect on DOCX. You may drop it for DOCX; if you do, update the affected assertions.
- **Stub.** Teach `src/cli/test/stubs/pandoc` that `--include-in-header` takes a value.
  - Today its catch-all `-*` arm consumes only the flag, so the following path would be misread as the input file.
  - Capture the header file's content as `pandoc-<n>-header`, alongside the existing captures.
  - Update the stub's header comment listing the captured arguments.
  - Add a matching accessor to `src/cli/test/helpers/stub-log.bash` if the existing `md2x_pandoc_capture` does not already handle arbitrary capture names.
- **Regression tests.** Each must fail on the pre-change code.
  - Stub suite, in `pandoc-args.bats`:
    - The HTML pandoc invocation has no `--css` argument, according to the stub log.
    - The `--include-in-header` capture starts with `<style>`, ends with `</style>`, and contains a recognizable `github.css` rule such as `.markdown-body`.
    - The PDF invocation still passes a `.css` path.
  - Real toolchain, in `real-toolchain-e2e.bats` and gated like the existing cases:
    - The HTML output contains `<style>`.
    - It contains no `<link rel="stylesheet"`.
    - It contains no `href` or `src` value that contains the value of `TMPDIR` or `/md2x.`.
- Update the existing harness-smoke and pandoc-args cases that assert the HTML `--css` argument or the CSS capture.
- Keep the code bash 3.2-compatible. Run the suite under `MD2X_TEST_BASH=/bin/bash`.

## Validation

- `make qa` passes, and the bats suite also passes under `MD2X_TEST_BASH=/bin/bash`.
- Real-toolchain e2e passes locally.
- A manual HTML conversion of `src/cli/test/tiny-doc.md`, opened after the run, is styled. Report that this check was done.
- The new stub and e2e assertions fail against the pre-change build. Confirm this and report it.

## Metadata

architectural_impact: true

## Assumptions

- Tasks 001 to 005 are complete. The work directory exists, and the CSS file lives there under a fixed `.css` name.

## References

- [Design decisions: HTML styling](../notes/design-decisions.md#html-styling).
- `.flow/audit-interface.md` B3, under the project root.
- `docs/architecture.md`, "Bundled stylesheet": the current CSS data flow this changes. Phase 4 updates the doc; do not edit it here.

## Status

succeeded (2026-10-04). HTML now embeds github.css inline via `--include-in-header` (work-dir `style.html`); PDF keeps `--css`; DOCX no longer receives `--css`. Stub captures `pandoc-<n>-header`. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` pass; new HTML stub/e2e cases fail on pre-change code. PDF left unchanged. Files: `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`, `src/cli/test/stubs/pandoc`, `src/cli/test/helpers/stub-log.bash`, `src/cli/test/bats/{pandoc-args,pandoc-stream-handling,real-toolchain-e2e}.bats`.

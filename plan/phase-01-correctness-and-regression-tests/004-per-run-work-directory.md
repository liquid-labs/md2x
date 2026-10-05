# Per-Run Work Directory

## Purpose and scope

Move every intermediate file into one per-run work directory, so nothing but the requested outputs is ever written to the cwd or the output directory. This fixes:

- B1: `--single-page -t X` deletes the user's `X.md`.
- S13: `pandoc-log.log` and the combined file are left in the cwd.
- N6: `--keep-intermediate` does not report every kept path.

It also gives tasks 005 to 007 a place for captured stdin, the inline-CSS header file, and the overlay. No standard skill covers this; follow the role doc and the requirements below.

In scope:

- `src/cli/md2x.sh`
- `src/cli/lib/generate-page.sh`
- the pandoc and gs stubs, only if their argument handling must change
- the bats files whose assertions reference intermediate paths or the old `--keep-intermediate` notices

Out of scope:

- stdin capture (task 005)
- inline HTML CSS (task 006)
- title escaping (task 007)
- `--to-stdout` purity (Phase 2)

## Requirements

- `role_doc: plugins/flow/roles/developer-bash.md`
- **One work directory per invocation.**
  - Create it with `mktemp -d` and a trailing-`X` template, for example `"${TMPDIR:-/tmp}"` with any trailing `/` stripped, then `/md2x.XXXXXX`. BSD `mktemp` only randomizes trailing `X`s.
  - Create it once, after option and input validation and before any conversion work. A usage error must not create it at all.
  - A mktemp failure is a runtime error (exit 1), reported through the task 001 helper.
- **Move every intermediate into it, under fixed names:**
  - The CSS file. Today it is `CSS_TMP_FILE` in `TMPDIR`, with a rename to add the `.css` suffix. In the work directory it gets a fixed `.css` name, such as `github.css`, so the rename dance goes away. Keep the comment explaining why WeasyPrint needs a real `.css` path.
  - The body-open and body-close include files. Create them once per run, not once per `generate-page` call.
  - The TOC-preprocessed Markdown. A per-call name inside the work directory is fine.
  - The `--single-page` concatenation. Use a fixed name such as `single-page.md`, **never derived from `--title`**. Delete the pre-existing-file `rm` of `${TITLE:-input}.md` in the cwd outright.
  - The search-root error signal file (`SEARCH_ROOT_ERROR_TMP_FILE`).
  - The pandoc log (`--log`). Today it is `pandoc-log.log` in the cwd.
  - The PDF overlay. Today it is `${OUTPUT_PATH}/${TITLE}-overlay.pdf`. Give it a fixed or per-call name in the work directory, not derived from the title.
  - The pdftk multistamp output. Today it is `${TITLE}-combined.pdf` in the cwd. Write it in the work directory, then `mv` it to the final output path.
- **One cleanup trap.** Replace the existing multi-file `EXIT` trap with one that removes the work directory: `rm -rf` on the work-directory variable, guarded so it is a no-op when the variable is unset.
  - It must fire on success, on errexit, and on every `md2x-die-*` path.
  - Preserve any exit-status normalization task 001 added to the trap.
  - Remove the per-call `rm` lines in `generate-page()`. The trap covers them.
  - Remove the `flSJ` workaround and its comment. With one fixed concatenation path in the work directory, the `SINGLE_PAGE_COMBINED_FILE` name clash with `generate-page()`'s own `COMBINED_FILE` no longer matters. Make `generate-page()`'s variables `local` where practical.
- **`--keep-intermediate`.** Keep the work directory instead of removing it, and print its path once to stderr: `md2x: kept intermediate files in '<dir>'`.
  - This replaces the two existing per-file notices, for the CSS file and the combined file.
  - Print it regardless of `--quiet`. It never goes to stdout.
  - Update the help text for `--keep-intermediate` only as far as it now describes a work directory instead of the log and overlay. Phase 2 does the full help parity work (D17).
- **Regression tests.** Add these in a new `src/cli/test/bats/work-directory.bats`, or in `single-page-and-stdin.bats`. Each must fail on the pre-change code.
  - B1: in a case directory holding `README.md` and `two.md`, `md2x -F html --single-page -t README README.md two.md` leaves `README.md` present and unchanged, and pandoc's captured input contains both documents.
  - A pre-existing `input.md` in the cwd survives `md2x --single-page a.md b.md`.
  - After an HTML, a PDF, and a `--single-page` PDF run, the cwd and the output directory contain only the inputs and the requested outputs. In particular there is no `pandoc-log.log`, no `*-combined.pdf`, and no `*-overlay.pdf`.
  - With `TMPDIR` set to an empty case-private directory, that directory is empty after a successful run and after a failed run (pandoc stub `MD2X_TEST_STUB_EXIT_CODE=1`).
  - With `--keep-intermediate`, stderr names one directory. That directory exists and contains the CSS file, the pandoc log, and, for PDF, the overlay.
- **Update existing tests** that assert the old intermediate locations or notices. Likely ones are `output-shaping.bats`, `pandoc-args.bats`, `harness-smoke.bats`, and `single-page-and-stdin.bats`.
  - Update the stub header comments in `src/cli/test/stubs/pandoc` and `gs`, which describe `pandoc-log.log` and the overlay path.
- Keep the `Created <file>` and `--list-files` stdout contracts byte-identical.
- Keep the code bash 3.2-compatible. Run the suite under `MD2X_TEST_BASH=/bin/bash`.

## Validation

- `make qa` passes, and the bats suite also passes under `MD2X_TEST_BASH=/bin/bash`.
- `grep -n "pandoc-log.log\|-combined\|-overlay\|CSS_TMP_FILE\|TMPDIR" src/cli/md2x.sh src/cli/lib/generate-page.sh`: every remaining hit is the work-directory creation or a work-directory-relative path.
- `grep -n 'rm "\${SINGLE_PAGE_COMBINED_FILE}"\|TITLE:-input' src/cli/md2x.sh` returns nothing.
- The real-toolchain e2e file (`real-toolchain-e2e.bats`) passes locally, and a real PDF run leaves no stray files in the cwd.
- The new regression cases fail against the pre-change build. Confirm this and report it.

## Metadata

architectural_impact: true

## Assumptions

- Tasks 001 to 003 are complete.
- The `INPUT` variable and the `while read LINE` stdin loop are still present. Task 005 replaces them. This task must not break the stdin path, but it need not fix it.

## References

- [Design decisions: per-run work directory](../notes/design-decisions.md#per-run-work-directory).
- `.flow/audit-interface.md` B1, S13, and N6, under the project root: the reproductions.
- Existing comments in `src/cli/md2x.sh` about the `EXIT` trap and followups 9hZL, MwYH, QBKX, and flSJ. These explain the lifecycle this task simplifies.

## Checkpoint hints

- After the work directory and trap exist, with CSS and the body files moved.
- After the single-page, log, overlay, and combined paths are moved.
- After `work-directory.bats` and the existing-test updates.

## Status

- Outcome: succeeded (2026-10-04).
- One `mktemp -d` work directory per run (`src/cli/md2x.sh`), created after option/input validation, removed by a single `EXIT` trap unless `--keep-intermediate`; kept path printed once to stderr. Fixed names: `github.css`, `body-open.html`, `body-close.html`, `preprocessed.md`, `single-page.md`, `pandoc.log`, `overlay.pdf`, `combined.pdf`, `search-root-error`. `generate-page` (`src/cli/lib/generate-page.sh`) no longer creates or removes files; its variables are `local`.
- Validation: `make qa` passes; `MD2X_TEST_BASH=/bin/bash make test-cli` passes (193 cases, including real-toolchain e2e); real PDF run left only the input and output in cwd and an empty TMPDIR.
- New tests: `src/cli/test/bats/work-directory.bats`. Pre-change, cases 1, 2, 5, 7, 8 fail; cases 3, 4, 6 pass on the old code because it already cleaned up on success and usage errors.
- Docs updated for the changed `--keep-intermediate` behavior: README.md, docs/md2x-spec.md, docs/architecture.md.

# Fix Single Page Combined File Naming

## Purpose and scope

`md2x --single-page` without `--title` concatenates its inputs into one filename and then tells
`generate-page()` to read a different one, so it silently converts an empty document. Fix the
naming, and tighten the bats case that currently passes without noticing.

This is a prerequisite for task 004: that task materializes the preprocessed Markdown into a
real file instead of a process substitution, which makes the failing `cat` visible to
`errexit` — turning today's silent empty output into a hard test failure. Fix it first.

Scope: `src/cli/md2x.sh` and `src/cli/test/bats/single-page-and-stdin.bats`. No new behavior.

## Requirements

1. **The defect.** In `src/cli/md2x.sh`:
   - line ~193 sets `COMBINED_FILE="${TITLE:-input}.md"` while `TITLE` is still the raw option
     value, so with no `--title` it resolves to `input.md`;
   - line ~277 then sets `TITLE="${TITLE:-output}"`;
   - line ~280 sets `MD_FILE="${TITLE:-input}.md"`, which now resolves to `output.md` — a file
     that does not exist.

   Reproduce it before changing anything:

   ```bash
   cd "$(mktemp -d)" && printf '# Alpha\n' > a.md && printf '# Beta\n' > b.md
   <repo>/bin/md2x --single-page --output-format html --output-path . a.md b.md
   # observe: "cat: output.md: No such file or directory", exit 0, empty ./output.html
   ```

2. **The fix.** Make the single-page branch read the file it actually wrote: set
   `MD_FILE="${COMBINED_FILE}"` in the `[[ -n "${SINGLE_PAGE}" ]]` case rather than
   re-deriving the name from `TITLE`. Keep the stdin (`INPUT`) path unchanged — it does not use
   `MD_FILE` at all.

   Note that the two situations share one `if [[ -n "${SINGLE_PAGE}" ]] || [[ -n "${INPUT}" ]]`
   block, so `MD_FILE` must only be reassigned on the single-page side. Also note that
   `generate-page()` reassigns the global `COMBINED_FILE` for its own PDF-overlay merge target
   (`src/cli/lib/generate-page.sh` line ~152): read `COMBINED_FILE` into `MD_FILE` *before*
   calling `generate-page`, which the existing ordering already does.

   Do **not** change the output filename: `--single-page` without `--title` must still produce
   `output.<format>`.

3. **Tighten the existing test.** `src/cli/test/bats/single-page-and-stdin.bats` has a case
   `"--single-page defaults the output name to 'output' when --title is absent"` that asserts
   only that `./output.pdf` exists — which was true even while the document was empty. Add
   assertions, in the style the sibling case at the top of that file already uses, that the
   buffer pandoc received (`md2x_pandoc_capture input`) contains both chapters' headings in
   order.

4. **Add a regression case** asserting that the CLI writes no `cat: … No such file` diagnostic
   to stderr on that invocation (`refute_stderr_contains`), so a future regression is caught by
   the symptom as well as the content.

5. Do not attempt to fix either of the two adjacent warts recorded in
   `plan/notes/pipeline-verification.md` (the orphan concatenation file left in the working
   directory; `generate-page()`'s shadowing of `COMBINED_FILE`). They are out of scope and are
   being tracked separately.

## Validation

- `make test-cli` passes, including the two modified/added cases in
  `src/cli/test/bats/single-page-and-stdin.bats`.
- The manual reproduction in requirement 1, re-run after the fix, produces a non-empty
  `./output.html` containing both headings and emits no `cat:` diagnostic.
- `git diff src/cli/md2x.sh` shows a single-line change in the single-page/stdin call-site
  block and nothing else.
- `grep -n 'MD_FILE=' src/cli/md2x.sh` shows the single-page assignment now referencing
  `COMBINED_FILE`.

## References

- [Pipeline verification and an adjacent defect](../notes/pipeline-verification.md) — the
  reproduction, why this blocks task 004, and the two out-of-scope warts.
- `src/cli/md2x.sh` lines ~192–196 and ~276–282 — the two halves of the defect.
- `src/cli/test/bats/single-page-and-stdin.bats` — the case to tighten; its first case shows the
  ordering-assertion idiom to copy.

## Status

- **Outcome:** succeeded
- **Date:** 2026-07-30
- **Validation summary:** `make test-cli` passes (72/72, including the two modified/added
  assertions in `single-page-and-stdin.bats`). Manual reproduction re-run after the fix
  produces a non-empty `output.html` containing both `Alpha` and `Beta` headings, exits 0,
  and emits no `cat:` diagnostic on stderr. `git diff src/cli/md2x.sh` shows a single-line
  change in the single-page/stdin call-site block. `grep -n 'MD_FILE=' src/cli/md2x.sh`
  shows the single-page assignment now referencing `COMBINED_FILE`.
- **Affected source files:**
  - `src/cli/md2x.sh`
  - `src/cli/test/bats/single-page-and-stdin.bats`
- **Decisions:** `MD_FILE="${COMBINED_FILE}"` is guarded with
  `[[ -z "${SINGLE_PAGE}" ]] || MD_FILE="${COMBINED_FILE}"` rather than an unconditional
  assignment, per the task doc's note that `MD_FILE` must only be reassigned on the
  single-page side of the shared `if` block — an unconditional assignment would dereference
  `COMBINED_FILE` (unset under `nounset` on the stdin-only path, since it is only set inside
  the earlier `[[ -n "${SINGLE_PAGE}" ]]` block) and break the untouched stdin path. This
  keeps the diff to one changed line, as the Validation section requires, while leaving
  `MD_FILE` unset (and unused, since `generate-page()`'s `INPUT` branch never reads it) on
  the stdin path.
  - Requirement 4's regression assertion (`refute_stderr_contains 'cat:'`) was folded into
    the same tightened test case as requirement 3's content assertions, rather than added as
    a separate `@test`, since both apply to "that invocation" (the single `md2x_run` call in
    the existing `--title`-absent case).

# Fix HTML Output Filename To Drop -base Suffix

## Purpose and scope

Closes followup `c2s9`. In `src/cli/md2x.sh`'s per-file conversion loop, `--output-format html` on a per-file (non-`--single-page`, non-stdin) conversion writes `<title>-base.html` instead of `<title>.html` — inconsistent with `pdf`/`docx` naming (`<title>.pdf`, `<title>.docx`) and undocumented anywhere in `docs/md2x-spec.md` or `README.md`. Change the naming so HTML output matches the other two formats: `<title>.html`.

## Requirements

- In `src/cli/md2x.sh`, remove the `-base` suffix logic: `if [[ "${OUTPUT_FORMAT}" == 'html' ]]; then BASE_OUTPUT="${BASE_OUTPUT}-base"; fi` (around line 260, in the per-file loop). After the fix, `BASE_OUTPUT` should be `<title>.html` for HTML output, exactly parallel to `<title>.pdf`/`<title>.docx`.
  - This applies only to the per-file loop branch (`[[ -z "${INPUT}" ]]` && not `SINGLE_PAGE`). The `--single-page`/stdin branch (further down in `md2x.sh`) already writes `${OUTPUT_PATH}/${TITLE:-output}.${OUTPUT_FORMAT}` with no `-base` suffix — confirm it is unaffected (it should need no change).
- Update every bats case that currently encodes or asserts the old `-base.html` naming:
  - `src/cli/test/bats/output-format.bats` — the `"--output-format html converts to <title>-base.html"` case (lines ~31-45): rename the test title, update its explanatory comment (which currently frames the `-base` suffix as undocumented/candidate-followup behavior — that framing is now stale), and change its assertions from `assert_file_exists './report-base.html'` / `assert_file_not_exists './report.html'` to the inverse (`assert_file_exists './report.html'`, and drop or invert the not-exists assertion as appropriate).
  - `src/cli/test/bats/harness-smoke.bats` — the `"harness: an html conversion leaves the pdf-only tools untouched"` case (around line 59-69) asserts `assert_file_exists './report-base.html'`; update to `'./report.html'`.
  - `src/cli/test/bats/real-toolchain-e2e.bats` — the `"e2e: tiny-doc.md converts to real HTML with recognizable Pandoc/CSS markup"` case (around lines 149-169) references `'./tiny-doc-base.html'` four times (`assert_file_exists`, `e2e_assert_nonempty`, and two `assert_file_contains` calls); update all four to `'./tiny-doc.html'`.
  - Grep the whole `src/cli/test/` tree for any other `-base.html`/`-base\.html`/`report-base` occurrence you may have missed after making these changes; there should be none left.
- Update documentation:
  - `docs/md2x-spec.md`'s UC2 ("Convert a Markdown file to HTML or DOCX") outcome text currently doesn't state an HTML output filename at all; add a short clause naming the convention (`<title>.html`) parallel to how UC1 states `report.pdf` for the PDF case, so the fixed naming is explicitly documented going forward (closing the "undocumented" half of this followup, not just the bug).
  - Confirm neither `README.md` nor `docs/md2x-spec.md` describes or implies the old `-base` suffix anywhere (the followup states it was undocumented, so this is a confirm-and-add-clarity step, not a correction of existing wrong text — but grep both files for `-base` to be sure before concluding there's nothing to fix).
- No change is needed to `src/node/md2x.js` or its tests — the Node library shells out to the same CLI and passes `format` straight through as `--output-format`; the fixed CLI behavior flows through automatically. Confirm this by inspection (do not add a redundant Node-side test asserting CLI output-filename behavior; that's the bats suite's job).

## Validation

- `make test` passes, including all updated/renamed bats cases.
- `grep -rn -- '-base\.html\|report-base\|tiny-doc-base' src/cli/test/ docs/ README.md` returns no hits.
- Manually confirm (via the updated bats assertions) that `md2x --output-format html report.md` now produces `report.html`, not `report-base.html`.
- `docs/md2x-spec.md`'s UC2 section names the `<title>.html` convention.

## References

- `src/cli/md2x.sh` line ~260 — the `-base` suffix logic to remove.
- `src/cli/test/bats/output-format.bats`, `src/cli/test/bats/harness-smoke.bats`, `src/cli/test/bats/real-toolchain-e2e.bats` — bats cases to update.
- `docs/md2x-spec.md` — UC2 and the API definition table.
- `README.md` — CLI reference table (`--output-format` row) and Usage examples.
- `plan/followups.yaml` item `c2s9` — full original followup text.

## Status

- **Outcome:** succeeded
- **Date:** 2026-07-30
- **Validation summary:** `make test` green (66/66 bats cases, 17/17 jest tests). `grep -rn -- '-base\.html\|report-base\|tiny-doc-base' src/cli/test/ docs/ README.md` returns no hits.
- **Affected files:**
  - `src/cli/md2x.sh` — removed the `-base` suffix conditional in the per-file conversion loop; confirmed the `--single-page`/stdin branch was already unaffected.
  - `src/cli/test/bats/output-format.bats` — renamed the HTML case to `"--output-format html converts to <title>.html"`, refreshed its comment, and asserted `./report.html` instead of `./report-base.html`.
  - `src/cli/test/bats/harness-smoke.bats` — updated the "html conversion leaves the pdf-only tools untouched" case to assert `./report.html`.
  - `src/cli/test/bats/real-toolchain-e2e.bats` — updated all four `./tiny-doc-base.html` references to `./tiny-doc.html`.
  - `docs/md2x-spec.md` — UC2 outcome text now names the `<title>.html`/`<title>.docx` convention explicitly, parallel to UC1's `report.pdf`.
- Closes followup `c2s9`.

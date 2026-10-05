# Prune WeasyPrint Unsupported CSS

## Purpose and scope

Prune or neutralize the rules in the bundled `src/cli/lib/github.css` that WeasyPrint reports as `WARNING: Ignored …`, so a normal PDF run writes no WeasyPrint warnings to stderr. stderr then becomes usable as an error channel. This is a standard implementation task; no dedicated skill applies.

Covers S12.

**Parallel-eligible.** This task touches only `src/cli/lib/github.css` and one gated assertion in `src/cli/test/bats/real-toolchain-e2e.bats`. It has no dependency on the other Phase 2 tasks and can run concurrently with the `md2x.sh` chain and the Node tasks. To keep it parallel-safe, it must not edit `src/cli/md2x.sh` or `src/cli/lib/generate-page.sh`.

Out of scope: any visual redesign, custom CSS options (a filed followup), and HTML output changes beyond what the pruned rules imply.

## Requirements

1. **Capture the baseline.**
   - On this host, with the real toolchain (pandoc 3.10.1 and the `~/.md2x/venv` WeasyPrint), run a representative PDF conversion. Use `src/cli/test/tiny-doc.md` plus a document exercising tables, code blocks, task lists, blockquotes, and headings; `README.md` works.
   - Capture every `WARNING: Ignored …` line, and record the list in your report.
2. **Prune or neutralize.** For each reported rule or declaration:
   - Remove it when WeasyPrint ignores it and it has no effect on the HTML output that matters. Typical cases are vendor-prefixed properties and properties WeasyPrint does not implement.
   - When a declaration matters for HTML but WeasyPrint ignores it, keep its HTML effect in a form WeasyPrint does not warn about if one exists. Otherwise prefer removal, unless the HTML visual change would be clearly noticeable. List each such judgment call in your report.
   - PDF visual output must stay the same. Compare before and after renders of the same document, for example by rasterizing pages with `gs -sDEVICE=png16m` and comparing them. Report any pixel differences and why they are acceptable.
3. **Residual warnings.**
   - The design allows a residual filter that drops only the exact `WARNING: Ignored` class if a rule cannot be pruned without visual change. That filter would live in `src/cli/lib/generate-page.sh`, which this task must not touch.
   - If such a rule remains, stop short of adding a filter and report the exact remaining warnings, so the manager can schedule the filter after `005-clean-up-version-inference-and-dependency-hygiene`.
   - Real WeasyPrint errors must always reach stderr.
4. **Regression test.**
   - Add a case to `src/cli/test/bats/real-toolchain-e2e.bats`, gated like its neighbors, that converts a representative document to PDF and asserts stderr contains no `WARNING: Ignored`.
   - Other Phase 2 tasks may also add cases to this file. Keep your addition self-contained, at the end of the file, to ease merging.

## Validation

- `make qa` passes. Because the CSS is inlined into `bin/md2x`, rebuild first.
- The new gated e2e case fails on the pre-task `github.css` and passes after it, and it does not skip on this host. Your report states that this was checked.
- `bin/md2x -p /tmp/o README.md 2>&1 >/dev/null | grep -c 'WARNING: Ignored'` prints `0`.
- `make smoke-test` (interactive, macOS) or a page-rasterization comparison shows no meaningful PDF visual change.
- An HTML conversion of the same document, viewed in a browser, looks unchanged or acceptably close. Report any differences.
- `git diff --stat` shows changes only in `src/cli/lib/github.css` and `src/cli/test/bats/real-toolchain-e2e.bats`.

## Assumptions

- Phase 1 is complete. HTML output inlines the CSS as a `<style>` block, so pruning affects HTML too, and PDF may still pass the CSS as a work-directory file.
- The WeasyPrint version is whatever `ensure-weasyprint` pins in `~/.md2x/venv`. Warnings are measured against that version.

## References

- [Design decisions: WeasyPrint warning flood](../notes/design-decisions.md#weasyprint-warning-flood).
- [Audit coverage](../notes/audit-coverage.md): row S12.
- `src/cli/lib/github.css`: 992 lines, every rule scoped under `.markdown-body`.
- `src/cli/lib/ensure-weasyprint.sh`: the pinned WeasyPrint version.
- `src/cli/test/bats/real-toolchain-e2e.bats`: the gating pattern.
- `src/cli/test/manual/visual-smoke-test.sh`: the visual check.

## Status

Outcome: partial (2026-10-05). The rules in `src/cli/lib/github.css` are pruned (WeasyPrint 69.0, pandoc 3.10.1), but one `WARNING: Ignored` line remains and is not in `github.css`: `` Ignored `user-select: none` at 49:32, unknown property. `` comes from pandoc's own default-template `<style>` (the `pre.numberSource` line-number rule), so it needs a `generate-page.sh` change (stderr filter) that this task may not make. The manager should schedule that filter after 005. The new e2e case in `src/cli/test/bats/real-toolchain-e2e.bats` exempts that exact line; drop the exemption once the filter lands.

Validation: `make qa` passes; `MD2X_TEST_BASH=/bin/bash make test-cli` passes (the new case runs, does not skip, and fails against the pre-task css). `bin/md2x -p o README.md 2>&1 >/dev/null | grep -c 'WARNING: Ignored'` prints 1 (the pandoc residual) rather than 0. Rasterized PDF pages (gs, 60 and 80 dpi) of README, tiny-doc and a table/kbd/task-list/blockquote/code document are byte-identical before and after.

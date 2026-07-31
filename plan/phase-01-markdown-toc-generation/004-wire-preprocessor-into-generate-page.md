# Wire Preprocessor Into Generate Page

## Purpose and scope

Put the TOC preprocessor into the conversion pipeline and retire Pandoc's native `--toc`. After
this task, PDF, HTML, and DOCX all receive the same md2x-generated Markdown TOC as ordinary
document content, and `--toc`/`--no-toc` control md2x's generator rather than a Pandoc flag.

Scope: `src/cli/lib/generate-page.sh`, a small addition to `src/cli/md2x.sh`, and the
integration bats coverage.

**Depends on tasks 001, 002, and 003.** 001 fixes the `--single-page` filename this task's move
away from process substitution would otherwise expose as a hard failure; 002 provides
`src/cli/lib/toc-preprocess.py`; 003 provides `TOC_MODE`.

## Requirements

1. **Inline the preprocessor into the rolled-up CLI.** `src/cli/lib/toc-preprocess.py` is a
   source file, and the shipped CLI is a single rolled-up bash script, so the Python source must
   travel inside it exactly as `github.css` does today. In `src/cli/md2x.sh`, next to the
   existing `CSS=$(cat <<'EOF' … EOF)` block, add:

   ```bash
   TOC_PREPROCESSOR=$(cat <<'EOF'
   source ./lib/toc-preprocess.py # bash-rollup-no-recur
   EOF
   )
   ```

   The `bash-rollup` inline directive resolves relative to the entry file's directory
   (`src/cli`), which is why the path is `./lib/…` — the existing comment above the `CSS` block
   explains this and is worth reading. The quoted heredoc means nothing in the Python source is
   expanded.

2. **Run it as `python3 -c`, not from a temp file.** Invoke the preprocessor as

   ```bash
   python3 -c "${TOC_PREPROCESSOR}" --mode "${TOC_MODE}"
   ```

   passing the script body as the `-c` argument so the document can occupy stdin, and so there
   is no fourth temp file to create, announce, and clean up. `python3 -c code arg…` places
   `arg…` at `sys.argv[1:]`, which is what the script's `--mode` parsing expects; if task 002's
   script derives a program name from `sys.argv[0]`, it must set an explicit `prog` instead,
   since `sys.argv[0]` is the literal `-c` here.

3. **Materialize the preprocessed Markdown to a real file.** Replace the two
   `<(… | eval $LINK_CONVERTER)` process substitutions with a single pipeline writing to a temp
   file, and hand Pandoc that file's path:

   ```bash
   PREPROCESSED_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-preprocessed.XXXXXX")"
   if [[ -z "${INPUT}" ]]; then cat "${MD_FILE}"; else printf '%s\n' "${INPUT}"; fi \
     | python3 -c "${TOC_PREPROCESSOR}" --mode "${TOC_MODE}" \
     | eval $LINK_CONVERTER \
     > "${PREPROCESSED_TMP_FILE}"
   ```

   This is the point of the change, not incidental cleanup: a process substitution's exit status
   is invisible to the script's `errexit`/`pipefail`, so a failing preprocessor would today
   hand Pandoc a truncated document and md2x would report success. As a plain pipeline under
   `pipefail`, any stage's failure aborts the conversion. Preserve the existing `INPUT`
   semantics: the stdin path currently accumulates lines with a trailing newline each, so
   `printf '%s\n'` reproduces `echo "${INPUT}"`'s behavior — verify against the existing
   `single-page-and-stdin.bats` stdin cases rather than assuming.

   The preprocessor runs **ahead of** `LINK_CONVERTER`, as specified. The two do not interfere:
   `LINK_CONVERTER` only rewrites links whose target ends in `.md)`, and generated TOC entries
   end in `)` directly after a `#anchor`.

4. **Collapse the duplicated Pandoc invocation.** With the input argument no longer differing
   between the two branches, the `if [[ -z "${INPUT}" ]]` / `else` pair of near-identical
   `pandoc …` calls becomes one invocation taking `"${PREPROCESSED_TMP_FILE}"`. Collapse them.
   Keep the trailing `1>/dev/null` and the comment above it explaining why stdout is redirected
   and stderr is not.

5. **Remove Pandoc's `--toc` entirely.** Delete the
   `$( [[ "${OUTPUT_FORMAT}" == 'docx' ]] || [[ -n "${NO_TOC}" ]] || echo '--toc' )` argument.
   Nothing in `generate-page.sh` may reference `NO_TOC` afterwards — `TOC_MODE` is the only TOC
   input to the pipeline. This is also what finally gives DOCX a TOC: the `docx` short-circuit
   in that condition was the sole reason DOCX never received one.

   Leave the separate `docx` short-circuit on `INCLUDE_BODY_ARGS` alone — that one is about the
   `markdown-body` wrapper div, not the TOC.

6. **Clean up the new temp file.** Remove `PREPROCESSED_TMP_FILE` at the end of
   `generate-page()` unless `--keep-intermediate` is given, alongside the existing
   `BODY_OPEN_TMP_FILE`/`BODY_CLOSE_TMP_FILE` removals, and add it to the script-level `EXIT`
   trap in `src/cli/md2x.sh` (with the same `${…:-}` default guard, for `nounset` safety when
   the trap fires before any `generate-page()` call). No stderr announcement is required when it
   is retained — that follows the body-open/body-close precedent; the announced-path treatment
   is reserved for the CSS file.

7. **Update the affected existing tests.** In `src/cli/test/bats/pandoc-args.bats`, the six
   `--no-toc`/`--toc` cases assert on Pandoc's `--toc` argument, which no longer exists. Replace
   them with cases asserting that **no** invocation ever passes `--toc` to `pandoc`, in any
   format, with or without the flags — and move the behavioral TOC coverage to the new file
   below. Update that file's header comment, which currently describes `--no-toc` as
   "table-of-contents suppression, format-dependent".

8. **Add integration coverage** in a new `src/cli/test/bats/toc-generation.bats`, driving the
   built CLI against the stubs and asserting on `md2x_pandoc_capture input` — the buffer Pandoc
   actually received. Add a local fixture helper that writes a document large enough and with
   enough sections to clear the default heuristic (see the calibration note; four or more
   top-level sections and more than ~90 estimated rendered lines).

   Required cases:
   - A TOC-worthy document gets a bullet list of `](#…)` links in the buffer, for
     `--output-format pdf`, `html`, **and `docx`** — the docx case is the headline behavior
     change and must assert the list is present.
   - `--no-toc` on the same document: no `](#` links added.
   - `--toc` on a deliberately tiny document: list present.
   - Neither flag on a tiny document: list absent.
   - `<!-- md2x:toc -->` in the source: the list appears at the marker's position (assert it
     follows a sentinel paragraph placed just above the marker) and the literal comment is gone
     from the buffer.
   - No marker: the list appears *after* the document's `# Title` line, not before it — the
     specific defect this feature exists to fix.
   - `--single-page` over two files that each contain a `## Overview` heading: the buffer's TOC
     contains both `#overview` and `#overview-1`, proving the dedup counter ran over the whole
     concatenated stream rather than per file.
   - The stdin (`-`) path gets the same treatment.
   - A `<!-- md2x:toc -->` inside a fenced code block is left verbatim and is not used as an
     insertion point.
   - `--keep-intermediate` retains the preprocessed temp file and it contains the TOC; without
     it, the file is gone after conversion. Locate it the way the existing CSS-temp-file cases
     do, by grepping the captured `pandoc` argument vector.

## Validation

- `make test` passes; `make test-cli` shows the new `toc-generation.bats` cases and every other
  bats file green.
- `grep -rn 'NO_TOC' src/cli/lib/` returns nothing.
- `grep -n -- "--toc" src/cli/lib/generate-page.sh` returns nothing (Pandoc's flag is gone).
- `grep -c 'pandoc \\' src/cli/lib/generate-page.sh` shows a single Pandoc invocation.
- `grep -n 'toc-preprocess.py' src/cli/md2x.sh` shows the rollup directive, and
  `grep -c 'def slugify' bin/md2x` (after `make all`) confirms the Python source was actually
  inlined into the built CLI.
- Manual end-to-end against the real toolchain, from a scratch directory: convert a
  four-section document to `html`, `pdf`, and `docx`; each output contains the TOC entries, and
  the DOCX contains `w:hyperlink` anchors (`unzip -p out.docx word/document.xml | grep -c
  'w:anchor'` is non-zero).
- No orphan `md2x-preprocessed.*` files remain in `${TMPDIR}` after a `make test-cli` run.

## Metadata

architectural_impact: true

## Assumptions

- Tasks 001, 002, and 003 have landed. In particular `TOC_MODE` exists and is always set to one
  of `on`/`off`/`auto` by the time `generate-page()` runs, so `nounset` is satisfied.
- `bash-rollup` inlines a non-`.sh` file's contents verbatim via the
  `source <path> # bash-rollup-no-recur` directive — established by the existing
  `lib/github.css` inline in `src/cli/md2x.sh`.

## Checkpoint hints

- After the rollup directive and `python3 -c` invocation are in place and `make all` shows the
  Python source inlined into `bin/md2x`.
- After the pipeline is materialized to a temp file and the two Pandoc invocations are collapsed
  into one, with the existing suite still green.
- After Pandoc's `--toc` and the `NO_TOC` reference are removed and `pandoc-args.bats` is
  updated.
- After `toc-generation.bats` is added.

## References

- [Pipeline verification and an adjacent defect](../notes/pipeline-verification.md) — why the
  preprocessor belongs inside `generate-page()`, why the process substitution has to go, and
  what the stub harness can and cannot see.
- [TOC defaults, directive syntax, and the page-count heuristic](../notes/toc-defaults-and-page-heuristic.md) —
  the placement rules the integration cases assert.
- `src/cli/lib/generate-page.sh` lines ~46–93 — the invocation to restructure and the temp-file
  cleanup idiom to extend.
- `src/cli/md2x.sh` lines ~197–235 — the `CSS` rollup-inline block to copy and the `EXIT` trap
  to extend.
- `src/cli/test/stubs/pandoc` and `src/cli/test/helpers/stub-log.bash` — how the input buffer is
  captured and asserted on.

## Status

- **Outcome:** succeeded
- **Date:** 2026-07-30
- **Validation summary:** `make test` passes in full (`test-cli` 127/127, `test-node` 23/23,
  100% Node coverage unchanged). `test-cli`'s 127 include all 13 new `toc-generation.bats`
  cases and every pre-existing case (updated where the task required, unchanged otherwise).
  `grep -rn 'NO_TOC' src/cli/lib/` is empty. `grep -n -- "--toc" src/cli/lib/generate-page.sh`
  is empty. `grep -c 'pandoc \\' src/cli/lib/generate-page.sh` is `1`. `grep -n
  'toc-preprocess.py' src/cli/md2x.sh` shows the rollup directive, and `grep -c 'def slugify'
  bin/md2x` (after `make all`) is `1`, confirming the inline. Manual end-to-end against the
  real toolchain (Pandoc 3.10.1, WeasyPrint, pdftk) from a scratch directory: a forced-`--toc`,
  four-section document converted to `html`, `pdf`, and `docx` all carry the TOC — 4
  `href="#section...\"` anchors in the HTML, a 1-page PDF (small fixture; the point was
  pipeline correctness, not clearing the page-count heuristic, which is already covered by the
  bats heuristic cases), and `unzip -p doc.docx word/document.xml | grep -c 'w:anchor'` = `4`
  in the DOCX. `ls "${TMPDIR}" | grep md2x-preprocessed` is empty both after `make test-cli` and
  after the manual e2e run.
- **Affected source files:**
  - `src/cli/md2x.sh` (the `TOC_PREPROCESSOR` rollup-inline block next to `$CSS`, and the
    script-level `EXIT` trap extended to remove `PREPROCESSED_TMP_FILE`)
  - `src/cli/lib/generate-page.sh` (the two near-duplicate Pandoc invocations collapsed into
    one taking a materialized, TOC-preprocessed temp file; Pandoc's native `--toc` removed
    entirely; `PREPROCESSED_TMP_FILE` cleanup added alongside the body-open/body-close cleanup)
  - `src/cli/test/bats/harness-smoke.bats` (removed the two now-inapplicable `--toc`-argument
    assertions and the stale "docx never gets an automatic table of contents" comment from
    harness-sanity cases not about TOC behavior)
  - `src/cli/test/bats/pandoc-args.bats` (header comment updated; the six `--no-toc`/`--toc`
    Pandoc-argument cases replaced with nine cases asserting Pandoc's `--toc` is never passed,
    across pdf/html/docx and with/without `--no-toc`/`--toc`; `teardown()` extended to delete
    any leaked `md2x-preprocessed.*` temp file so this file's four `--keep-intermediate` cases
    leave no orphan)
  - `src/cli/test/bats/real-toolchain-e2e.bats` (`e2e_teardown()` extended the same way, since
    its real-toolchain PDF case also passes `--keep-intermediate` and this machine has a real
    toolchain installed, so the case genuinely runs rather than skipping)
  - `src/cli/test/bats/toc-generation.bats` (new; 13 integration cases against the built CLI
    and stubs, per Requirement 8)
  - `plan/phase-01-markdown-toc-generation/004-wire-preprocessor-into-generate-page.md` (this
    file, Status only)
- **Decisions:**
  - The two `--keep-intermediate`-carrying test files that predate this task
    (`pandoc-args.bats`, `real-toolchain-e2e.bats`) now also produce a retained
    `PREPROCESSED_TMP_FILE` as a direct, mechanical consequence of Requirement 6 (cleanup gated
    on `--keep-intermediate`, matching the existing CSS/body-open/body-close precedent). Since
    the task's own validation explicitly requires no orphan `md2x-preprocessed.*` files after
    `make test-cli`, and both files were already part of this task's diff (or, for
    `real-toolchain-e2e.bats`, directly caused by this task's required behavior on a machine
    with a real toolchain installed), the fix was applied in place rather than flagged.
  - The integration bats fixture helper builds a TOC-worthy document as 18 structural lines (a
    title plus 4 `##` sections with body text) plus 90 blank padding lines (108 total),
    comfortably past both the >90-estimated-line and >=4-section floors, mirroring
    `toc-preprocess.bats`'s own padded-document convention.
  - The stdin-parity case redirects from a real file (`< 'report.md'`) rather than a
    here-string/`$(...)`, since command substitution strips the fixture's trailing blank
    padding lines and would silently shrink the document back under the heuristic's line-count
    floor.
  - The `--toc`-on-a-small-document case uses a title-plus-one-section fixture, not a
    title-only one, per the task doc's calibration note: the document-title heading is always
    excluded from the emitted TOC, so a title-only document can never show a TOC list
    regardless of `--toc`.
  - `toc-preprocess.py`'s `parse_args` does not derive a program name from `sys.argv[0]`
    (confirmed unchanged), so no `prog` adjustment was needed for the `python3 -c` invocation
    style.

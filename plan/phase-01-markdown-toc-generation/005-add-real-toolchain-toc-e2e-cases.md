# Add Real Toolchain TOC E2E Cases

## Purpose and scope

Add the fidelity backstop the stub-based suite structurally cannot provide: proof against real
Pandoc, WeasyPrint, and `pdftk` that md2x's generated slugs match the identifiers Pandoc
actually mints, and that the resulting TOC is genuinely navigable in DOCX and PDF output.

Scope: `src/cli/test/bats/real-toolchain-e2e.bats` and any fixture it needs. No production code
changes. Depends on task 004.

## Requirements

1. **Work within the existing e2e file's contract.** `src/cli/test/bats/real-toolchain-e2e.bats`
   already establishes the pattern: it deliberately does *not* call `md2x_setup` (which would
   put the stubs on `PATH`), uses its own `e2e_setup`/`e2e_teardown`, and gates cases with
   `e2e_require_pandoc` (binary presence, sufficient for HTML/DOCX) or `e2e_require_pdf_engine`
   (a real throwaway conversion probe, required for PDF). A gate that is not satisfied `skip`s
   with a message naming what was missing; it never fails the suite. Reuse those gates rather
   than inventing new ones.

2. **Slug agreement with real Pandoc.** The most valuable case, and the one that would catch a
   silent regression in the algorithm. Gate on `e2e_require_pandoc`.
   - Add a checked-in fixture, `src/cli/test/toc-slug-corpus.md`, containing the 29 headings
     from the table in `plan/notes/pandoc-gfm-slug-algorithm.md` as `##` headings, plus a
     leading `# Slug Corpus` title.
   - Extract the identifiers real Pandoc mints:
     `pandoc --from gfm --to html5 <fixture> | grep -o 'id="[^"]*"'`.
   - Convert the same fixture with `md2x --toc --output-format html`, and extract the anchors
     the generated TOC used from the resulting HTML.
   - Assert every TOC anchor appears in Pandoc's identifier set. Do not assert set equality —
     the fixture deliberately contains headings the TOC omits by design (the document title and
     the empty-slug heading), and the note records emoji as an accepted divergence, so keep the
     emoji heading out of the fixture or out of the compared set and say why in a comment.

3. **DOCX navigation is real.** Gate on `e2e_require_pandoc`.
   - Convert a multi-section fixture with `--toc --output-format docx`.
   - Read `word/document.xml` out of the `.docx` with Python's `zipfile` rather than shelling
     out to `unzip` (`python3` is a preflight-required binary; `unzip` is not):
     `python3 -c "import zipfile,sys; sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read('word/document.xml').decode())" out.docx`.
   - Assert the XML contains at least one `w:bookmarkStart` and that every `w:anchor="…"` value
     in it also occurs as a `w:bookmarkStart w:name="…"` — i.e. no TOC link points at a
     nonexistent bookmark.
   - Include one heading whose identifier Word cannot use as a bookmark name — a heading
     starting with a digit, such as `## 1. First Section` — since Pandoc mangles those into an
     `X<hash>` bookmark name on *both* the heading and the link, and this case is precisely what
     proves the mangling stays consistent. This is the headline "DOCX now gets a working TOC"
     claim.

4. **PDF links survive the overlay stage.** Gate on `e2e_require_pdf_engine`.
   - Convert a multi-section fixture with `--toc` (default PDF format).
   - Uncompress the finished PDF (`pdftk <out> output <tmp> uncompress`) and assert it contains
     at least one `/Link` annotation and at least one named destination. The finished PDF is the
     one that has already been through `gs` + `pdftk multistamp`, so this asserts end-to-end
     that the overlay stage does not strip the TOC's navigation.
   - A header comment should record why this case exists: `pdftk multistamp` was verified during
     planning to preserve annotations, and this case is what keeps that true.

5. **HTML anchors resolve.** Gate on `e2e_require_pandoc`. Convert a multi-section fixture with
   `--toc --output-format html` and assert every `href="#…"` the TOC emitted has a matching
   `id="…"` in the same file.

6. **Reuse a single fixture where practical.** A four-or-more-section document is needed by
   three of these cases; either add one checked-in fixture alongside `tiny-doc.md` or write it
   from a shared local helper in the e2e file. Follow whichever is more consistent with the
   file's existing use of `md2x_copy_fixture 'tiny-doc.md'` and `md2x_write_doc`.

7. **Keep every new case skippable.** A developer machine without Pandoc must still see
   `make test` pass, with these cases reported as skipped.

## Validation

- `make test-cli` passes on a machine with the full real toolchain, with the new cases *running*
  (not skipped) — verify by checking the bats output for their names without a `# skip` marker.
- `make test-cli` still passes with the new cases skipped: simulate by running bats with a `PATH`
  from which `pandoc` is absent, and confirm the suite exits `0` and reports skips.
- The new fixture(s) exist under `src/cli/test/` and are referenced by path from the cases.
- `git status` shows no stray `.docx`/`.pdf`/uncompressed artifacts left in the repository after
  a run — the e2e teardown removes its temp directory.

## References

- [Pipeline verification and an adjacent defect](../notes/pipeline-verification.md) — the
  measured `/Link`/`/Dest`/`/Annots` counts before and after `pdftk multistamp`, and the DOCX
  bookmark-mangling observation these cases lock in.
- [Pandoc GFM auto-identifier algorithm](../notes/pandoc-gfm-slug-algorithm.md) — the 29-heading
  corpus for the fixture, and the accepted-divergence list explaining what must be excluded from
  a strict comparison.
- `src/cli/test/bats/real-toolchain-e2e.bats` — the gating helpers, local setup/teardown, and
  content-assertion helpers to extend.
- `AGENTS.md` — the suite's stub-versus-real-toolchain division of labor.

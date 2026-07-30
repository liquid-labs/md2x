# Pipeline Verification and an Adjacent Defect

## Purpose and scope

What was verified end-to-end against the real toolchain before this plan was written, and one
pre-existing defect the injection work is forced to confront. Verified 2026-07-30 with Pandoc
3.10.1, `pdftk`, Ghostscript, and WeasyPrint from `~/.md2x/venv`.

## A Markdown-content TOC works in all three formats

A hand-written `[Heading](#slug)` bullet list, converted from `--from gfm`, produces real,
working navigation in every output format md2x supports:

- **HTML** — plain `<a href="#slug">`, trivially correct.
- **DOCX** — Pandoc's `docx` writer emits `w:bookmarkStart` for each heading and
  `w:hyperlink w:anchor="…"` for each link. Crucially, identifiers that Word forbids as
  bookmark names (a leading digit, for example) are **mangled consistently on both ends**: the
  heading `## 1. Numbered` and the link `[…](#1-numbered)` both become
  `X44e4729a77dc4314add13e7d427c616619942aa`. The generator therefore only needs the
  `gfm_auto_identifiers` slug; Pandoc handles the docx-specific renaming itself. This is what
  makes the "DOCX finally gets a working TOC" claim true, and it is exercisable only against
  real Pandoc, not the stub.
- **PDF** — WeasyPrint turns the anchors into `/Link` annotations plus named destinations. A
  four-entry TOC produced four `/Link` annotations.

## `pdftk multistamp` preserves the links

The obvious risk with the PDF path is md2x's second stage: `generate-page.sh` renders a
Ghostscript PostScript overlay and merges it with `pdftk … multistamp`, which could plausibly
drop annotations. It does not. A three-entry TOC document, before and after the overlay merge:

| | `/Link` | `/Dest` | `/Annots` |
| --- | --- | --- | --- |
| Pandoc/WeasyPrint output | 3 | 8 | 1 |
| After `pdftk multistamp` | 3 | 8 | 1 |

The PDF TOC stays clickable through the overlay stage. No change to the Ghostscript/pdftk stage
is needed.

## Pre-existing defect: `--single-page` without `--title` converts an empty document

`src/cli/md2x.sh` builds the concatenation target as `COMBINED_FILE="${TITLE:-input}.md"`
(line 193, before `TITLE` has been defaulted), then, at the single-page/stdin call site, sets
`MD_FILE="${TITLE:-input}.md"` (line 280) — *after* line 277 has already defaulted `TITLE` to
`output`. With no `--title`, the two names diverge: content is concatenated into `input.md`,
and `generate-page()` is told to read `output.md`.

Reproduced against the real toolchain:

```
$ md2x --single-page --output-format html --output-path . a.md b.md
cat: output.md: No such file or directory
Created ./output.html
$ echo $?
0
```

The `cat` failure is invisible to `errexit` because it happens inside a process substitution
(`<(cat "${MD_FILE}" | …)`), so md2x exits `0` having produced an empty document, and leaves
the orphan `input.md` behind in the working directory. The existing bats case
`single-page-and-stdin.bats::"--single-page defaults the output name to 'output' when --title
is absent"` passes, because it asserts only that `./output.pdf` exists — never that it has
content.

**Why this blocks the TOC work.** The injection design materializes the preprocessed Markdown
into a real temp file before invoking Pandoc, rather than piping it through a process
substitution, so that a preprocessor failure is visible to `errexit` instead of silently
yielding a truncated document. That change also makes *this* `cat` failure visible — which
would turn the currently-passing bats case into a hard failure. The naming bug therefore has to
be fixed as part of this work; it is a prerequisite, not scope creep. The fix is one line
(`MD_FILE="${COMBINED_FILE}"`), plus tightening the bats case to assert on content.

Two smaller warts observed alongside it, **not** in scope, worth recording as follow-ups:

- The concatenation file (`input.md` / `<title>.md`) is written into the user's current working
  directory and never removed, even without `--keep-intermediate`.
- `generate-page()` reassigns the caller's `COMBINED_FILE` variable for its own PDF-overlay
  merge target (`generate-page.sh` line 152). Harmless today because the caller has finished
  with it, but it is a live shadowing hazard for anything that later reads `COMBINED_FILE`
  after `generate-page` returns.

## Where the preprocessor has to sit

`--single-page` concatenates in `md2x.sh` *before* `generate-page()` is called, and
`generate-page()` receives the combined file as `MD_FILE`. Running the preprocessor inside
`generate-page()` therefore covers per-file, stdin, and `--single-page` input uniformly, and
sees the full concatenated stream — which is what makes cross-file heading deduplication
correct. No change to the concatenation step itself is required.

The preprocessor must run **ahead of** the existing `LINK_CONVERTER` perl pass. The two do not
interfere: `LINK_CONVERTER` only rewrites links whose target ends in `.md)`, and generated TOC
entries end in `)` after a `#anchor`.

## Test-harness reach

The stub `pandoc` (`src/cli/test/stubs/pandoc`) captures the content of the input-document
argument as `pandoc-<n>-input`, and the capture works the same whether that argument is a
process substitution or a real file path. So the bulk of this feature — that the TOC list is
present/absent, correctly placed, correctly nested, correctly slugged — is assertable in the
default stub-based bats suite by inspecting `md2x_pandoc_capture input`.

What the stub suite **cannot** show, and which therefore belongs in `real-toolchain-e2e.bats`
(whose cases skip rather than fail when the toolchain is absent):

- that the generated slugs match the identifiers real Pandoc mints;
- that DOCX output carries real `w:bookmarkStart` / `w:hyperlink w:anchor` pairs;
- that PDF output carries `/Link` annotations that survive `pdftk multistamp`.

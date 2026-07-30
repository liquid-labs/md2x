# Update README

## Purpose and scope

Bring the consumer-facing documentation in line with the new TOC behavior. `README.md`'s current
description — "Suppress the table of contents Pandoc otherwise adds for `pdf`/`html` output
(`docx` output never receives an automatic TOC)" — is wrong on every clause after this change.

Scope: `README.md` only. `CHANGELOG.md` is explicitly out of scope for this task — its real
entries are generated from `.meta/changelog.yaml` by liq release tooling at release time, and the
maintainer has decided not to hand-edit it here; leave it to release tooling. `docs/md2x-spec.md`,
`docs/architecture.md`, and `docs/project-structure.md` are Phase 02's responsibility — do not
edit them here. The CLI's `--help` text is task 003's responsibility. Depends on task 004 (the
behavior must exist before it is documented as existing). May run concurrently with task 005.

## Requirements

1. **`README.md` — CLI reference table.**
   - Add a `--toc` row: forces a table of contents on, regardless of document size.
   - Rewrite the `--no-toc` row: suppresses the table of contents, overriding both the default
     heuristic and a `<!-- md2x:toc -->` marker in the source. Remove the "Pandoc otherwise
     adds" framing and the "`docx` output never receives an automatic TOC" parenthetical — both
     are now false.
   - State, in one of the two rows or a note beneath the table, that giving both flags is a
     fatal error.
   - Keep the table's existing row ordering convention and the surrounding formatting.

2. **`README.md` — Features list.** The `## Features` bullet list currently says nothing about
   the TOC. Add a bullet: md2x generates the table of contents itself, as Markdown content, so
   PDF, HTML, and DOCX all get the same one, placed where the author asks for it.

3. **`README.md` — a short subsection on the TOC.** Add one, in the style of the existing
   `### The PDF header/footer overlay` subsection under `## CLI reference`. It must cover, in
   consumer terms:
   - the `<!-- md2x:toc -->` marker: what it looks like, that it goes on its own line, that it
     is an ordinary HTML comment and so is invisible in other Markdown renderers, and that its
     position is where the TOC lands;
   - where the TOC lands with no marker — after the document's title heading, or at the top when
     the document has no title heading;
   - the default: with neither flag, md2x adds a TOC only to documents longer than about two
     rendered pages that have four or more top-level sections, and `--toc`/`--no-toc` override
     that in either direction;
   - that the TOC is real document content, so it works identically in PDF, HTML, and DOCX —
     including as clickable Word bookmarks in DOCX, which previously got no TOC at all;
   - the two known limitations from `plan/notes/pandoc-gfm-slug-algorithm.md`: a heading
     containing an emoji character gets a TOC entry whose link may not resolve, and headings
     nested inside blockquotes or list items are not included.

   Keep it to a compact few paragraphs. Do not restate the calibration constants or the slug
   algorithm — those are internal detail, and the spec/architecture docs are Phase 02's job.

4. **Do not change** `README.md`'s Node library section. The `toc` option's addition to the
   library surface is documented in `docs/md2x-spec.md`, which Phase 02 owns; `README.md`'s
   Node section does not enumerate options.

5. **Do not touch `CHANGELOG.md` or `.meta/changelog.yaml`.** Both are out of scope — see
   Purpose and scope above.

## Validation

- `grep -n 'Pandoc otherwise adds' README.md` returns nothing.
- `grep -n 'docx.*never receives' README.md` returns nothing.
- `grep -n -- '--toc' README.md` shows both the new `--toc` row and the `--no-toc` row.
- `grep -n 'md2x:toc' README.md` shows the marker documented.
- `git diff --stat` shows exactly one changed file: `README.md`. `CHANGELOG.md` and
  `.meta/changelog.yaml` are untouched.
- The README's links all still resolve (no new relative link is added that points at a
  nonexistent path).

## References

- [TOC defaults, directive syntax, and the page-count heuristic](../notes/toc-defaults-and-page-heuristic.md) —
  the behavior to describe, in the level of detail a consumer needs.
- [Pandoc GFM auto-identifier algorithm](../notes/pandoc-gfm-slug-algorithm.md) — the
  "Known, accepted divergences" and "Heading recognition" sections are the source for the
  limitations note.
- `README.md` lines ~62–92 — the Features list, CLI reference table, and the overlay subsection
  whose style the new subsection should match.

# TOC Defaults, Directive Syntax, and the Page-Count Heuristic

## Purpose and scope

The concrete, testable definitions behind the TOC feature's user-visible behavior: the
directive marker, where the TOC lands when no directive is present, how `--toc`/`--no-toc`/
neither resolve, and the calibrated estimator that stands in for "2 pages or less" on an
unrendered Markdown document. Calibration measurements were taken on 2026-07-30 against the
real toolchain (Pandoc 3.10.1, WeasyPrint via `~/.md2x/venv`, `github.css`). Every number here
is load-bearing: the implementation and its tests must use these exact values.

## Directive marker

**`<!-- md2x:toc -->`**

- An HTML comment, so it is inert in GitHub, VS Code, and every other Markdown renderer — a
  source document carrying the marker still reads correctly outside md2x.
- `md2x:` matches the prefix the CLI already uses for its own stderr messages
  (`src/cli/lib/ensure-weasyprint.sh`), so the namespace is consistent with existing project
  convention. No prior directive/marker convention exists anywhere in md2x — this establishes
  the first one.
- **Recognition rule:** a source line whose whitespace-trimmed content matches
  `^<!--[ \t]*md2x:toc[ \t]*-->$`, case-sensitive, outside any fenced or indented code block.
  Only whole-line markers are recognized; an occurrence inside a paragraph, a code fence, or an
  indented code block is left untouched (this is what lets md2x's own documentation show the
  marker in a fenced example).
- **Multiple markers:** the first recognized marker is expanded; every later one is removed
  from the stream, and md2x prints a one-line `md2x: ...` notice to stderr naming the count.
  Never emit the TOC twice.
- **When the TOC is off** (`--no-toc`, or the default heuristic says no), every recognized
  marker line is still *removed* from the stream, so the literal comment never reaches the
  converter.

## Where the TOC goes

1. **Marker present** → at the marker, replacing that line.
2. **No marker, TOC on** → immediately after the document-title heading, if the document has
   one (see [document title](#document-title)), separated from it by a blank line. This is the
   fix for the current behavior, where Pandoc's `--toc` places the nav block *above* the
   document's own first heading.
3. **No marker, TOC on, no document title** → at the very top of the document, before all
   content.

## Document title

Several rules below need to know whether the document's first heading is a title rather than a
section. The definition, applied to the list of headings the scanner found, in document order:

> The first heading is the **document title** when it is the only heading in the document at
> the shallowest heading level present.

So `# md2x` followed by six `## …` headings has a document title; a document that is six `# …`
headings (the usual `--single-page` shape) does not.

The document-title heading is excluded from the emitted TOC. It still consumes a dedup slot,
like every other heading.

## Top-level section count

1. Scan all headings; if there are none, the count is **0**.
2. If the document has a title (above), drop it and work with the remainder; if nothing
   remains, the count is **0**.
3. The **section level** is the shallowest heading level present in that remainder (or in the
   whole document, when there is no title).
4. The **top-level section count** is the number of headings at the section level.

Worked examples against this repository's own docs:

| Document | Headings | Section level | Count |
| --- | --- | --- | --- |
| `README.md` | one `#`, six `##` | 2 | 6 |
| `docs/md2x-spec.md` | one `#`, five `##` | 2 | 5 |
| `src/cli/test/tiny-doc.md` | one `#`, one `##` | 2 | 1 |
| `--single-page` of three chapter files, each starting `# Chapter N` | three `#` | 1 | 3 |
| A document with no headings | — | — | 0 |

## TOC content and shape

- **Included levels:** absolute heading levels **1 through 3**, matching Pandoc's default
  `--toc-depth` of 3 — the behavior being retired — minus the document-title heading. Levels
  4–6 are omitted.
- **Nesting:** a Markdown bullet list, indented **2 spaces per level below the shallowest
  included level**. Emit nothing but the list — no `## Table of Contents` heading. Pandoc's
  `--toc` emitted an untitled `<nav>`, so this preserves the retired behavior; an author who
  wants a visible label writes their own heading above the marker.
- **Entry text:** the heading's raw text with Markdown link syntax flattened (`[text](url)` →
  `text`) — a nested link inside a link is invalid Markdown — and any remaining `[` and `]`
  backslash-escaped. Other inline markup (emphasis, code spans) is preserved, as Pandoc's own
  TOC did.
- **Entry target:** `#<slug>`, with the slug computed per
  [the slug algorithm note](./pandoc-gfm-slug-algorithm.md).
- **Omitted entries:** headings whose slug is empty (not linkable — see the slug note).
- **Nothing to emit:** when no heading qualifies, emit no list at all, and still remove the
  marker.

Shape:

```markdown
- [Section One](#section-one)
  - [Sub A](#sub-a)
    - [Sub Sub](#sub-sub)
- [Section Two](#section-two)
```

The generated list must be separated from surrounding content by a blank line on each side, or
GFM will fold it into an adjacent paragraph.

## Resolving `--toc` / `--no-toc` / neither

| Invocation | Result |
| --- | --- |
| `--toc` and `--no-toc` both given | **Fatal error before any conversion work**, naming both flags. Exit non-zero via `echoerrandexit` (exit `1`), consistent with the unrecognized-`--output-format` path. |
| `--no-toc` | TOC off. Wins over everything, including a `<!-- md2x:toc -->` marker in the source. |
| `--toc` | TOC on, regardless of document size. |
| Neither, and the source contains a `<!-- md2x:toc -->` marker | TOC on. An explicit marker is explicit author intent, so it overrides the small-document default-off. |
| Neither, no marker | The default heuristic below. |

**Default heuristic.** A document is **small**, and gets no TOC, when *either*:

- its estimated page count is **2 or less**, **or**
- its top-level section count is **fewer than 4**.

Otherwise (estimated pages > 2 **and** top-level sections >= 4) it gets a TOC. The `or` is
deliberate and both branches stand alone — do not weaken it to an `and`.

The resolution applies uniformly to `pdf`, `html`, and `docx`. `docx` no longer has a special
case.

## Estimated page count

There is no page count before rendering, so md2x estimates one from the Markdown source. Since
md2x owns the stylesheet, page setup, margins, and font, the estimator can be calibrated
against what those actually produce.

**Definition.** Walk the source lines, *after* removing any recognized marker line and *before*
injecting the TOC (so neither the marker nor the generated list feeds back into the estimate):

- a blank line contributes **1**;
- a line inside a fenced code block contributes **1** (code does not wrap under `github.css`);
- any other line contributes `max(1, ceil(len(line.strip()) / 85))`.

Then `estimated_pages = ceil(total / 45)`.

Equivalently, and this is the form to assert on in tests: **a document is "2 pages or less"
exactly when its estimated rendered-line total is 90 or fewer.**

`85` characters per rendered line and `45` rendered lines per page are the calibrated
constants. They must be named constants in the implementation with a comment pointing here.

### Calibration data

Measured page counts, real toolchain, `github.css` + the `markdown-body` wrapper + WeasyPrint,
against the estimator above:

| Document | Words | Source lines | Actual pages | Estimated |
| --- | --- | --- | --- | --- |
| `src/cli/test/tiny-doc.md` | 62 | 21 | 1 | 1 |
| synthetic structured, 2 sections | 173 | 27 | 1 | 1 |
| synthetic structured, 4 sections | 343 | 53 | 2 | 2 |
| synthetic structured, 6 sections | 513 | 79 | 3 | 3 |
| synthetic structured, 8 sections | 683 | 105 | 4 | 4 |
| synthetic structured, 10 sections | 853 | 131 | 5 | 4 |
| synthetic structured, 12 sections | 1023 | 157 | 5 | 5 |
| synthetic dense prose, 200 words | 203 | 13 | 1 | 1 |
| synthetic dense prose, 400 words | 403 | 21 | 2 | 2 |
| synthetic dense prose, 600 words | 603 | 27 | 2 | 2 |
| synthetic dense prose, 800 words | 803 | 33 | 3 | 2 |
| synthetic dense prose, 1000 words | 1003 | 41 | 3 | 3 |
| synthetic dense prose, 1200 words | 1203 | 47 | 4 | 4 |
| `AGENTS.md` | 741 | 81 | 3 | 3 |
| `README.md` | 904 | 104 | 4 | 4 |
| `docs/project-structure.md` | 971 | 100 | 4 | 4 |
| `docs/md2x-spec.md` | 2205 | 140 | 8 | 7 |
| `docs/architecture.md` | 2599 | 111 | 8 | 7 |

Fifteen of eighteen exact; the three misses are all one page low on long documents, where the
answer to "more than 2 pages?" is unchanged. The single boundary-relevant miss is the 800-word
dense-prose case (3 actual, 2 estimated) — a document with one heading, which the
fewer-than-4-sections branch excludes from a default TOC regardless.

A raw word count was rejected: words-per-page ranges from 171 to 334 across this corpus
depending on how much structure the document carries, a 2× spread the rendered-line estimator
does not have.

## Interactions worth stating

- **`--single-page`.** The concatenated document typically has one `#` per input file, so the
  section level is 1 and the count is the number of files. Three or more files with more than
  two estimated pages therefore get a TOC by default.
- **`--infer-title`.** Independent. It sets Pandoc title metadata; the document-title rule here
  looks only at Markdown content.
- **stdin (`-`).** Identical treatment; the preprocessor sits on the same path.

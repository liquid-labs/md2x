# Markdown-Based TOC Generation

## Purpose and scope

Replace Pandoc's native `--toc` with a table of contents md2x generates itself, as literal
Markdown content, so PDF, HTML, and DOCX all receive an identical, consistently-placed,
navigable TOC. Along the way, give the TOC a placement the author controls, give `docx` a TOC
at all (it currently never gets one), and replace the current "always on unless `--no-toc`"
behavior with an explicit `--toc`/`--no-toc` pair plus a size-based default.

In scope: a new Markdown preprocessing stage in the CLI's conversion pipeline; a directive
marker; the slug algorithm; the default-on/default-off heuristic; CLI flag parsing and
validation; the Node wrapper's corresponding option; test coverage; and documentation.

Out of scope: any change to the Ghostscript/`pdftk` PDF overlay stage (verified unnecessary —
it preserves link annotations); any change to the `--single-page` concatenation step itself;
exposing further Pandoc options; a general-purpose directive/shortcode system beyond the single
TOC marker.

## Current status

Phase 01 (Markdown TOC Generation) begins first. Nothing is blocked: every design question the
request left open has been resolved and recorded in `plan/notes/`, and the algorithm, the
heuristic constants, and the three-format link behavior were verified against the real
toolchain (Pandoc 3.10.1, WeasyPrint, `pdftk`) during planning.

Pre-conditions: the repository builds and its suites pass (`make test`), `node_modules` is
installed, and `bin/md2x` is present.

One correction to the request's stated background carries into implementation: md2x converts
with `--from gfm`, so heading identifiers come from Pandoc's `gfm_auto_identifiers` extension,
**not** the classic `auto_identifiers` algorithm. Leading digits are *kept*, whitespace is
*not* collapsed, and text is *not* ASCII-folded — the opposite of the behavior described in the
request's background notes. See [the slug algorithm note](./notes/pandoc-gfm-slug-algorithm.md).

## Overview

### What must change

1. **A new preprocessing stage.** `src/cli/lib/toc-preprocess.py` reads Markdown on stdin and
   writes Markdown on stdout, expanding a `<!-- md2x:toc -->` marker (or inserting a TOC at a
   default position) into a nested bullet list of `[Heading](#slug)` links. It also owns the
   default-on/default-off heuristic, so the shell only has to hand it `on`, `off`, or `auto`.
2. **`generate-page()` runs it** ahead of the existing `LINK_CONVERTER` perl pass, materializing
   the result into a temp file rather than a process substitution so failures are visible to
   `errexit`. Pandoc's `--toc` flag is removed from the invocation entirely, including the
   `docx` short-circuit that currently denies DOCX a TOC.
3. **`--toc` is a new flag**; `--no-toc` keeps its name but now controls md2x's own TOC.
   Supplying both is a fatal error before any conversion work.
4. **`--single-page` combined-file naming is fixed** — a pre-existing defect that the move away
   from process substitution would otherwise convert from a silent empty document into a hard
   failure.
5. **Docs and tests** follow the behavior change.

### Design decisions (all resolved; see `plan/notes/`)

| Question | Decision |
| --- | --- |
| Marker syntax | `<!-- md2x:toc -->` on its own line, outside code blocks |
| Placement, no marker | after the document-title heading; top of document when there is none |
| Multiple markers | expand the first, drop the rest, notice on stderr |
| Marker present, no flags | forces the TOC on (overrides the small-document default) |
| `--no-toc` | wins over everything, including a marker |
| "2 pages or less" | estimated rendered lines <= 90, at 85 chars/line and 45 lines/page |
| "top-level sections" | headings at the shallowest level, excluding a sole leading title heading |
| TOC depth | absolute heading levels 1–3, matching Pandoc's retired `--toc-depth` default |
| Slug algorithm | Pandoc `gfm_auto_identifiers`, replicated exactly, dedup included |

Supporting notes:

- [Pandoc GFM auto-identifier algorithm](./notes/pandoc-gfm-slug-algorithm.md) — the verified
  slug specification and its 29-case corpus.
- [TOC defaults, directive syntax, and the page-count heuristic](./notes/toc-defaults-and-page-heuristic.md) —
  marker rules, placement, flag resolution, and the calibrated page estimator.
- [Pipeline verification and an adjacent defect](./notes/pipeline-verification.md) — what was
  proven end-to-end, and why the `--single-page` naming fix is a prerequisite.

### Phase 01 — Markdown TOC Generation

Six tasks. The first three are independent and may run concurrently; the last three are
sequential behind them.

1. **Fix `--single-page` Combined-File Naming** — one-line fix in `src/cli/md2x.sh` so the
   concatenation target and the file `generate-page()` reads are the same name when `--title`
   is absent, plus tightening the bats case that currently passes vacuously. Prerequisite for
   task 004.
2. **Add The TOC Preprocessor Script** — `src/cli/lib/toc-preprocess.py`: heading scanner, slug
   algorithm, page/section heuristic, marker handling, TOC emission. Ships with a bats file
   that drives the script directly, so the algorithm is covered at fine grain.
3. **Add The `--toc` Flag And Both-Flags Conflict Check** — option parsing, the fatal
   both-flags error, help text, and the resolved TOC mode variable. Independent of tasks 001
   and 002.
4. **Wire The Preprocessor Into `generate-page()`** — the injection itself, retiring Pandoc's
   `--toc`, temp-file lifecycle, and the integration bats coverage (default on/off, DOCX,
   `--single-page` cross-file dedup). Depends on 001, 002, and 003.
5. **Add Real-Toolchain TOC End-To-End Cases** — the fidelity backstop the stub suite cannot
   provide: slug agreement with real Pandoc, DOCX bookmarks/anchors, PDF `/Link` annotations
   surviving `pdftk multistamp`. Depends on 004.
6. **Update README, Help Text, And CHANGELOG** — the consumer-facing surface. Depends on 004.

The Node wrapper's `toc` option is part of task 003, alongside the CLI flag it maps to.

### Phase 02 — Documentation Updates

One task, updating `docs/architecture.md` and `docs/md2x-spec.md` for the new pipeline stage
and the changed spec-defined behavior.

### Parallelism and dependencies

- Concurrent: tasks 001, 002, 003. Tasks 001 and 003 both edit `src/cli/md2x.sh`, but in
  disjoint regions (the single-page call site versus the option block and help text).
- Sequential: 004 after 001+002+003; 005 and 006 after 004 (and may run concurrently with each
  other); Phase 02 after Phase 01.

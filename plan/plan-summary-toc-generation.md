# Plan Summary: Markdown-Based TOC Generation

## What was planned and why

The session originated from a user question about why the table of contents appeared *before*
the document title in md2x's PDF output. Investigating that surfaced a larger problem: md2x's
TOC came entirely from Pandoc's native `--toc` flag, which (a) always places the nav block above
the document's own first heading with no author control over placement, (b) is silently
suppressed for `docx` output by an existing short-circuit, so DOCX conversions never got a TOC
at all, and (c) was "always on unless `--no-toc`" with no size-based default.

The plan's goal was to replace Pandoc's native `--toc` with a table of contents md2x generates
itself, as literal Markdown content injected into the source before conversion, so PDF, HTML,
and DOCX all receive an identical, consistently-placed, navigable TOC. Along the way: give the
TOC a placement the author controls (a `<!-- md2x:toc -->` marker, or a sensible default), give
`docx` a TOC for the first time, and replace the old "always on unless `--no-toc`" behavior with
an explicit `--toc`/`--no-toc` flag pair plus a size-based default heuristic.

Explicitly out of scope: any change to the Ghostscript/`pdftk` PDF overlay stage (verified
unnecessary — it preserves link annotations), any change to the `--single-page` concatenation
step itself, exposing further Pandoc options, or a general-purpose directive/shortcode system
beyond the single TOC marker.

Before implementation began, every open design question was resolved and verified against the
real toolchain (Pandoc 3.10.1, WeasyPrint, `pdftk`) and recorded in `plan/notes/`, including a
correction to the request's own background: because md2x converts with `--from gfm`, heading
identifiers come from Pandoc's `gfm_auto_identifiers` extension, not the classic
`auto_identifiers` algorithm — leading digits are kept, whitespace is not collapsed, and text is
not ASCII-folded, the opposite of what the request's background notes assumed.

## What shipped

### Phase 1 — Markdown TOC Generation (6 tasks, all complete)

1. **Fix Single Page Combined File Naming** (merge `271e90c`) — Fixed a pre-existing
   `--single-page`-without-`--title` defect: `md2x.sh` concatenated inputs into `COMBINED_FILE`
   but told `generate-page()` to read a differently-derived `MD_FILE`, silently converting an
   empty document while still exiting 0. Fixed with `MD_FILE="${COMBINED_FILE}"`, guarded to the
   single-page branch, and tightened the bats case that had been passing vacuously.
   `make test-cli` passed all 72 cases. This was a prerequisite for task 4, since moving away
   from process substitution would otherwise turn this silent bug into a hard failure.

2. **Add TOC Preprocessor Script** (merge `100d577`) — Implemented
   `src/cli/lib/toc-preprocess.py`, a stdlib-only Python 3 Markdown-in/Markdown-out preprocessor
   that scans ATX/setext headings (respecting fence and multi-line-HTML-comment block state),
   reproduces Pandoc's `gfm_auto_identifiers` slug algorithm exactly (verified against all 29
   corpus rows), resolves the `<!-- md2x:toc -->` marker and on/off/auto mode contract, and emits
   a nested, deduplicated `[Heading](#slug)` bullet list at the correct placement per the
   calibrated page/section heuristic. Shipped with `toc-preprocess.bats` (33 cases: slug corpus,
   heading-recognition table, marker handling, placement, heuristic boundaries, mode overrides,
   CRLF pass-through, link-text flattening/escaping). Nothing called the script yet at this
   point — wiring was task 4's job.

3. **Add TOC Flag And Conflict Check** (merge `8855999`) — Added `--toc` as a long-only, boolean
   `setSimpleOptions` entry alongside `--no-toc` (confirmed `--toc` does not steal `-t`), added a
   fatal both-flags-given conflict check placed before the network-triggering
   `ensure-weasyprint` call, and resolved both flags into a `TOC_MODE` (auto/on/off) variable not
   yet consumed. Rewrote `--help` and added the mirrored Node wrapper option. `make test`
   (78 bats + 23 Jest) and `make lint` green. Flagged one pre-existing, out-of-scope bug: a
   `TITLE`-overwrite defect in `md2x.sh`'s per-file loop means `--title`/`-t` has no effect on
   non-single-page, non-stdin conversions (see Follow-up items).

4. **Wire Preprocessor Into Generate Page** (merge `70f3703`) — Wired `toc-preprocess.py` into
   the real conversion pipeline: inlined into the rolled-up CLI, invoked via `python3 -c` ahead
   of `LINK_CONVERTER`, output materializes to a real temp file that Pandoc reads as a plain path
   argument — collapsing the two INPUT-branch Pandoc calls into one and making preprocessor
   failure visible under `errexit`/`pipefail`. Pandoc's native `--toc` (and the `docx`
   short-circuit) is gone entirely, so DOCX gets a working TOC for the first time — confirmed
   against real Pandoc/WeasyPrint/`pdftk`, including real `w:anchor` bookmarks. Updated
   `pandoc-args.bats`/`harness-smoke.bats` for the retired flag, added 13 new integration cases in
   `toc-generation.bats`, and fixed two `--keep-intermediate` temp-file leaks. `make test` fully
   green; manual real-toolchain end-to-end confirmed the feature works outside the stub harness.

5. **Add Real Toolchain TOC E2E Cases** (merge `84cc5f4`) — Added the real-toolchain fidelity
   backstop the stub suite can't provide: a checked-in 29-heading slug corpus fixture plus four
   new `real-toolchain-e2e.bats` cases (slug agreement with real Pandoc, DOCX bookmark/anchor
   consistency including digit-heading mangling, PDF `/Link`+`/Dests` survival through the
   `gs`+`pdftk` multistamp overlay, HTML anchor resolution), gated on the existing
   `e2e_require_pandoc`/`e2e_require_pdf_engine` helpers. Verified end-to-end on real Pandoc
   3.10.1/WeasyPrint/`pdftk`: `make test-cli` passed with all 131 cases running, and again with
   `pandoc` stripped from `PATH` (clean skips). No production code touched.

6. **Update README And CHANGELOG** (merge `982b5a5`) — Updated README.md only, per an
   amendment narrowing scope to README-only (CHANGELOG.md untouched). Replaced the stale
   `--no-toc` description with an accurate `--toc`/`--no-toc` pair and both-flags-fatal-error
   note. Added a Features bullet and a new TOC subsection covering the marker, default
   placement, the size/section-count heuristic, cross-format consistency (including DOCX
   bookmarks), and the two known slug-algorithm limitations.

**Phase 1 boundary review.** Found two fix-first findings: a setext-heading scanner bug that
misidentified indented-code-block text as setext heading text (causing spurious TOC entries and
incorrect document-title detection), and an efficiency issue computing heuristic inputs
unconditionally even when the TOC mode made them unnecessary. Both were fixed in a follow-up
commit, `c221eef` — `fix(toc-preprocess): exclude indented code from setext text, skip unused
heuristic work` — merged at `c1666a0`.

### Phase 2 — Documentation Updates (1 task, complete)

1. **Update Architecture Docs** (merge `8753145`) — Updated `docs/architecture.md`,
   `docs/md2x-spec.md`, and `docs/project-structure.md` to reflect the Markdown-based TOC
   generation delivered in Phase 1, and corrected `AGENTS.md`'s code-organization list to include
   `toc-preprocess.py`. The architecture doc gained a new TOC preprocessor subsection, an updated
   Mermaid diagram and walkthrough, a corrected pipeline description, and two Key-decisions
   updates. The spec doc's UC2, features bullet, CLI flags table, exit behavior, and Node-library
   options were rewritten to state that DOCX now gets a TOC and to describe flag/marker/heuristic
   resolution behaviorally. `docs/project-structure.md` was updated to mention the new files.
   README.md/CHANGELOG.md needed no further changes.

**Phase 2 boundary review.** Found two minor findings: `docs/project-structure.md` was missing a
mention of the new `real-toolchain-e2e.bats` file, and a followup entry's title had been
truncated. Both were fixed directly on the plan branch afterward: the missing bats-file mention
was added in `9e17531` (`docs(project-structure): mention real-toolchain-e2e.bats in src/cli/test/
listing`), and the truncated followup title was corrected by removing the malformed entry
(`133abf2`, followup `lQoE`) and re-adding it with a proper title (`af5fd99`, followup `IcMM`).

## Key decisions

- **Marker syntax and placement.** `<!-- md2x:toc -->` on its own line, outside code blocks, is
  the directive. An HTML comment was chosen because it is inert in every Markdown renderer, and
  the `md2x:` prefix matches the CLI's existing stderr-message convention. With no marker, the
  TOC defaults to right after the document-title heading (fixing the exact defect that started
  the session — Pandoc's `--toc` placed the nav block *above* the title); with no title, it goes
  at the top of the document. Multiple markers: the first is expanded, later ones are dropped
  with a stderr notice.

- **Size heuristic for default-on/off.** A document is "small" (no default TOC) when *either*
  its estimated page count is 2 or less, *or* its top-level section count is fewer than 4 — an
  `or`, deliberately, not an `and`. The page estimate is a calibrated line-based formula (a blank
  line or fenced-code line counts as 1 rendered line; any other line counts as
  `max(1, ceil(len/85))`; `estimated_pages = ceil(total/45)`), calibrated against real
  Pandoc+WeasyPrint+`github.css` rendering (15 of 18 calibration cases exact, remaining misses one
  page low on long documents with no effect on the >2-page threshold). "Top-level sections" means
  headings at the shallowest level present, excluding a sole leading title heading.

- **`--toc`/`--no-toc` resolution.** `--toc` is a new flag; `--no-toc` keeps its name but now
  controls md2x's own TOC instead of Pandoc's. Supplying both flags together is a fatal error,
  raised before any conversion work. `--no-toc` wins over everything, including a marker in the
  source; an explicit marker with neither flag forces the TOC on, overriding the small-document
  default-off; with neither flag and no marker, the size heuristic decides. This resolution
  applies uniformly across `pdf`, `html`, and `docx` — no format-specific special case remains.

- **Retiring Pandoc's native `--toc` entirely.** Pandoc's `--toc` flag (and the `docx`
  short-circuit that denied DOCX a TOC) was removed from the Pandoc invocation altogether. DOCX
  now gets a working TOC — with real `w:anchor` bookmarks — for the first time in md2x's history.

- **Reimplementing Pandoc's `gfm_auto_identifiers` slug algorithm exactly**, rather than relying
  on Pandoc's own TOC/anchor mechanism, was necessary because md2x now generates the TOC as
  Markdown *before* Pandoc sees it, so md2x's own hand-written `[Heading](#slug)` links must
  resolve against the anchors Pandoc will mint later. The algorithm (flatten inline markup, split
  on whitespace, filter to Unicode alnum/`_`/`-`, lowercase, join with `-`, dedup via `-1`,
  `-2`, … suffixes) was derived by differential testing against Pandoc 3.10.1 with `--from gfm`
  (not from documentation) and verified against a 29-heading corpus. Choosing `gfm` semantics
  over the classic `auto_identifiers` algorithm was itself a correction to the request's
  background assumptions: leading digits are kept, whitespace is not collapsed, and text is not
  ASCII-folded.

- **Two documented, accepted divergences** from Pandoc's real identifier algorithm, both judged
  acceptable rather than worth chasing with a full CommonMark parser:
  - **Emoji headings** — Pandoc's `gfm` reader's `emoji` extension turns `🎉` into `tada`
    (`emoji-tada-party`); md2x's text-based approximation yields `emoji--party` instead, so such
    a heading's TOC entry link won't resolve (the entry still renders as text).
  - **Blockquote- and list-nested headings** (e.g. `> ## X` or `- ## X`) are real headings to
    Pandoc but are out of scope for md2x's line-based scanner, since recognizing them correctly
    would require block-structure parsing. Such a heading is missing from the TOC, and can
    silently consume a Pandoc dedup slot the scanner doesn't model, so a later same-titled
    top-level heading's generated TOC link could point at the nested one instead. Documented as
    a bounded, benign limitation rather than fixed.

## Follow-up items

Filtered from `plan/followups.yaml` to items tagged against this plan's phases
(`markdown-toc-generation` / `phase-01-markdown-toc-generation` and `doc-updates`); the file also
carries unrelated items from other plans sharing this repository, which are omitted here.

- **Pre-existing, out-of-scope `--title` bug [CwaE]** — `md2x.sh`'s per-file conversion loop
  unconditionally overwrites `TITLE` from each input file's basename, so `--title`/`-t` has no
  effect on a directly-named, non-single-page, non-stdin conversion's output filename or
  `--infer-title` metadata, contradicting the spec's API table. A naive fix would make every file
  in a multi-file/directory batch collide on one output name, so it needs its own design
  decision. Recommends a dedicated followup to define and fix `--title` precedence for
  per-file/batch conversion.

- **Task-doc wording tension on mode overrides [ntBH]** — The task doc's "Mode overrides" bullet
  ("`--mode on` emits a TOC for a one-heading, one-line document") is in tension with the
  unconditional document-title-exclusion rule, since a genuine one-heading document's sole
  heading is always the excluded title and so can never produce a non-empty TOC under any mode.
  Resolved by testing the real intent (mode overriding the size-based auto-suppress heuristic
  only) against the smallest document with a non-title heading, documented inline in the bats
  test and the task doc. Implemented behavior is spec-correct; flagged only in case the task doc
  wording should be tightened for future readers.

- **`allocate_slug()` collision probe is O(d²) in duplicate count [psgq]** — Surfaced by the
  phase-1 boundary review's efficiency lens (low confidence, not blocking). The dedup probe
  restarts from `n=1` on every call for a given base slug, so a document with many headings that
  flatten to the same slug text makes each successive duplicate probe scan linearly through all
  prior duplicates. This mirrors Pandoc's own documented collision-probing behavior, so it's
  likely intentional parity rather than a regression, and real documents rarely have enough
  same-text headings for it to matter. If it ever needs to scale, track a per-base "next probe
  index" dict so each call resumes where the previous duplicate left off.

- **TOC marker: no dedicated spec use case added [IcMM]** — Judgment call surfaced for
  visibility, not requiring action: the doc-updates task chose not to add a new use case or
  Constraints/assumptions entry in `docs/md2x-spec.md` for the marker, since the rewritten
  General-features bullet already documents it behaviorally. A reviewer could reasonably prefer
  an explicit constraints entry instead.

# Add TOC Preprocessor Script

## Purpose and scope

Create `src/cli/lib/toc-preprocess.py`, the new Markdown-in / Markdown-out preprocessing stage
that generates md2x's table of contents. It scans headings, replicates Pandoc's
`gfm_auto_identifiers` slug algorithm exactly, decides whether a TOC is warranted, and emits a
nested `[Heading](#slug)` bullet list at the marker (or at a default position).

This task delivers the script and its direct test coverage only. Nothing calls it yet — task
004 wires it into `generate-page()`. It is independent of tasks 001 and 003 and may run
concurrently with them.

**Read `plan/notes/pandoc-gfm-slug-algorithm.md` and
`plan/notes/toc-defaults-and-page-heuristic.md` before writing any code.** They are the
specification; this document is the packaging around them. Every constant, rule, and edge case
below is already resolved there — do not re-derive or re-decide any of it.

## Requirements

### Program contract

```
toc-preprocess.py --mode on|off|auto
```

- Reads the whole Markdown document from stdin; writes the transformed Markdown to stdout.
- `--mode` is required. `on` = always emit a TOC; `off` = never emit one (but still strip
  markers); `auto` = apply the default heuristic. The shell caller resolves `--toc`/`--no-toc`
  into this value, so the script never sees the flags themselves.
- Diagnostics go to stderr only, prefixed `md2x: ` to match the CLI's existing message style
  (`src/cli/lib/ensure-weasyprint.sh`). **stdout carries document bytes exclusively** — the CLI
  pipes it, and `--to-stdout`/`--list-files` make stdout a parsed channel.
- Exits `0` on success, non-zero with a `md2x: ` stderr message on any internal failure. Never
  fail silently and never emit a partial document: build the output fully, then write it.
- Python 3 standard library only. No third-party imports. Target the ambient system `python3`
  the CLI already preflight-checks; avoid syntax newer than Python 3.8.
- Reconfigure stdin/stdout to UTF-8 with `errors='surrogateescape'` so a document containing
  invalid UTF-8 passes through byte-preserved rather than crashing the conversion.
- Preserve each pass-through line's original line ending byte-for-byte (read with
  `splitlines(keepends=True)` or equivalent); emit `\n` for generated lines.
- An empty input produces empty output and exit `0`.

### Heading scanner

Recognize, per the recognition table in the slug-algorithm note:

- **ATX** — 0–3 leading spaces, 1–6 `#`, then a space or end of line. Strip an optional trailing
  run of `#` (and the whitespace before it) from the text. `#NoSpace` and `#######` are not
  headings.
- **Setext** — a non-blank paragraph line (0–3 leading spaces) immediately followed by a line of
  only `=` (level 1) or only `-` (level 2), 0–3 leading spaces. The text line must not itself be
  an ATX heading, a fence line, a blockquote (`>`), a list item (`-`/`*`/`+`/`N.`/`N)`), or
  blank.
- **Excluded:** anything inside a fenced code block; any line indented 4 or more spaces (which
  is indented code and can never be an ATX heading anyway); anything inside a multi-line HTML
  comment block.

Track exactly three block states, in this order per line: fenced-code state, then the marker
check, then multi-line HTML-comment state.

- **Fence state.** An opener is 0–3 leading spaces then 3 or more backticks or 3 or more tildes;
  record the character and the run length. A closer is 0–3 leading spaces, the same character, a
  run at least as long as the opener's, and nothing else but trailing whitespace. A backtick
  opener's info string may not contain a backtick.
- **HTML-comment state.** A line containing `<!--` with no matching `-->` after it opens the
  state; the state closes on the line containing `-->`. A single-line `<!-- … -->` never enters
  the state.

Record, for each heading: level, raw text, and the source line span (an ATX heading spans one
line; a setext heading spans two). The span is needed for default TOC placement.

**Out of scope, deliberately:** headings nested inside blockquotes or list items. Pandoc does
mint identifiers for them, so omitting them can skew the dedup numbering of a later same-titled
top-level heading. This is a recorded, documented limitation — do not build a block-structure
parser to close it.

### Slug algorithm

Implement exactly the four steps and the dedup rule in
`plan/notes/pandoc-gfm-slug-algorithm.md`. The note's 29-row corpus table is the expected-output
fixture for the tests below; reproduce it verbatim.

Points that are easy to get wrong and are all specified in the note: leading digits are kept;
whitespace runs are *not* collapsed into one hyphen when an intervening token filters to empty
(`A/B testing & "quotes"` → `ab-testing--quotes`); no ASCII folding; `_` is kept intraword but
matched `_…_` emphasis pairs are stripped; empty slugs are legal, consume a dedup slot, and are
not linkable.

### Marker handling

Marker: `<!-- md2x:toc -->`, recognized per the rules in
`plan/notes/toc-defaults-and-page-heuristic.md` (whole line after trimming, case-sensitive, 0–3
leading spaces, outside code fences).

- First recognized marker: the TOC insertion point (when the TOC is on) or simply removed (when
  off).
- Later markers: removed. When two or more were found, print one stderr notice naming the count,
  e.g. `md2x: found N 'md2x:toc' markers; expanded the first and removed the rest.`
- Markers are always removed from the output, in every mode.

### Placement, heuristic, and TOC shape

All specified in `plan/notes/toc-defaults-and-page-heuristic.md`:

- **Placement** — marker position; else after the document-title heading's last source line,
  separated by a blank line; else the very top of the document.
- **Document title** — the first heading, when it is the only heading at the shallowest level
  present. Excluded from the TOC; still consumes a dedup slot.
- **Top-level section count** — the four-step rule in the note.
- **`auto` resolution** — a TOC is emitted only when estimated pages > 2 *and* top-level
  sections >= 4; a marker being present forces it on regardless.
- **Estimated pages** — `ceil(total / 45)` over per-line contributions of `1` (blank), `1`
  (inside a fence), or `max(1, ceil(len(line.strip()) / 85))`, computed after removing marker
  lines and before injecting the TOC. Express `85` and `45` as named module-level constants with
  a comment citing the note's calibration table.
- **TOC shape** — absolute levels 1–3, 2-space indent per level below the shallowest included
  level, bullet list, no heading of its own, blank line above and below, empty-slug headings
  omitted, link text with Markdown links flattened and residual `[`/`]` backslash-escaped.
- When nothing qualifies for the TOC, emit no list, and still remove the marker.

### Structure for testability

Organize the module so the tests below can exercise the pieces without reimplementing them:
a `slugify(text)`, a document scanner returning the heading records, an estimator, and a
`main()`. The tests drive the script through its stdin/stdout contract; keeping the internals
separable is for the implementer's own benefit and for the `--mode` paths to stay readable.

### Tests

Add `src/cli/test/bats/toc-preprocess.bats`.

**Deliberate convention deviation, to be stated in the file's header comment:** every other bats
file in this suite exercises the built `bin/md2x`. This one invokes the checked-in
`src/cli/lib/toc-preprocess.py` directly with the system `python3`, because the slug algorithm
needs case-level coverage that would be unreadable and slow driven through a full CLI
conversion. Integration through the CLI is task 004's concern.

Do not call `md2x_setup` (it installs stubs this file has no use for). Use a small local
setup/teardown that creates a per-case temp working directory, in the style of
`real-toolchain-e2e.bats`'s `e2e_setup`, and `load '../helpers/common'` for the assertion
helpers and the `MD2X_REPO_ROOT` path. Add a local helper that pipes a here-doc into the script
and captures stdout/stderr/status.

Required cases:

1. **Slug corpus.** Feed the 29 headings from the slug-algorithm note's table as `##` headings,
   with the TOC forced on, and assert the emitted TOC's anchors match the note's identifier
   column exactly, in order — including the `-1`/`-2` dedup suffixes and the omission of the
   first empty-slug heading.
2. **Recognition table.** One case per row of the note's heading-recognition table: fenced code,
   4-space-indented code, `#NoSpaceHash`, `#######`, trailing-hash stripping, setext `=` and
   `-`, and a heading inside a multi-line HTML comment. Assert each is or is not represented in
   the TOC.
3. **Marker handling.** Marker expanded in place; a second marker removed with the stderr notice
   emitted; a marker inside a code fence left untouched and *not* treated as an insertion point;
   the marker removed under `--mode off`.
4. **Placement.** With a document title, the TOC lands after it and not before it. Without one,
   the TOC lands at the top. With a marker, the marker position wins over both.
5. **Heuristic boundaries** under `--mode auto`, asserting on both sides of each branch:
   - 4+ top-level sections but an estimated 2 pages or fewer → no TOC;
   - more than 2 estimated pages but 3 top-level sections → no TOC;
   - more than 2 estimated pages and 4 top-level sections → TOC;
   - the exact rendered-line boundary: 90 estimated lines → no TOC, 91 → TOC, constructed from
     a document with 4+ sections so the other branch does not mask it;
   - no headings at all → no TOC;
   - a marker present in an otherwise-small document → TOC.
6. **Mode overrides.** `--mode on` emits a TOC for a one-heading, one-line document; `--mode off`
   emits none for a document that `auto` would give one.
7. **Section counting.** The five worked examples in the note's top-level-section table,
   asserted through the resulting TOC contents (title excluded; sibling `#` headings counted as
   sections when there is no single title).
8. **Pass-through fidelity.** A document with `--mode off` and no marker comes out byte-identical
   to what went in, CRLF line endings included.
9. **Link-text handling.** A heading containing a Markdown link produces a flattened, non-nested
   TOC entry; a heading containing literal `[`/`]` produces escaped ones.

## Validation

- `make test-cli` passes, with `src/cli/test/bats/toc-preprocess.bats` contributing the new
  cases and every pre-existing case still green.
- `src/cli/lib/toc-preprocess.py` exists, is valid Python 3, and imports nothing outside the
  standard library: `python3 -c "import ast,sys; ast.parse(open('src/cli/lib/toc-preprocess.py').read())"`
  succeeds and `grep -nE '^\s*(import|from) ' src/cli/lib/toc-preprocess.py` shows stdlib names
  only.
- The script's stdout is document-only: piping a document through it with `--mode on` and
  discarding stderr yields Markdown with no `md2x:` line.
- `85` and `45` appear as named constants with a comment referencing
  `plan/notes/toc-defaults-and-page-heuristic.md`.
- `make test` passes overall (`test-cli` plus `test-node`).

## Metadata

architectural_impact: true

## Assumptions

- The system `python3` is reachable from the bats cases' PATH. The suite's restricted
  `MD2X_TEST_SYSTEM_PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`) includes `/usr/bin/python3` on both
  macOS and Linux, and `src/cli/test/helpers/common.bash` already documents that md2x reaches
  the ambient system `python3` rather than a stub. If it turns out not to be reachable, add
  `python3` to `MD2X_TEST_PASSTHROUGH_TOOLS` rather than weakening the tests.
- `src/cli/lib/toc-preprocess.py` is automatically picked up as a build input: the `Makefile`'s
  `CLI_LIB_SRC` is `$(shell find src/cli/lib -type f)`. No `Makefile` change is needed.

## References

- [Pandoc GFM auto-identifier algorithm](../notes/pandoc-gfm-slug-algorithm.md) — the slug
  specification, the 29-case corpus, the heading-recognition table, and the two accepted
  divergences.
- [TOC defaults, directive syntax, and the page-count heuristic](../notes/toc-defaults-and-page-heuristic.md) —
  marker rules, placement, document-title and section-count definitions, mode resolution, the
  calibrated estimator, and the TOC's shape.
- `src/cli/lib/ensure-weasyprint.sh` — the `md2x: ` stderr-message style and the
  stdout-is-a-data-channel discipline to match.
- `src/cli/test/bats/real-toolchain-e2e.bats` — the local-setup pattern for a bats file that
  deliberately does not use `md2x_setup`.
- `src/cli/test/helpers/assertions.bash` — available assertions.

## Status

- **Outcome:** succeeded
- **Date:** 2026-07-30
- **Validation summary:** `make test-cli` passes (105/105), including all 33 new
  `toc-preprocess.bats` cases and every pre-existing case unchanged. `make test` passes overall
  (test-cli 105/105 plus test-node 22/22, 100% coverage on the untouched Node side).
  `python3 -c "import ast,sys; ast.parse(open('src/cli/lib/toc-preprocess.py').read())"`
  succeeds; `grep -nE '^\s*(import|from) ' src/cli/lib/toc-preprocess.py` shows only `math`,
  `re`, `sys`. Piping a document through the script with `--mode on` and discarding stderr
  yields no `md2x:` line on stdout. `CHARS_PER_RENDERED_LINE = 85` and
  `RENDERED_LINES_PER_PAGE = 45` are named constants with comments citing
  `plan/notes/toc-defaults-and-page-heuristic.md`. All 29 rows of the slug corpus were
  additionally cross-checked directly against `slugify()`/`allocate_slug()` in an ad hoc
  Python harness before being folded into the bats corpus case.
- **Affected source files:**
  - `src/cli/lib/toc-preprocess.py` (new)
  - `src/cli/test/bats/toc-preprocess.bats` (new)
- **Decisions:**
  - Fence and multi-line-HTML-comment tracking share one scan pass with heading/marker
    recognition, applying the task doc's per-line ordering (fence state, then marker/heading
    check gated on the *pre-update* comment state, then comment-state update) literally, so a
    line that closes a multi-line comment is itself still treated as "inside" it.
  - `toc_link_text()` flattens only `[text](url)`/`[text][ref]` link syntax (matching the
    toc-defaults note's literal wording) and leaves image syntax (`![alt](url)`) and autolinks
    alone; only genuinely nested-link-invalidating syntax is flattened, everything else falls
    through to the generic `[`/`]` escaping.
  - `allocate_slug()`'s generic collision-retry loop is applied uniformly to empty and
    non-empty base slugs (no special-casing), which reproduces the note's `` / `-1` / `-2`
    empty-heading dedup sequence for free; only a final slug that is the literal empty string
    is omitted from the TOC, so `-1`/`-2` dedup collisions on an empty base are correctly
    rendered as linkable entries.
  - Required test case 6 ("`--mode on` emits a TOC for a one-heading, one-line document") is
    implemented against a two-line, two-heading document (`# Doc Title` / `## Section`) rather
    than a literal single-heading document: per the toc-defaults note's document-title rule, a
    document with exactly one heading always makes that heading the (excluded) document title,
    so a true one-heading document can never produce a non-empty TOC under any mode. The test
    instead uses the smallest document with a non-title heading, to faithfully exercise the
    bullet's real intent (`--mode on` overriding the small-document auto-suppress heuristic).
    See `flagged_for_manager` in this task's report for the wording tension this resolves.

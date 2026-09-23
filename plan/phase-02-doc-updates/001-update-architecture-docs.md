# Update Architecture Docs

## Purpose and scope

This plan changes spec-defined CLI behavior — the `-t`/`--title <title>` API contract in
`docs/md2x-spec.md`, including a new fatal-error case for `--title` combined with a multi-file,
non-`--single-page` conversion — so it triggers the architectural-implications check per the
Project Plan Document Standards (`plugins/flow/references/project-plan-document-standards.md` in
the Flow plugin). This task is the review pass confirming `docs/md2x-spec.md` and
`docs/architecture.md` are accurate and consistent after phase 01 lands; it does not re-implement
or second-guess phase 01's code, only verifies its documentation-facing consequences are complete
and correctly stated.

Run this task using the `update-architecture-docs` task-procedure, at
`plugins/flow/task-procedures/update-architecture-docs/SKILL.md` in the Flow plugin.

## Requirements

- **Implementation task doc that surfaced this review:**
  `plan/phase-01-title-precedence/001-fix-title-precedence-for-batch-conversions.md` — by the
  time this task runs, that task has landed and already made its own `docs/md2x-spec.md` edits
  (its requirement 6: the `-t`/`--title` API table row and the CLI exit-behavior sentence) and
  its own `--help` text edit (requirement 5). This review confirms those edits are complete,
  accurate, and internally consistent with the shipped behavior — not a from-scratch authoring
  pass.
- **Architecture and spec files to review:**
  - `docs/md2x-spec.md` (the sole match of the `docs/*-spec.md` glob) — confirm the `-t`,
    `--title <title>` API table row (originally at line ~86, under
    [API definition](../../docs/md2x-spec.md#api-definition)) and the CLI exit-behavior sentence
    (originally at line ~95) accurately state: `--title` is honored only when exactly one file is
    converted outside `--single-page` (a lone directly-named file, or a search resolving to
    exactly one file), for both the output filename and the PDF header/`--infer-title` metadata;
    and that combining `--title` with more than one file in that path is a fatal, pre-conversion
    error. Also confirm UC1, UC3, and UC4 (under
    [Key use cases](../../docs/md2x-spec.md#key-use-cases)) and the "Automatic PDF header/footer"
    bullet under [General features](../../docs/md2x-spec.md#general-features) still read
    correctly against the shipped behavior — phase 01's requirement 6 expected no change to
    these, but this review should verify that expectation held rather than assume it.
  - `docs/architecture.md` — confirm it needs no corresponding change. It documents design-level
    mechanisms (the Ghostscript/`pdftk` header-footer overlay, the WeasyPrint bootstrap, the TOC
    preprocessor) rather than per-file title-derivation precedence, and a `grep -in title
    docs/architecture.md` at planning time found no passage describing this behavior — confirm
    that grep still comes back clean (or, if phase 01's implementation surfaced something
    architecture-relevant that this task doc's authors did not anticipate, document it here
    instead of silently skipping).
- **`role_doc`:** `plugins/flow/references/roles/architect-backend.md` (in the Flow plugin) —
  this is a CLI/backend component change with no data-model, cloud/infrastructure, or frontend
  dimension.

## Validation

- `docs/md2x-spec.md`'s `-t`/`--title` API table row and CLI exit-behavior sentence match the
  behavior phase 01 actually shipped (cross-check against
  `plan/phase-01-title-precedence/001-fix-title-precedence-for-batch-conversions.md`'s final
  `## Status`/outcome notes once available, not just its original `## Requirements`).
  `grep -n -- '--title' docs/md2x-spec.md` shows both updated passages.
  `grep -in title docs/architecture.md` confirms no stale or missing passage remains.
- No unrelated content in either file was altered — this is a targeted consistency review, not a
  rewrite.

## Status

**Outcome: succeeded** (2026-09-23). Review-only task — confirmed phase 01's documentation edits
are complete, accurate, and consistent with shipped behavior; no edits were required to either
file.

- **`docs/md2x-spec.md`.** Read the full file and cross-checked the `-t`/`--title <title>` API
  table row (line 86) and the CLI exit-behavior sentence (line 95) against phase 01's `## Status`
  outcome notes (`plan/phase-01-title-precedence/001-fix-title-precedence-for-batch-conversions.md`)
  and against the actual shipped code in `src/cli/md2x.sh` (the upfront file-count gate at lines
  180–194, `echoerrandexit` message at lines 188–192, and the per-file loop's `TITLE_SET` guard at
  line 336). Both passages accurately state the single-file-only precedence (a lone directly-named
  file, or a directory search resolving to exactly one file) and the multi-file fatal-error case,
  and match the wording phase 01's Status section describes it made. `grep -n -- '--title'
  docs/md2x-spec.md` shows both updated passages (lines 86 and 95).
- Also re-read UC1, UC3, UC4, and the "Automatic PDF header/footer" bullet under General
  features, per this task's requirement to confirm rather than assume phase 01's expectation of
  no change held. None of the four claims a `--title` behavior that the shipped fix contradicts:
  UC1 is single-file only; UC3 (batch-convert a directory) makes no `--title` claim at all; UC4
  concatenates via `--single-page`, an untouched path; and the header/footer bullet's "from
  `--title`, or otherwise the source filename" phrasing does not assert uniform `--title`
  behavior across a batch. No change needed to any of the four.
- **`docs/architecture.md`.** Read the full file. `grep -in title docs/architecture.md` returns
  two hits: a Mermaid diagram node label naming "title" as one of three values the PostScript
  overlay renders (line 45), and a description of the TOC preprocessor's handling of a document's
  own title *heading* for TOC-insertion placement (line 83) — both design-level mechanisms
  (Ghostscript/`pdftk` overlay rendering, TOC preprocessor placement), unrelated to per-file
  `--title` *source*-precedence, which lives entirely in `src/cli/md2x.sh`'s CLI option-handling
  layer that this document does not cover. The grep confirms clean, as the task doc anticipated —
  no stale or missing passage. No change needed.
- No unrelated content was altered in either file; this task made no edits.

Affected source files: none (review-only; no edits to `docs/md2x-spec.md` or
`docs/architecture.md` were needed). Only this task document was updated.

Validation: `grep -n -- '--title' docs/md2x-spec.md` shows both updated passages (lines 86, 95).
`grep -in title docs/architecture.md` shows only the two pre-existing, unrelated hits described
above — confirmed clean of stale/missing title-precedence content.

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

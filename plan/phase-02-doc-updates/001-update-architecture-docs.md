# Update Architecture Docs

## Purpose and scope

Update md2x's architecture, specification, and layout documentation to reflect the
Markdown-based TOC generation delivered in Phase 01. The change adds a new stage to the
conversion pipeline, adds a new source file, changes a documented CLI and Node-library surface,
and changes spec-defined behavior in three places — none of which the Phase 01 tasks touch.

Run the `update-architecture-docs` task-procedure at
`plugins/flow/task-procedures/update-architecture-docs/SKILL.md`.

role_doc: plugins/flow/references/roles/architect-backend.md

## Requirements

### Implementation task documents that surfaced the architectural implications

These are the Phase 01 task documents whose changes this doc update must reflect. All of them
will have been completed by the time this task runs; read them, and the notes they cite, for the
authoritative behavior.

- `plan/phase-01-markdown-toc-generation/002-add-toc-preprocessor-script.md` — introduces
  `src/cli/lib/toc-preprocess.py`, a new component in the pipeline.
- `plan/phase-01-markdown-toc-generation/003-add-toc-flag-and-conflict-check.md` — adds the
  `--toc` CLI flag and the Node library's `toc` option; adds a new fatal-error path.
- `plan/phase-01-markdown-toc-generation/004-wire-preprocessor-into-generate-page.md` — inserts
  the preprocessing stage into `generate-page()`, retires Pandoc's `--toc`, and replaces the
  process-substitution input with a materialized temp file.
- `plan/phase-01-markdown-toc-generation/001-fix-single-page-combined-file-naming.md` — corrects
  the `--single-page` input filename that the materialized-input change depends on.

Supporting design notes, which carry the verified detail these docs should summarize rather than
duplicate: `plan/notes/pandoc-gfm-slug-algorithm.md`,
`plan/notes/toc-defaults-and-page-heuristic.md`, `plan/notes/pipeline-verification.md`.

### Files to review and update

- **`docs/architecture.md`**
  - The Mermaid `flowchart` in [System overview](../../docs/architecture.md#system-overview):
    the `Rewrite` node's description and the `Pandoc` node's `+ optional TOC` annotation are both
    now wrong. Add the TOC-preprocessing stage as its own node ahead of the link-rewriting node,
    and drop the TOC from Pandoc's box.
  - The numbered prose walkthrough beneath the diagram (the paragraph explaining the diagram for
    non-visual readers): insert the new step and renumber. Step 4 currently says Pandoc embeds
    "unless `--no-toc` is given, a table of contents" — that is no longer what happens.
  - [Major components](../../docs/architecture.md#major-components): add a subsection for the TOC
    preprocessor, and correct the "Page generation / conversion pipeline" subsection, which
    currently says `generate-page.sh` embeds "the TOC flag" and lists the intermediate artifacts
    it cleans up (a fourth temp file now joins them).
  - The [Bundled stylesheet](../../docs/architecture.md#bundled-stylesheet) subsection documents
    the `bash-rollup` heredoc-inlining technique for `github.css`; the Python source now travels
    the same way, and the new component subsection should say so rather than re-explaining it.
  - [Key decisions](../../docs/architecture.md#key-decisions): add a decision entry for
    generating the TOC as Markdown content rather than using Pandoc's `--toc`. It should record
    the rationale (one consistent, author-placed TOC across all three output formats; DOCX
    previously got none because Pandoc's docx `--toc` emits an unrendered Word field code; and
    Pandoc's html5 template placed the nav block above the document's own title) and the
    trade-off (md2x now has to replicate Pandoc's `gfm_auto_identifiers` slug algorithm exactly,
    and carries a documented divergence for emoji and for headings nested in blockquotes/lists).
  - The test-suite decision entry should note that the slug algorithm's correctness is asserted
    against real Pandoc in `real-toolchain-e2e.bats`, since the stub boundary cannot see it.

- **`docs/md2x-spec.md`**
  - [UC2](../../docs/md2x-spec.md#uc2-convert-a-markdown-file-to-html-or-docx): "DOCX output
    never receives the header/footer overlay or an automatic table of contents (regardless of
    `--no-toc`)" — the TOC half is now false; DOCX does receive one. The header/footer half is
    still true.
  - [General features](../../docs/md2x-spec.md#general-features): rewrite the
    **Table of contents** bullet completely. It must state that md2x generates the TOC itself as
    Markdown content (not via Pandoc's `--toc`), that it applies uniformly to PDF, HTML, and
    DOCX, where it is placed, the `<!-- md2x:toc -->` marker, and the `--toc`/`--no-toc`/default
    resolution including the size heuristic. State the heuristic in behavioral terms ("more than
    about two rendered pages and four or more top-level sections"); the calibrated constants are
    an implementation detail belonging in `docs/architecture.md`, not the spec.
  - [CLI flags table](../../docs/md2x-spec.md#cli): add `--toc`; rewrite `--no-toc`, whose
    current text ("Has no effect on `docx` output, which never receives one") is false.
  - [Exit behavior](../../docs/md2x-spec.md#cli): add the both-flags-given fatal error to the
    enumerated non-zero exits.
  - [Node library](../../docs/md2x-spec.md#node-library): add `toc` to the options object.
  - Consider whether the marker warrants a new use case or a note under
    [Constraints and assumptions](../../docs/md2x-spec.md#constraints-and-assumptions); use
    judgment, and do not add a use case if the General-features bullet already covers it.

- **`docs/project-structure.md`**
  - The directory tree and the [`src/`](../../docs/project-structure.md#src) narrative both
    enumerate `src/cli/lib/`'s contents; add `toc-preprocess.py`.
  - The `src/cli/test/` listing should mention the new bats files and any new fixture Phase 01
    added under `src/cli/test/`.

- **`AGENTS.md`** — review only. Its "Code organization" bullet for `src/cli/lib/` lists the
  library scripts by name and needs the new file added. Nothing else there should need to change;
  if the test-suite paragraph's description of what the stubs can and cannot cover is still
  accurate, leave it.

### Constraints

- Read what Phase 01 actually landed before writing; the task documents describe intent, the
  code is the truth. Where they differ, document the code and flag the divergence.
- Do not copy the calibration tables or the 29-case slug corpus out of `plan/notes/` into
  `docs/`. The plan directory is torn down at session close, so the docs must stand on their own
  — summarize the *decisions* and their rationale, and state the constants where architecture
  detail warrants them, without transplanting the working data.
- `README.md` and `CHANGELOG.md` were updated in Phase 01 task 006; do not re-edit them beyond
  correcting an outright contradiction, and say so in your report if you find one.

## Validation

- `docs/architecture.md`, `docs/md2x-spec.md`, `docs/project-structure.md`, and `AGENTS.md` have
  each been read in full and updated where the requirements above call for it, or explicitly
  confirmed as needing no change.
- `grep -rn 'never receives an automatic table of contents' docs/` returns nothing.
- `grep -rn 'unless `--no-toc` is given, a table of contents' docs/` returns nothing.
- `grep -rn 'toc-preprocess' docs/ AGENTS.md` shows the new file recorded in both the
  project-structure tree/narrative and `AGENTS.md`'s code-organization list.
- `grep -n -- '--toc' docs/md2x-spec.md` shows both the new flag row and the rewritten
  `--no-toc` row.
- The Mermaid diagram in `docs/architecture.md` still parses (render it, or confirm the node/edge
  syntax matches the surrounding style) and its explanatory prose paragraph matches the node set.
- Every relative link added or touched resolves to a real path.
- Each document's own table of contents lists any newly added section.

## References

- `plugins/flow/task-procedures/update-architecture-docs/SKILL.md` — the procedure to run.
- `plan/notes/pandoc-gfm-slug-algorithm.md`, `plan/notes/toc-defaults-and-page-heuristic.md`,
  `plan/notes/pipeline-verification.md` — the verified design detail behind the decisions being
  documented.
- `plan/overview.md` — the decision table summarizing what was chosen and why.

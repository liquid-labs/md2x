# Update Architecture Docs

## Purpose and scope

Review md2x's architecture and specification documents against what Phase 01 landed, and update them where they no longer describe the system. Two changes in Phase 01 have documentation implications: the mirrored-output path derivation now has precise, general semantics (it previously stripped a hardcoded `/policy/` segment), and md2x now has an automated test surface with a deliberate stub boundary at the external-tool integration points.

Run the [`update-architecture-docs`](flow-mcp:d) task-procedure at `plugins/flow/task-procedures/update-architecture-docs/SKILL.md`.

role_doc: `plugins/flow/references/roles/architect-backend.md`

## Requirements

### Planned task documents that surfaced the architectural implications

These are the Phase 01 implementation tasks whose changes this review covers; all will have landed before this task runs. Read each task document and the resulting diff:

- `plan/phase-01-automated-test-coverage/002-fix-mirrored-output-path-derivation.md` — changed spec-defined behaviour: the non-`--flatten-dirs` output path is now derived relative to the search root a file was found under, rather than by stripping a hardcoded `/policy/` segment. Also made `--flatten-dirs` create its output path.
- `plan/phase-01-automated-test-coverage/001-stand-up-test-infrastructure.md` — introduced the automated test surface, including stub `pandoc`/`gs`/`pdftk` executables that stand in for the external tools at the boundary `docs/architecture.md` describes, and relocated the interactive smoke test to an opt-in target.
- `plan/phase-01-automated-test-coverage/003-cover-cli-option-behavior.md`, `004-cover-node-wrapper.md`, `005-add-gated-end-to-end-tests.md` — the resulting coverage; read these mainly for behaviour discrepancies their agents reported against the spec.

### Files to review and update where needed

- `docs/md2x-spec.md` — principally **UC3** ("Batch-convert a directory of Markdown files"), whose outcome statement, "each output file is written under `./out` at a path that mirrors the file's location in the input tree", is now imprecise: state that the mirrored path is relative to the search root the file was found under (the directory argument given on the command line, or the input file's own directory for a file named directly). Check the `-D`/`--flatten-dirs` and `-p`/`--output-path` rows in the flag table for the same imprecision. Also check whether any behaviour discrepancy reported by tasks 003/004 needs the spec to be made explicit rather than the code changed — flag, do not silently rewrite the contract.
- `docs/architecture.md` — check whether the CLI entry point / page generation component descriptions need to mention search-root-relative output derivation, and whether the document should acknowledge the test surface's stub boundary at the Pandoc/Ghostscript/pdftk integration points, since that boundary is now load-bearing for development. Add only what genuinely belongs at the design layer; do not restate the spec.
- `docs/project-structure.md` — verify the `src/cli/test/` description matches the layout that actually landed (task 001 was asked to update it; confirm rather than assume).
- `README.md` — verify the `--flatten-dirs` row and the Features list still read correctly against the landed behaviour.
- `AGENTS.md` — verify the build/test section describes the landed targets and that the "Known issues" bullet pointing at followup `aI57` is gone (task 002 was asked to remove it; confirm rather than assume).

Keep the scope to conforming the docs to the system. Do not introduce new architectural material unrelated to Phase 01, and do not restructure documents that are merely imprecise in one sentence.

## Validation

- `docs/md2x-spec.md` UC3 and the `--flatten-dirs` / `--output-path` flag rows describe search-root-relative derivation, and match the worked examples in `plan/notes/mirrored-output-path-contract.md`.
- `docs/architecture.md` contains no statement contradicted by the Phase 01 diff; any addition about the stub boundary is at the design layer and does not duplicate the spec.
- `grep -rn 'policy' docs/ README.md AGENTS.md` returns no stale reference to the removed `/policy/` convention.
- `grep -rn 'aI57' AGENTS.md docs/ README.md` returns nothing.
- `grep -rn 'test\.sh' AGENTS.md docs/` refers only to the relocated opt-in smoke-test path, never to a default `make test` step.
- The commands named in `AGENTS.md`'s build/test section all run successfully as written.
- Every document touched still conforms to the project documentation standards: `## Purpose and scope` opens each doc, tables of contents match headings, and all relative links resolve.
- `make qa` passes (nothing in this task should affect it, so a failure means something upstream is broken and should be reported, not patched here).

## Assumptions

- All Phase 01 tasks have landed and merged.
- Task 001 already updated `docs/project-structure.md` and `AGENTS.md`'s build/test section, and task 002 already removed the `AGENTS.md` "Known issues" bullet and may have made a minimal README/spec wording tweak. This task verifies and completes that work rather than redoing it — check the actual state before editing.
- Behaviour discrepancies that tasks 003 and 004 reported as candidate followups are the manager's to triage. Do not fix code here; if a discrepancy means a doc is wrong, flag it rather than quietly changing the documented contract.

## Metadata

architectural_impact: true

## References

- `plugins/flow/task-procedures/update-architecture-docs/SKILL.md` — the procedure to run.
- [Mirrored output path contract](../notes/mirrored-output-path-contract.md) — the authoritative statement of the new derivation semantics, with worked examples.
- [Test tooling survey](../notes/test-tooling-survey.md) — the stub-boundary decision and its rationale.
- [`docs/md2x-spec.md`](../../docs/md2x-spec.md), [`docs/architecture.md`](../../docs/architecture.md), [`docs/project-structure.md`](../../docs/project-structure.md), [`README.md`](../../README.md), [`AGENTS.md`](../../AGENTS.md) — the documents under review.

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

## Status

**Outcome: succeeded** — 2026-07-29.

Read `plan/overview.md`, all five Phase 01 task documents (and their landed diffs), the mirrored-output-path-contract and test-tooling-survey notes, and all five arch/spec files in full before editing.

### Findings by file

- `docs/md2x-spec.md` — **already fully updated by task 002.** UC3's outcome statement and the `-D`/`--flatten-dirs` flag-table row already state the search-root-relative contract precisely, matching every worked example in the contract note verbatim (verified `git show` of task 002's commit `b620b0b`). No edit needed. No spec-vs-code discrepancy from tasks 003/004 rises to "the spec's contract is wrong" — see [Flagged for manager](#flagged-for-manager-not-fixed-here) below.
- `README.md` — **already fully updated by task 002.** The `--flatten-dirs` row states the search-root-relative contract correctly; the Features list needed no change. No edit needed.
- `AGENTS.md` — **already correct.** The "Build and test" section fully and accurately describes `make test` / `make test-cli` / `make test-node` / `make smoke-test` / `make lint` / `make qa`, the stub-boundary rationale, and the opt-in visual smoke test; the "Known issues" section (and its `aI57` bullet) is gone, confirmed via `git show` of task 002's commit. No edit needed.
- `docs/project-structure.md` — task 001's `src/cli/test/` rewrite is accurate and complete. **One gap found and fixed:** the "Key root-level files" table's `Makefile` row still only listed `make all`/`make test`/`make qa`/`make clean` (unchanged since before Phase 01), omitting the `make test-cli`/`make test-node`/`make smoke-test` targets task 001 added. Updated that one table cell to name them.
- `docs/architecture.md` — **not touched by any Phase 01 task**, so its whole content had to be checked fresh. Two additions made, both flagged as needed by this task's own file-review guidance:
  1. "CLI entry point and argument parsing" (Major components) gained one sentence noting that file discovery now carries the search root each file was found under alongside the file path, so the entry point can derive mirrored output placement relative to that root (or write flat into `--output-path` under `--flatten-dirs`). Placed here rather than "Page generation" because `git show` of task 002's diff confirms the derivation lives entirely in `src/cli/md2x.sh`'s own loop, not `generate-page.sh`.
  2. A new bullet in "Key decisions" acknowledging the test-stub boundary: grounded in the same "CLI orchestrates subprocesses, owns no rendering" framing already present in the doc's own Tech stack section, states the decision and the accepted trade-off (stub suite can't catch a real Pandoc/Ghostscript/pdftk regression; the gated e2e set covers that), and links to `AGENTS.md` rather than restating the test procedure.
  No existing statement in the file was contradicted by the Phase 01 diff, so nothing else needed changing.

### Validation performed

- `grep -rn 'policy' docs/ README.md AGENTS.md` — no hits.
- `grep -rn 'aI57' AGENTS.md docs/ README.md` — no hits.
- `grep -rn 'test\.sh' AGENTS.md docs/` — both hits are the relocated `manual/visual-smoke-test.sh` opt-in path; no default-`make test` reference.
- `make qa` — exit 0, both before and after the edits (61 bats cases + 17 Jest cases + lint, all green).
- `git status --porcelain` after all edits shows only `docs/architecture.md` and `docs/project-structure.md` modified — no other file touched, `plan/followups.yaml` untouched.
- Re-read both edited files in full: `## Purpose and scope` still opens each, the tables of contents still match the (unchanged) heading sets, and every link touched or adjacent to an edit (`../AGENTS.md` from `docs/architecture.md`) resolves.

### Flagged for manager (not fixed here)

- **Pre-existing, out-of-scope doc self-contradiction (already tracked as followup `LPg7`):** `AGENTS.md`'s "Code organization" and "Documentation" sections, and `docs/architecture.md`'s "Pointers" section, still mark `docs/project-structure.md` and `docs/architecture.md` as "(planned)" even though both have existed since the single commit (`6061449`, "standard project docs") that created the whole doc set — i.e. this was self-contradictory from the moment it was authored, not something Phase 01 caused to go stale. `README.md`'s own "Additional documentation" list, from the same commit, does *not* carry the "(planned)" qualifier, so the inconsistency is also cross-file. Left untouched per this task's scope (unrelated to what Phase 01 changed) and because the task document's own file-by-file checklist doesn't name it; `LPg7`'s text already attributes ownership to this task, so the manager may want to fold its resolution into a small explicit follow-on rather than leave it implicit.
- **Spec-vs-code discrepancies from tasks 003/004 — confirmed already tracked, none require a spec rewrite:** the `--output-format html` per-file `-base` suffix (`c2s9`), the unreachable `title = 'Report'` default (`aaLV`/`udVi`), and the `undefined.md` staging filename (`8SZc`/`egcc`) are all pre-existing followups with their own regression-test coverage from tasks 003/004. None of them looked like a case where the spec itself needs to change to match reality (as opposed to the code needing a fix) — the spec's stated contracts for output filenames, the Node title default, and the markdown staging path all remain the *intended* behavior; the code just doesn't yet fully deliver on them. So per this task's "flag, don't rewrite the contract" instruction, none of the three arch/spec files were altered for these.
- **`docs/project-structure.md`'s `docs/` section** ("Further docs (e.g. `docs/architecture.md`) would land here as the project grows") and its "Related documents" list (which omits `docs/architecture.md`) are also stale relative to `docs/architecture.md`'s actual existence, for the same pre-existing reason as the "(planned)" tags above. Left untouched for the same reason; flagging alongside `LPg7` since it's the same underlying issue.

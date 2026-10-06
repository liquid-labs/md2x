# Update Architecture Docs

## Purpose and scope

Bring `docs/architecture.md` and `docs/md2x-spec.md` into conformance with the changes this plan makes in Phases 1 to 3. Follow the `update-architecture-docs` task-procedure at `plugins/flow/task-procedures/update-architecture-docs/SKILL.md`.

This task runs after Phase 3, whose docs tasks already rewrite the spec's flag reference to point at the README table. Its job is a final architecture-and-spec conformance pass against the merged code, not a second README overhaul. It edits only `docs/architecture.md` and `docs/md2x-spec.md`. `docs/project-structure.md` is changed only if this review finds it inconsistent with the final source tree.

## Requirements

- `role_doc: plugins/flow/roles/architect-backend.md`
- Task-procedure: `plugins/flow/task-procedures/update-architecture-docs/SKILL.md`.
- **Task documents that surfaced the architectural implications.** The implementation task documents for these phases are authored by the phase-decomposition agents and do not exist yet. Review every task document under the following directories, relative to the plan worktree, and treat those flagged `architectural_impact: true` as the primary sources:
  - `plan/phase-01-correctness-and-regression-tests/*.md`: the error helper and exit-code contract, the project-owned option parser and getopt resolution, bash 3.2 support and the POSIX guard, the per-run work directory, stdin handling, inline HTML CSS, and title-safe sinks.
  - `plan/phase-02-interface-contract/*.md`: `--version` build-time injection, `-o/--output` and `--to-stdout`, input discovery and collision checks, the Pandoc Lua link and image filter that replaces the `perl` converter, lazy version inference, the pandoc version floor, the pruned stylesheet, and the rewritten Node wrapper (child_process, ESM/CJS/types `exports`, `md2xAsync`).
  - `plan/phase-03-docs-ci-and-release-readiness/*.md`: CI, the flag-table single source, and package metadata.
- **Files to review and update:**
  - `docs/architecture.md`. At minimum, check "System overview", "Tech stack", every "Major components" subsection, the "Build pipeline", and "Key decisions". Expected changes include:
    - the parser that replaces the bash-toolkit one, and the fact that it no longer needs `brew`
    - the new Lua filter component and how it is inlined and passed to pandoc
    - the per-run work directory
    - the Node wrapper's process model and dual build
    - `--version` injection in the `Makefile`
    - the reduced dependency set, with `perl` gone and `git` and `jq` conditional
  - `docs/md2x-spec.md`, found by globbing `docs/*-spec.md`. Check the use cases, "General features", "API definition" (CLI and Node library), "Constraints and assumptions", and "Non-goals". It must state:
    - the exit-code contract: 0 success, 1 runtime, 2 usage, 3 dependency
    - the short-flag set `-D -F -h -o -p -s -t`, either directly or by linking the README table
    - the conflict rules for `-o`, `--to-stdout`, and `--output-path`
    - the final dependency set and the bash 3.2 floor
    - that N4 (`--jobs` and progress) and N8's header and footer features are deferred, not supported
- Every statement in both files must match the final code. Where the spec and README overlap, the spec links to the README flag table rather than duplicating it, per the [flag table decision](../notes/design-decisions.md#flag-table-single-source).

## Validation

- `docs/architecture.md` and `docs/md2x-spec.md` were each reviewed, and the task report lists the sections changed or confirmed unchanged.
- `grep -n -i "perl\|brew\|shelljs\|LINK_CONVERTER" docs/architecture.md docs/md2x-spec.md` returns only statements that describe these as removed or optional.
- `grep -n "exit" docs/md2x-spec.md` shows the 0/1/2/3 contract, and no remaining text says missing dependencies exit 2.
- Every component named in `docs/architecture.md` exists in `src/`, and every new component from Phases 1 and 2 (the parser module and the Lua filter) is named.
- The bats flag-table drift test from Phase 3 still passes, and `make qa` is green.
- Both files follow the markdown style standards: sentence-case section titles and a `## Purpose and scope` section.

## Metadata

architectural_impact: true

## References

- [Design decisions](../notes/design-decisions.md): the authoritative statement of every behavior these docs must describe.
- [Audit coverage](../notes/audit-coverage.md): the D1 and D2 rows, about the spec's dependency list and the gnu-getopt requirement.
- [Brew and getopt resolution](../notes/brew-and-getopt-resolution.md): the getopt dependency facts.
- User answers: [exit codes](../notes/exit-code-contract-answer.md), [short flags](../notes/short-flag-set-answer.md), and [N4/N8 scope](../notes/n4-n8-scope-answer.md).

## Status

- Outcome: succeeded (2026-10-05).
- `docs/architecture.md`: rewrote System overview (diagram, 10-step sequence, exit-code contract), Tech stack, and Build pipeline; fixed CLI entry point, WeasyPrint bootstrap (exit 3, single run-wide trap), TOC preprocessor, Page generation, Bundled stylesheet, and Node wrapper; added component subsections (option parser, dependency preflight, version inference, error helpers, title handling, output planning, output staging and delivery, link and image filter, run cleanup and exit-status trap); added Key decisions for each Phase 1 to 3 change.
- `docs/md2x-spec.md`: reviewed against the code and confirmed consistent (exit codes, short flags, conflict rules, dependency set, bash 3.2 floor, deferred N4/N8); only the Pointers entry for the architecture doc was extended. `docs/project-structure.md` was consistent and unchanged.
- Validation: perl/brew/shelljs/LINK_CONVERTER greps show only removed/optional statements; spec exit grep shows 0/1/2/3; `make qa` and `flag-table-drift.bats` pass (log: `.flow/validation-logs/01-make-qa.log`).

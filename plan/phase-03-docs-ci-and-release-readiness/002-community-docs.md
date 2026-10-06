# Community Docs

## Purpose and scope

Create `CHANGELOG.md`, `CONTRIBUTING.md`, and `SECURITY.md` at the repository root. Covers audit items D9 (changelog), D10 (contributing, security), and part of D13. Touches only those three new files.

Parallel-eligible: no dependency on other Phase 3 tasks. The [README overhaul](./007-readme-overhaul.md), the [release procedure](./006-release-procedure-and-dry-run.md), and the [AGENTS.md update](./008-spec-agents-and-structure-docs.md) link to these files.

## Requirements

- **`CHANGELOG.md`.** Keep a Changelog format with an `Unreleased` section targeting `1.0.0`. Summarize the changes since `1.0.0-alpha.11`, and call out a **Breaking changes** list that includes at least:
  - Missing or unusable dependencies now exit `3` instead of `2`. The full contract is 0 success, 1 runtime or conversion failure, 2 usage error, 3 dependency ([exit-code answer](../notes/exit-code-contract-answer.md)).
  - `-s` now means `--to-stdout` (it formerly meant `--single-page`, contrary to the docs).
  - The undocumented auto-shorts `-q`, `-l`, `-n`, `-i` are removed and are now usage errors.
  - The Node wrapper's default title is `output`, not `Report`.
  - Other behavior changes from Phases 1 and 2, found by reading the merged code and `git log` (for example: `--to-stdout` no longer writes a file, `sources: ['-']` throws, output-name collisions and empty-input conditions are errors, `*.markdown` discovery, Node `shelljs` replaced by `node:child_process`, `perl` no longer needed, `--version` added). Verify each item against the code before listing it.
  - Include Added, Changed, Fixed, and Removed groupings, with the six must-fix defects under Fixed (see [overview success criteria](../overview.md)).
- **`CONTRIBUTING.md`.** Dev setup (`bun install`, prerequisites matching the README dependency set), `make all`, `make qa`, how to run the bats suite including the bash 3.2 override and the gated real-toolchain tests, the rule that every bug fix carries a regression test, markdown and code style pointers (`make lint`), how to run `make smoke-test`, and how to propose changes. Describe CI generically (do not assert it is green). Keep code 3.2-compatible.
- **`SECURITY.md`.** Supported versions, how to report a vulnerability privately (use GitHub's private security advisory flow for `liquid-labs/md2x`; use `zane@liquid-labs.com`-style contact only if the maintainer's address appears in `package.json`'s `author`), expected response, and scope notes: md2x converts untrusted Markdown, remote resources referenced from the document (images, links) can be fetched by pandoc or WeasyPrint during PDF generation (the SSRF caveat), and the CLI executes local tools (pandoc, gs, pdftk, python3).
- Use lowercase `liquid-labs` in every URL. Follow the markdown style standards (sentence-case headings; no trailing whitespace).

## Validation

- The three files exist at the repo root; `grep -n "exit 2\|exits 2" CHANGELOG.md` shows `2` only as the usage code or the old-to-new transition.
- `grep -n -i "Liquid-Labs" CHANGELOG.md CONTRIBUTING.md SECURITY.md` returns nothing (lowercase org only).
- Every breaking change in the Requirements list appears in `CHANGELOG.md`.
- Every command named in `CONTRIBUTING.md` exists (check `Makefile` targets and `package.json` scripts).
- `make qa` passes (no code files were touched).

## Metadata

architectural_impact: false

## Assumptions

- Phases 1 and 2 are merged, so the final behavior can be read from the code.
- No version is released by this task; the changelog entry is `Unreleased` until the [release task](./006-release-procedure-and-dry-run.md) dates it.

## References

- [Design decisions](../notes/design-decisions.md): exit-code contract, short flags, Node wrapper defaults.
- [Audit coverage](../notes/audit-coverage.md): rows D9, D10.
- [Phase summary](../phases/docs-ci-and-release-readiness.md)

## Status

Succeeded, 2026-10-05. Created [CHANGELOG.md](../../CHANGELOG.md), [CONTRIBUTING.md](../../CONTRIBUTING.md), and [SECURITY.md](../../SECURITY.md). Validation: files present, no capitalized org name, no trailing whitespace, `make qa` passed. The title-precedence fix predates alpha.11 so it is not listed under Fixed.

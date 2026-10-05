# Golden Release Hardening

## Purpose and scope

Harden md2x (`@liquid-labs/md2x`, currently `1.0.0-alpha.11`) for a golden 1.0 release.

**In scope:**

- Every blocker, should-fix, and nice-to-have item in the three 1.0 audits, except the feature parts of N4 and N8 that the user deferred. The audits are `<project_root>/.flow/audit-interface.md`, `audit-docs.md`, and `audit-release.md`, and every item is mapped in the [audit coverage matrix](./notes/audit-coverage.md).
- The user's binding decisions, including the three answers given during planning: the [exit-code contract](./notes/exit-code-contract-answer.md), the [short-flag set](./notes/short-flag-set-answer.md), and the [N4/N8 scope](./notes/n4-n8-scope-answer.md).
- The open followup `psgq`. The other folded-in followup, `zwH4`, was already fixed in `35c8d54` and has been closed.
- N8's robustness part: non-ASCII and PostScript-special titles (`\`, `(`, `)`, control characters) must not crash or corrupt the PDF header and footer overlay.

**Out of scope, filed as followups only:**

- epub, odt, and latex output formats
- custom CSS and styling options
- a config file and env namespace
- a self-contained HTML option
- N4: `--jobs` parallelism and progress output (user decision; followup `1wy6`)
- N8's feature parts: a configurable header and footer, a first-page header, and font choice (user decision; followup `1wy6`)

**Must not change:**

- The PDF rendering approach: HTML5 intermediate, WeasyPrint, Ghostscript overlay, and pdftk.
- md2x's own TOC generation and its Pandoc slug parity.
- The mirrored output layout and `--flatten-dirs` semantics.
- The `Created <file>` and `--list-files` stdout contracts.
- The CLI-first design, in which the Node library passes through to the CLI.
- GNU getopt long-option abbreviation behavior (user decision 6).

**Success criteria:**

1. Each of the six must-fix defects is fixed and covered by a regression test that fails on the old code:
   - single-page source deletion
   - stdin corruption and the silent exit on empty stdin
   - unstyled HTML
   - the bash 3.2 silent exit 0
   - the wrong `-s` and the hidden shorts
   - the unsanitized `--title`, including non-ASCII and PostScript-special titles in the PDF overlay
2. Every other audit item is implemented with a test or documentation change. The only exceptions are N4 and N8's feature parts, which the user deferred.
3. The exit-code contract is 0 success, 1 runtime or conversion failure, 2 usage error, and 3 missing or unusable dependency. Every exit path follows it.
4. The short flags are exactly `-D -F -h -o -p -s -t`, with `-s` meaning `--to-stdout`. `--version` is long-only, and `-q`, `-l`, `-n`, and `-i` are rejected as usage errors.
5. `make qa` is green locally on macOS, and also under `/bin/bash` 3.2 through the harness interpreter override.
6. A GitHub Actions workflow for macOS and Linux exists. It is proven once the branch is pushed, which is a user action.
7. README, spec, `--help`, and the parser cannot drift on flags, because a drift test enforces agreement.
8. The Node package works from a packed tarball under native ESM named import, CJS `require`, and TypeScript types.
9. The release procedure is documented and dry-run rehearsed.
10. `docs/architecture.md` and `docs/md2x-spec.md` conform to the final behavior.

## Current status

Planning. No implementation work has started. The plan worktree branches from `main` at `7b413bc`.

Phase 1 begins first. Its tasks run as a serial chain because nearly all of them edit `src/cli/md2x.sh`.

Pre-conditions and known state:

- The development host has the real toolchain: pandoc 3.10.1, gs 10.07.1, pdftk, a WeasyPrint venv, Homebrew bash 5, and the system `/bin/bash` 3.2.57.
- `main` is 117+ commits ahead of `origin`.
- All planning questions are answered. The task breakdown for Phases 1 to 3 is still to be authored by the phase-decomposition agents. Phase summaries are under [`phases/`](./phases/). Phase 4 (documentation updates) has its single task authored.

## Overview

The full decision rationale is in [design decisions](./notes/design-decisions.md). The suggested task split and file-serialization constraints are in [sequencing and file ownership](./notes/sequencing-and-file-ownership.md).

### Phase 1: Correctness and regression tests

This phase fixes the six must-fix defects and lays the foundations later phases rely on:

- **Error helper and exit codes.** A project-owned error helper and the user-confirmed exit-code contract: 0 success, 1 runtime, 2 usage, 3 dependency.
- **Option parser.** A project-owned parser with an explicit short-flag table. `-s` becomes `--to-stdout`, and `-q`, `-l`, `-n`, and `-i` are removed. It resolves GNU getopt without `brew`, and `--help` works without getopt.
- **Bash 3.2.** Compatibility with bash 3.2, plus a harness interpreter override.
- **Work directory.** A per-run work directory for every intermediate. This fixes B1 and keeps `pandoc-log.log` and other intermediates out of the cwd.
- **stdin.** Byte-exact stdin handling.
- **HTML CSS.** HTML output gets inline CSS.
- **Title sinks.** `--title` is made safe in its filename, metadata, PostScript, and Node sinks. Non-ASCII and PostScript-special titles must not crash `gs` (N8 robustness). N8's header and footer features are deferred.

Each fix carries its own regression test. Summary: [correctness and regression tests](./phases/correctness-and-regression-tests.md).

### Phase 2: Interface contract

This phase locks the 1.0 interface:

- **New CLI surface.** `--version`, a no-args usage hint, and empty-directory errors. `-o/--output`, and a pure `--to-stdout`.
- **Validation.** Input discovery and validation, and output-collision protection.
- **Links and images.** Both resolve against each source file's directory, through a Pandoc Lua filter. This removes `perl` and `eval`.
- **Hygiene.** Lazy, unquoted version inference with no `cat: package.json` noise, raw-error-leak cleanup, and a pandoc version floor.
- **Stylesheet.** A WeasyPrint warning-free `github.css`. This work is parallel-eligible.
- **Node wrapper.** A modernized wrapper with an ESM, CJS, and types `exports` map, `node:child_process`, `markdown` over stdin, `sources: ['-']` and option validation, and an async variant. This work is parallel-eligible after the `--version` and `Makefile` work.

Summary: [interface contract](./phases/interface-contract.md).

### Phase 3: Docs, CI, and release readiness

This phase covers:

- **README overhaul.** Platform matrix, precise dependencies, exit codes, troubleshooting, the full Node options, and no "other formats" claims.
- **Other docs.** Spec, AGENTS.md, and project-structure updates, plus the flag-table drift test.
- **Community files.** `CHANGELOG.md`, `CONTRIBUTING.md`, and `SECURITY.md`.
- **CI.** GitHub Actions on macOS and Linux.
- **Lint and packaging.** Lint config and dependency bumps, and `package.json` metadata.
- **Release.** RELEASING.md and release-script fixes, with a dry-run rehearsal.
- **psgq.** The slug-probe optimization.

CI, community docs, and psgq can start in parallel. The rest is chained by file ownership.

Summary: [docs, CI, and release readiness](./phases/docs-ci-and-release-readiness.md).

### Phase 4: Documentation updates

The plan changes public interfaces, spec-defined behavior, and the runtime dependency set, and it adds a Lua filter component. This phase holds one task, [update architecture docs](./phase-04-doc-updates/001-update-architecture-docs.md). It reviews `docs/architecture.md` and `docs/md2x-spec.md` against the final code and fixes anything the Phase 3 docs work left inconsistent.

### Parallelism and dependencies (summary)

| Phase | Serial chain | Parallel-eligible |
| --- | --- | --- |
| Phase 1 | all tasks (`md2x.sh`, `generate-page.sh`) | none |
| Phase 2 | the `md2x.sh` and `generate-page.sh` tasks | stylesheet pruning; Node wrapper, after the `--version`/`Makefile` task |
| Phase 3 | lint, then metadata, then releasing; README, then spec/AGENTS (after CI and lint), then drift test | CI, community docs, psgq |
| Phase 4 | the single architecture-docs task, after Phase 3 | none |

## Findings recorded for the user

### Brew is a required dependency today

The user believed `brew` is an optional install-if-missing helper. **The code says otherwise. Today `brew` is a hard runtime requirement on macOS for every invocation, including `--help`.**

- The rolled-in bash-toolkit option parser runs `brew --prefix gnu-getopt` at load time.
- Without `brew`, md2x dies with `brew: command not found` (rc 127).
- If `brew` is present but gnu-getopt is not installed, `brew --prefix` still prints a path. The result is a cryptic "No such file" failure.
- md2x never installs anything through `brew`.

The plan's Phase 1 parser makes `brew` genuinely optional. It probes the standard gnu-getopt locations first and uses `brew --prefix` only as a fallback. GNU getopt itself remains required on macOS. The full evidence is in [brew and getopt resolution](./notes/brew-and-getopt-resolution.md).

### Followup zwH4 was already fixed and is closed

The fix is commit `35c8d54`, with a regression test in `weasyprint-bootstrap-locking.bats`. The followup has been closed, and nothing is re-implemented. The only remaining effect on this plan is that the three `ensure-weasyprint` failure functions move to exit code 3 in Phase 1. psgq is planned for Phase 3. Details are in [followup verification](./notes/followup-verification.md).

### The `bun publish` path has never run live

`1.0.0-alpha.11` was published through `npm publish`; the release script switched to `bun publish` afterwards. The "unverified" note in `RELEASING.md` is therefore still accurate and must be reworded, not deleted. A user-run prerelease publish before `1.0.0` is recommended.

### `perl` and `jq` leave the always-required set

After this plan, `perl` is no longer a dependency. It was used only by the toolkit parser and the link converter, and both are replaced. `jq` and `git` become needed only for `--infer-version`. The final dependency documentation reflects the code as it is after this plan, not the pre-plan list.

## Assumptions and decisions

- **LOW-RISK ASSUMPTION (user decision 6).** `--no-toc` stays the flag name. GNU getopt's unambiguous long-option prefix abbreviation stays as-is: `--single` means `--single-page`, and `--no` currently resolves to `--no-toc`. The plan documents the behavior in README and `--help` rather than disabling it, and adds tests that pin the documented behavior. Once 1.0 ships, abbreviations become de-facto API. Adding `--output` makes `--out` ambiguous, which is acceptable.
- **Answered user questions.** All three planning questions are answered, and each answer accepted the recommended default:
  - [Exit codes](./notes/exit-code-contract-answer.md): 0 success, 1 runtime, 2 usage, 3 dependency. Missing-dependency moves from 2 to 3, which `CHANGELOG.md` must call out.
  - [Short flags](./notes/short-flag-set-answer.md): `-D -F -h -o -p -s -t` only, with `-s` meaning `--to-stdout`. `--version` is long-only, and `-q`, `-l`, `-n`, and `-i` are removed.
  - [N4 and N8 scope](./notes/n4-n8-scope-answer.md): N4 and N8's feature parts are deferred as followup `1wy6`. Safety for non-ASCII and PostScript-special titles stays in scope.
- **Planner assumptions:**
  - Support bash 3.2 rather than require bash 4.
  - Replace `shelljs` with `node:child_process`, which supersedes the "bump shelljs 0.10" item.
  - Change the Node default title from `Report` to `output`.
  - Discover `*.md` and `*.markdown` case-insensitively.
  - Normalize org casing to lowercase `liquid-labs`.
  - Treat a single empty directory among non-empty ones as a warning, and only an overall zero-file result as exit 2.

  All are recorded with rationale in [design decisions](./notes/design-decisions.md).

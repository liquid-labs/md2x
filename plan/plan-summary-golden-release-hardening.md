# Plan Summary: golden-release-hardening

## What was planned and why

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

## What shipped

### Phase 01 — Correctness and Regression Tests

1. **Error Helper and Exit Codes** (`001-error-helper-and-exit-codes.md`, tier `sonnet-med`) — Added errors.sh with the 0/1/2/3 exit-code contract and migrated every md2x-owned exit path to it. Tool failures now exit 1 with a named-tool message, backstopped by an EXIT-trap normalization of statuses outside 0-3. The bats suite now asserts specific codes, and error-output.bats adds regression cases that fail on the pre-change binary.
   Commit `8903965`, merged at `9f6523e90b9bfac7c68bb406502b6fa06dbbb854`.

2. **Bash 3.2 Compatibility** (`002-bash-3-2-compatibility.md`, tier `sonnet-high`) — Fixed B4. Apostrophes in comments inside the file-discovery process substitution and the empty INCLUDE_BODY_ARGS array under nounset broke bash 3.2; both fixed. Silent exit 0 came from a 3.2 quirk where the EXIT trap sees $?=0 after a fatal nounset error; a completion sentinel fixes it on every bash. Added a POSIX-sh guard (exit 3), the MD2X_TEST_BASH harness override, and bash-compat.bats. Full suite passes under bash 5 and /bin/bash 3.2.57.
   Commit `1ff59af`, merged at `3210abe5a2e1eebd63a4e2f2c13ebe5b0a108349`.

3. **Project-Owned Option Parser** (`003-project-owned-option-parser.md`, tier `sonnet-high`) — Replaced the toolkit setSimpleOptions parser with project-owned src/cli/lib/parse-options.sh: explicit flag table, brew-free GNU getopt probe with MD2X_GETOPT override, help without getopt, friendly md2x usage errors with exit 2. -s now means --to-stdout; -q/-l/-n/-i rejected; brew dropped from test harness. 26 new regression cases pass under bash 5 and 3.2.
   Commit `4585085`, merged at `57b0e846b29e1025c2191c53415b377bf0ea4959`.

4. **Per-Run Work Directory** (`004-per-run-work-directory.md`, tier `sonnet-med`) — Every intermediate now lives in a per-run mktemp work directory removed by the EXIT trap (kept with --keep-intermediate). Fixes B1 single-page source deletion and keeps pandoc-log.log and other intermediates out of the cwd. generate-page no longer creates or removes files. 8 new regression cases; suite passes under bash 5 and 3.2.
   Commit `affc656`, merged at `db674932fea6eae6511b71b7581cf4d8c49b01c3`.

5. **Byte-Exact Stdin** (`005-byte-exact-stdin.md`, tier `sonnet-low`) — Stdin is now captured byte-exact to a work-dir file via cat instead of a shell variable, fixing indentation, backslash and trailing-newline corruption; empty stdin is now a usage error (exit 2) instead of a silent exit. Regression cases fail on the old build; suite passes under bash 5 and 3.2.
   Commit `10f9844`, merged at `fa777eeac4ea023c11c08ceb3af34ef05be7f85c`.

6. **Inline HTML CSS** (`006-inline-html-css.md`, tier `sonnet-med`) — HTML output now embeds github.css inline via --include-in-header and no longer references the work directory. PDF keeps --css and DOCX gets no --css. Pandoc stub captures the header file; 4 new stub cases plus an extended e2e case guard the change; new HTML tests fail on pre-change code.
   Commit `ffa2498`, merged at `65330f3e531e830b4b0b3334b44da63dc8b92c16`.

7. **Title-Safe Sinks** (`007-title-safe-sinks.md`, tier `sonnet-med`) — Added src/cli/lib/title-safe.sh and routed --title through three sinks: validated as a filename (exit 2), passed as one -M title= argument, and PostScript-escaped for the gs overlay. Updated pandoc stub and existing tests; added bats file and real-toolchain e2e cases. qa and bash 3.2 runs pass.
   Commit `22ba07d`, merged at `2aa7cfdda9ba4888423fda639cb7ad944ceed7e1`.

8. **Node Staging Path** (`008-node-staging-path.md`, tier `sonnet-low`) — Node markdown staging now uses fs.mkdtempSync(os.tmpdir()/md2x-) with a fixed input.md file name, so a title such as ../esc can no longer build a path outside the staging directory. Tests rewritten with regression tests for ../esc, O'Brien and Math.random; new tests fail on old code.
   Commit `19d4104`, merged at `ac43c656e9c1ebbab7e5a461040df6afccd80b74`.

### Phase 02 — Interface Contract

1. **Add Version Flag and Help Contract** (`001-add-version-flag-and-help-contract.md`, tier `sonnet-med`) — Added a long-only --version. A placeholder is substituted from package.json by the Makefile after rollup, and the build fails if the version cannot be read. Help now carries exit-code section, homepage, --version row, abbreviation and = note, and a formats description naming only pdf, html and docx. Eight new bats cases; validation passed under bash 5 and 3.2.
   Commit `cc62ba9`, merged at `5785104f830bb0604914b53bcdc950e2cb36d911`.

2. **Harden Input Discovery and Validation** (`002-harden-input-discovery-and-validation.md`, tier `sonnet-med`) — Input discovery builds one deduplicated, case-insensitive (*.md, *.markdown) resolved list feeding both the --title gate and conversion; adds usage error for no args, error for all-empty dirs, warning for a lone empty dir, '-' mixing error, case-insensitive -F validation, UTF-8/NUL rejection, and rejects control-character file names (x2X1). 25 new bats cases; validation passed under bash 5 and 3.2.
   Commit `99b3244`, merged at `784a074da7347b076f1713cfe6d3db12dd5d0f3b`.

3. **Add Output Option and Collision Checks** (`003-add-output-option-and-collision-checks.md`, tier `sonnet-high`) — Added -o/--output with extension-based format inference, a pure --to-stdout stream built in the work directory, -p slash normalization and non-directory rejection, and an up-front target plan with case-insensitive collision and input-overwrite checks (exit 2 before any conversion). Pandoc output is staged under a fixed work-directory name and copied to the planned target. 34 new bats cases; validation passed under bash 5 and 3.2.
   Commit `3eb5b2d`, merged at `75409f9d90b3be4ff5f443035551b5c60e93d9c3`.

4. **Resolve Links and Images With Lua Filter** (`004-resolve-links-and-images-with-lua-filter.md`, tier `sonnet-high`) — Replaced the eval/perl LINK_CONVERTER with an inlined pandoc Lua filter that rewrites .md/.markdown links and resolves images relative to each source file, with per-source markers in --single-page. Missing images produce one md2x warning each and exit 0. Real-pandoc bats file covers every spike case; new cases fail on pre-task code. One bats case (weasyprint persistent mkdir failure) timed out under 3.2 under host load, passes in isolation.
   Commit `bc423f4`, merged at `99c130be9087e5f94be9e8c6f6e019dc557e590b`.

5. **Clean Up Version Inference and Dependency Hygiene** (`005-clean-up-version-inference-and-dependency-hygiene.md`, tier `sonnet-med`) — Added lib/preflight.sh with pandoc >= 2.0 floor check, lazy unquoted --infer-version inference using the first input's repo, git/jq required only for --infer-version, and md2x-formatted errors instead of raw tool errors at audited leak sites. 19 new bats cases; validation passed under bash 5 and 3.2.
   Commit `6dd07a4`, merged at `ea60e174a2a695da562e55ae27d61ceb7ce5b82e`.

6. **Prune WeasyPrint Unsupported CSS** (`006-prune-weasyprint-unsupported-css.md`, tier `sonnet-med`) — Pruned WeasyPrint-unsupported CSS from github.css (fill, word-wrap break-all, max-width auto, overflow-x/y, unprefixed user-select, spin-button rule, kbd box-shadow); PDFs rasterize byte-identical. One pandoc-template-owned 'user-select: none' WARNING remains and is exempted in the new e2e regression test.
   Commit `a11e4c4`, merged at `1705a759121f908e3e02895d002385d5651f3959`.

7. **Rewrite Node Wrapper on Child Process** (`007-rewrite-node-wrapper-on-child-process.md`, tier `sonnet-med`) — Rewrote the Node wrapper on node:child_process with argv arrays: markdown goes on stdin as '-', no staging file or shelljs, options validated before spawning. Added md2xAsync, output (-o) and quiet, and errors carrying exitCode and stderr. Removed the shelljs dependency and rewrote tests with 100% coverage.
   Commit `9b14495`, merged at `74623d6ce924b60de02f53fc3a64b3fb18caf4ea`.

8. **Package Node Library for ESM, CJS, and Types** (`008-package-node-library-for-esm-cjs-and-types.md`, tier `sonnet-med`) — Replaced the single CJS bundle with ESM and CJS bundles plus hand-written types and an exports map. The packed tarball passes native ESM named import, CJS require and a strict tsc check via make test-pack (scripts/test-pack.sh).
   Commit `2514e6a`, merged at `beb32a26520d3f80cbe878bc7f090cb0a0ee4a1f`.

### Phase 03 — Docs, CI, and Release Readiness

1. **Add GitHub Actions CI Workflow** (`001-github-actions-ci.md`, tier `sonnet-med`) — Added .github/workflows/ci.yml with an ubuntu/macOS matrix running make qa, a macOS bash 3.2 test run, and a legacy-pandoc job to validate the pandoc 2.0 floor. actionlint and YAML parse pass; the workflow itself is unproven until pushed.
   Commit `d7d3def`, merged at `c4b5cf15be64d0ea2a47f4788a27865bda1e085b`.

2. **Add Changelog, Contributing, and Security Docs** (`002-community-docs.md`, tier `sonnet-med`) — Created CHANGELOG.md (Keep a Changelog Unreleased 1.0.0 with breaking changes, Added, Changed, Fixed, Removed), CONTRIBUTING.md (setup, make targets, bash 3.2 override, regression-test rule) and SECURITY.md (private reporting, untrusted-Markdown caveats). No code touched.
   Commit `41a5203`, merged at `3f581c9f7730111420da2f483d18bd973ee89c03`.

3. **Optimize TOC Slug Probe** (`003-psgq-slug-probe-optimization.md`, tier `sonnet-med`) — Replaced the restart-from-1 slug probe with a per-base resume index. Output is byte-identical on every corpus checked (cmp), real-pandoc e2e parity cases pass, and the 2000-duplicate case dropped from 0.17s to 0.02s.
   Commit `5188d51`, merged at `7a23add893a9ba6bb9cdfdc0f9befff84c84e28a50`.

4. **Fix Lint Scope and Bump Dev Dependencies** (`004-lint-and-dependency-bumps.md`, tier `sonnet-med`) — Fixed the 20 key-spacing errors in eslint.config.mjs, widened make lint and lint-fix to the whole repo, and widened the ignores. ESLint 10 is blocked by the neostandard peer range, so the dependencies are unchanged. qa, test-pack and the bash 3.2 suite pass.
   Commit `baa2400`, merged at `3ce00333bf601851df0a4b78a755b43076452448`.

5. **Correct Package Metadata and Verify Pack Contents** (`005-package-metadata-and-pack-verification.md`, tier `sonnet-med`) — Corrected package.json metadata (description, keywords, engines >=20, lowercase org with git+https URLs, prepack make all, CHANGELOG.md in files). Confirmed bun runs prepack and rebuilds bin/md2x. The 8-file tarball verified; qa and test-pack pass on Node 20 and 26.
   Commit `e43e43e`, merged at `ef9b92c5646b1de63b70a50ce92e2c0e27c5568a`.

6. **Fix Release Procedure and Rehearse Dry Run** (`006-release-procedure-and-dry-run.md`, tier `sonnet-high`) — Rewrote RELEASING.md as a numbered procedure with accurate publish verification status and dry-run guidance, and fixed scripts/release.sh dist-tag logic, dry-run credential handling and pack check. Script dry runs for 1.0.0-rc.1 and 1.0.0 pass; nothing was published.
   Commit `40b2ad4`, merged at `171af748cd52efd4a927ff0237bed571586d5491`.

7. **Overhaul README** (`007-readme-overhaul.md`, tier `sonnet-high`) — Rewrote README.md for 1.0 with every claim and example run against the built CLI and a packed-tarball Node install; machine-parseable 17-row flag table, exit-code and troubleshooting tables, Node API, dependency/platform/security/limitation notes. make qa passes.
   Commit `b8f9d11`, merged at `3d401e46d23cc310348fb2885973637be204a3a5`.

8. **Update Spec, AGENTS.md, and Project Structure Docs** (`008-spec-agents-and-structure-docs.md`, tier `sonnet-high`) — Brought the spec, AGENTS.md, and project-structure.md to the final behavior: spec links the README flag table and keeps normative content (exit codes, dependency set, trust notes), AGENTS.md no longer lists perl and has current layout/commands/constraints, project-structure lists every src file. make qa passes.
   Commit `8816aab`, merged at `7e367ed959a7a966f47f62dff3c6573b6005f162`.

9. **Add Flag Table Drift Test** (`009-flag-table-drift-test.md`, tier `sonnet-high`) — Added a bats drift test and helper comparing (short, long) flag pairs across the parser table, md2x --help and the README CLI table, plus a spec link/no-table check. Drift detection demonstrated on temp copies; make qa and the bash 3.2 suite pass (369 tests).
   Commit `cf527cb`, merged at `fd1a2807e1334864eabd6f51f4f0554aa1caf539`.

### Phase 04 — Documentation Updates

1. **Update Architecture Docs** (`001-update-architecture-docs.md`, tier `sonnet-high`) — Brought docs/architecture.md into conformance with the final code (exit-code contract, new components, Node wrapper process model and dual build, stylesheet and stderr handling, version inference trust model, dependency set, CI) with 18 added Key decisions; reviewed the spec and left it unchanged apart from one pointer bullet. make qa and the drift test pass.
   Commit `f5b76b6`, merged at `2cb7f32ece89278ff89c393328850f5404c2a8c1`.

### Phase 05 — Remediation Round 1

1. **Resolve The CLI Relative To The Installed Bundle And Harden The Pack Test** (`001-fix-node-bundle-bin-resolution.md`, tier `sonnet-high`) — Fixed bin resolution in both bundles using import.meta.dirname plus a CJS-only Makefile --define to module.path, so no build path or __dirname reaches dist/. test-pack now proves the installed bin is the one used (stub check, build-path grep) and the typescript check uses a lockfile-pinned devDependency instead of npx. Reintroducing bare __dirname makes test-pack fail.
   Commit `3145e42`, merged at `7ce6d7e3ffde8ba3f0bb1920dc6bacd5b28fd4fc`.

2. **Pass Sources After End-Of-Options And Correct Node Type Docs** (`002-node-end-of-options-and-type-docs.md`, tier `sonnet-med`) — Sources now go after '--' so '-weird.md' is treated as a file, while '-' (stdin) still works. index.d.ts JSDoc for inferTitle, inferVersion and singlePage matches CLI help. Tests updated plus two new -weird.md tests; make qa and make test-pack pass.
   Commit `9df95a1`, merged at `02d0158b108998b8717348b9f765bc832b30bcc9`.

3. **Reject Trailing-Slash Output Paths And Protect Dash-Leading Search Roots** (`003-reject-trailing-slash-output-and-dash-roots.md`, tier `sonnet-med`) — Rejected -o <dir>/ at plan time with a usage error (exit 2), and made find treat dash-leading roots as paths via a ./ prefix stripped from results. Two regression bats cases fail on old code; make qa and the bash 3.2 suite pass.
   Commit `928a0f4`, merged at `357d27cdd1b316fe66c77e7f9a767a25965acd58`.

4. **Filter Pandoc Template User-Select Warning From PDF Stderr** (`004-filter-pandoc-user-select-warning.md`, tier `sonnet-med`) — Pandoc stderr is captured and replayed with exactly the one user-select warning line dropped (exact whole-line match). Exemption removed from the PDF e2e case, plus a failure-passthrough test. qa and the bash 3.2 CLI suite are green.
   Commit `64b8280`, merged at `ca5492dabe980635ae96a9f24fadadd798ee4eba`.

5. **Make The Single-Page Source Marker Unforgeable** (`005-unforgeable-single-page-source-marker.md`, tier `sonnet-high`) — Added a per-run /dev/urandom nonce that single-page source markers must carry for the Lua filter to honor them, so forged markers in a source are inert. Switched the Lua heredoc terminator to MD2X_LUA_EOF and added three bats regression cases. qa and the bash 3.2 suite pass.
   Commit `d349562`, merged at `d21be7b8943fd6636b450d6445d3967d37f1c63d`.

6. **Neutralize Repository Git Config In Version Inference** (`006-harden-infer-version-git-calls.md`, tier `sonnet-med`) — Both git calls in version inference now go through a hardened wrapper, and a sentinel regression test (verified failing on the old build) proves a repo-local core.fsmonitor command no longer executes.
   Commit `adc898d`, merged at `e17d3dfa9cebea21691d1d3ad60c2748669a4656`.

7. **Re-Check Input Identity And Deliver Output Without Following Symlinks** (`007-inode-safe-output-delivery.md`, tier `sonnet-med`) — Delivery stages a copy beside the target, re-checks it against every input with -ef, and renames it into place, so symlinks and hard links at the output path are never written through. Two of three new bats cases fail on old code; qa and bash 3.2 suite pass.
   Commit `c5acb94`, merged at `fcd107359d1bb22c0ef8cfbd0377df1edd8fbfd3`.

### Phase 06 — Remediation Round 2

1. **Refuse Command-Bearing Repository Config Before Git Status In Version Inference** (`001-refuse-command-bearing-repo-config-in-infer-version.md`, tier `sonnet-high`) — md2x-infer-version now refuses repositories whose local (and per-worktree) git config has command-bearing keys. It warns once, omits the version, and never runs git status; it also fails closed on unreadable config. The filter-sentinel test was shown to fail on the pre-change build and passes now.
   Commit `3fda89b`, merged at `72565167afaaf7200d5104a82990162ce9a445e5`.

2. **Harden Output Delivery Edge Cases And Find Root Handling** (`002-harden-output-delivery-and-find-roots.md`, tier `sonnet-med`) — Hardened delivery against directory and symlink-to-directory targets, a dash-leading relative output directory and a leftover temp file, and made find roots literal by prefixing every relative root with ./. Four bats cases (three fail on pre-change build) plus spec text. Symlink-to-dir case is a guard only.
   Commit `82fb9b5`, merged at `38cfbf66a7fa146970170ee6e60e6bd9393e482d`.

3. **Always Pass The Marker Nonce And Make Test-Pack Checks Fail Closed** (`003-always-pass-filter-nonce-and-harden-test-pack.md`, tier `sonnet-med`) — The marker nonce and all md2x-* filter settings are now always passed with -M in every mode, so a source's front matter cannot supply or change them. test-pack now fails closed on missing bundles, grep errors and missing pinned tsc, and checks both logical and physical root paths. New regression case fails on pre-change code; qa, test-pack and bash 3.2 suite pass.
   Commit `9732bbb`, merged at `80736059a93a9d42438bc3cbb72f224047cfd992`.

### Phase 07 — Remediation Round 3

1. **Allowlist Repository Config And Harden Git Status In Version Inference** (`001-allowlist-repo-config-for-infer-version.md`, tier `sonnet-high`) — Replaced the config denylist with an allowlist, hardened the git status call (no submodule recursion, no lazy fetch, protocol.allow=never, no global config), and removed the pipefail fail-open. Nine new bats cases; the four execution cases and the refusal cases fail on the pre-change build. Implementer tried to defeat the fix in a scratch dir without success.
   Commit `ea985d1`, merged at `84653af61d47923189aac628fb38d23faf3fa152`.

## Key decisions

_No `## Why this shape` section is recorded in `plan/overview.md`, so this plan's cross-task rationale was never written down. Per-task outcomes are under "What shipped" above._

## Findings

- **`d7Tf`** — **Docs still say missing dep exits 2** — dismissed — 2026-10-05 — reason: Already planned: README exit-code table in Phase 3 task 007; spec exit-code validation in Phase 3 task 008 and Phase 4 task 001; architecture parser/work-dir/stdin/CSS/title wording in Phase 4 task 001.

- **`x2X1`** — **Escape discovered filenames in messages** — promoted — ref: `x2X1` — 2026-10-05

- **`ttPU`** — **Harden getopt eval and cap title length** — promoted — ref: `ttPU` — 2026-10-05

- **`32b8`** — **Drop bash-toolkit lists, harden heredoc** — promoted — ref: `32b8` — 2026-10-05

- **`S0YR`** — **Validate pandoc floor and RELEASING artifacts** — promoted — ref: `S0YR` — 2026-10-05

- **`nPPK`** — **Image paths may escape source tree** — promoted — ref: `nPPK` — 2026-10-05

- **`yV1b`** — **Directory arg starting with - read by find** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.3: dash-leading roots passed to find as ./root (md2x.sh:314-319), test input-discovery.bats:270; remaining find-token roots tracked by wgQ3.

- **`KhXI`** — **Filter pandoc template user-select warning** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.4: exact-line grep -vxF filter in generate-page.sh; e2e exemption removed (real-toolchain-e2e.bats).

- **`Xylz`** — **Dash-leading sources parsed as CLI flags** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.2: src/node/md2x.js places '--' before sources; tests md2x.test.js cover -weird.md sync and async.

- **`8xEp`** — **Node bundles hardcode build-time __dirname** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.1: import.meta.dirname plus CJS --define in Makefile; test-pack stub check proves installed bin resolution; build-path grep hardening tracked by xDG1.

- **`3rV7`** — **-o with trailing slash fails after convert** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.3: trailing-slash -o rejected with exit 2 at plan time (md2x.sh:207-211), test output-options.bats:391.

- **`YkUH`** — **index.d.ts JSDoc misdescribes options** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.2: index.d.ts JSDoc for inferTitle, inferVersion and singlePage now matches the CLI.

- **`tT72`** — **test-pack fetches unpinned typescript** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.1: test-pack uses lockfile-pinned node_modules/.bin/tsc, no npx; silent fallback tracked by xDG1.

- **`z2v9`** — **Single-page source marker is forgeable** — dismissed — 2026-10-05 — reason: Fixed by remediation task 5.5 for --single-page: per-run nonce required by the filter (md2x-links.lua:171-174), tests links-and-images.bats:234-250; multi-file front-matter gap tracked by xDG1.

- **`SmNy`** — **infer-version git may run repo config** — dismissed — 2026-10-05 — reason: Duplicate of r4Pu: remediation task 5.6 fixed fsmonitor/hooksPath; the remaining clean-filter execution via git status is fully described by r4Pu.

- **`wgQ3`** — **Output delivery edge cases and find roots** — dismissed — 2026-10-05 — reason: Fixed by remediation task 6.2 (delivery refuses -d targets, ./ mktemp prefix, EXIT-trap temp cleanup, ./-prefixed find roots); round 2 security and combined reviews both found delivery and find roots sound.

- **`m1SB`** — **Output overwrite check is advisory only** — dismissed — 2026-10-05 — reason: Fixed by remediation tasks 5.7 and 6.2: inode re-check and temp+mv delivery; symlinked *.md following and parent-dir trust assumption documented in docs/md2x-spec.md; round 2 reviews found delivery sound.

- **`xDG1`** — **Always pass nonce; harden test-pack checks** — dismissed — 2026-10-05 — reason: Fixed by remediation task 6.3: nonce and all md2x-* filter settings always passed via -M (pandoc -M overrides front matter, verified by implementer and reviewers); test-pack fails closed. Round 2 reviews confirmed.

- **`r4Pu`** — **infer-version git status runs clean filters** — dismissed — 2026-10-05 — reason: Superseded: remediation task 6.1 fixed the reproduced clean-filter case, but the denylist was shown bypassable; the complete fix is tracked by U0Pj (allowlist) and Qbv2 (pipefail fail-open).

- **`JEAt`** — **infer-version status may recurse submodules** — dismissed — 2026-10-05 — reason: Duplicate: the reachable submodule git status case is covered by U0Pj (allowlist plus --ignore-submodules=all).

- **`U0Pj`** — **Config denylist bypassed; use allowlist** — dismissed — 2026-10-06 — reason: Fixed by remediation task 7.1: config allowlist, --ignore-submodules=all, no lazy fetch, protocol.allow=never; round 3 full security review re-verified the partial-clone, ext:: and submodule cases closed and found no execution path.

- **`Qbv2`** — **Pipefail SIGPIPE fails open in config refusal** — dismissed — 2026-10-06 — reason: Fixed by remediation task 7.1: the printf|grep -q pipeline is replaced by here-strings and a case match with a single tr lowercase; a >64KB padded-config test refuses; round 3 review reproduced the closed case.

- **`HdEH`** — **Infer-version hardening trade-offs and spoof** — promoted — ref: `HdEH` — 2026-10-06

- **`FUld`** — **Release dry-run and doc wording polish** — promoted — ref: `FUld` — 2026-10-06

- **`5E3C`** — **Architecture doc small inaccuracies** — promoted — ref: `5E3C` — 2026-10-06

## Remediation

- Rounds used: 3 (resolved max_rounds: 3).
- Remediation tasks added: 11 (resolved max_added_tasks: 14).
- Remediation phases:
  - `remediation-01` — 7 task(s)
  - `remediation-02` — 3 task(s)
  - `remediation-03` — 1 task(s)
- Security review required: yes (at least one remediation phase carries `security_review: required`).

## Final Task State

# TODO

## Purpose and scope

Tracking document for the active plan.

## Tasks

### Phase 01 — Correctness and Regression Tests

- [x] [001-error-helper-and-exit-codes.md](./phase-01-correctness-and-regression-tests/001-error-helper-and-exit-codes.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-01-001` · commit `8903965` · merge `9f6523e90b9bfac7c68bb406502b6fa06dbbb854`
- [x] [002-bash-3-2-compatibility.md](./phase-01-correctness-and-regression-tests/002-bash-3-2-compatibility.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-01-002` · commit `1ff59af` · merge `3210abe5a2e1eebd63a4e2f2c13ebe5b0a108349`
- [x] [003-project-owned-option-parser.md](./phase-01-correctness-and-regression-tests/003-project-owned-option-parser.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-01-003` · commit `4585085` · merge `57b0e846b29e1025c2191c53415b377bf0ea4959`
- [x] [004-per-run-work-directory.md](./phase-01-correctness-and-regression-tests/004-per-run-work-directory.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-01-004` · commit `affc656` · merge `db674932fea6eae6511b71b7581cf4d8c49b01c3`
- [x] [005-byte-exact-stdin.md](./phase-01-correctness-and-regression-tests/005-byte-exact-stdin.md) — tier `sonnet-low` · branch `plan/golden-release-hardening-01-005` · commit `10f9844` · merge `fa777eeac4ea023c11c08ceb3af34ef05be7f85c`
- [x] [006-inline-html-css.md](./phase-01-correctness-and-regression-tests/006-inline-html-css.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-01-006` · commit `ffa2498` · merge `65330f3e531e830b4b0b3334b44da63dc8b92c16`
- [x] [007-title-safe-sinks.md](./phase-01-correctness-and-regression-tests/007-title-safe-sinks.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-01-007` · commit `22ba07d` · merge `2aa7cfdda9ba4888423fda639cb7ad944ceed7e1`
- [x] [008-node-staging-path.md](./phase-01-correctness-and-regression-tests/008-node-staging-path.md) — tier `sonnet-low` · branch `plan/golden-release-hardening-01-008` · commit `19d4104` · merge `ac43c656e9c1ebbab7e5a461040df6afccd80b74`

### Phase 02 — Interface Contract

- [x] [001-add-version-flag-and-help-contract.md](./phase-02-interface-contract/001-add-version-flag-and-help-contract.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-02-001` · commit `cc62ba9` · merge `5785104f830bb0604914b53bcdc950e2cb36d911`
- [x] [002-harden-input-discovery-and-validation.md](./phase-02-interface-contract/002-harden-input-discovery-and-validation.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-02-002` · commit `99b3244` · merge `784a074da7347b076f1713cfe6d3db12dd5d0f3b`
- [x] [003-add-output-option-and-collision-checks.md](./phase-02-interface-contract/003-add-output-option-and-collision-checks.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-02-003` · commit `3eb5b2d` · merge `75409f9d90b3be4ff5f443035551b5c60e93d9c3`
- [x] [004-resolve-links-and-images-with-lua-filter.md](./phase-02-interface-contract/004-resolve-links-and-images-with-lua-filter.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-02-004` · commit `bc423f4` · merge `99c130be9087e5f94be9e8c6f6e019dc557e590b`
- [x] [005-clean-up-version-inference-and-dependency-hygiene.md](./phase-02-interface-contract/005-clean-up-version-inference-and-dependency-hygiene.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-02-005` · commit `6dd07a4` · merge `ea60e174a2a695da562e55ae27d61ceb7ce5b82e`
- [x] [006-prune-weasyprint-unsupported-css.md](./phase-02-interface-contract/006-prune-weasyprint-unsupported-css.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-02-006` · commit `a11e4c4` · merge `1705a759121f908e3e02895d002385d5651f3959`
- [x] [007-rewrite-node-wrapper-on-child-process.md](./phase-02-interface-contract/007-rewrite-node-wrapper-on-child-process.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-02-007` · commit `9b14495` · merge `74623d6ce924b60de02f53fc3a64b3fb18caf4ea`
- [x] [008-package-node-library-for-esm-cjs-and-types.md](./phase-02-interface-contract/008-package-node-library-for-esm-cjs-and-types.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-02-008` · commit `2514e6a` · merge `beb32a26520d3f80cbe878bc7f090cb0a0ee4a1f`

### Phase 03 — Docs, CI, and Release Readiness

- [x] [001-github-actions-ci.md](./phase-03-docs-ci-and-release-readiness/001-github-actions-ci.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-03-001` · commit `d7d3def` · merge `c4b5cf15be64d0ea2a47f4788a27865bda1e085b`
- [x] [002-community-docs.md](./phase-03-docs-ci-and-release-readiness/002-community-docs.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-03-002` · commit `41a5203` · merge `3f581c9f7730111420da2f483d18bd973ee89c03`
- [x] [003-psgq-slug-probe-optimization.md](./phase-03-docs-ci-and-release-readiness/003-psgq-slug-probe-optimization.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-03-003` · commit `5188d51` · merge `7a23add893a9ba6bb9cdfdc0f9befff84c84e28a50`
- [x] [004-lint-and-dependency-bumps.md](./phase-03-docs-ci-and-release-readiness/004-lint-and-dependency-bumps.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-03-004` · commit `baa2400` · merge `3ce00333bf601851df0a4b78a755b43076452448`
- [x] [005-package-metadata-and-pack-verification.md](./phase-03-docs-ci-and-release-readiness/005-package-metadata-and-pack-verification.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-03-005` · commit `e43e43e` · merge `ef9b92c5646b1de63b70a50ce92e2c0e27c5568a`
- [x] [006-release-procedure-and-dry-run.md](./phase-03-docs-ci-and-release-readiness/006-release-procedure-and-dry-run.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-03-006` · commit `40b2ad4` · merge `171af748cd52efd4a927ff0237bed571586d5491`
- [x] [007-readme-overhaul.md](./phase-03-docs-ci-and-release-readiness/007-readme-overhaul.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-03-007` · commit `b8f9d11` · merge `3d401e46d23cc310348fb2885973637be204a3a5`
- [x] [008-spec-agents-and-structure-docs.md](./phase-03-docs-ci-and-release-readiness/008-spec-agents-and-structure-docs.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-03-008` · commit `8816aab` · merge `7e367ed959a7a966f47f62dff3c6573b6005f162`
- [x] [009-flag-table-drift-test.md](./phase-03-docs-ci-and-release-readiness/009-flag-table-drift-test.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-03-009` · commit `cf527cb` · merge `fd1a2807e1334864eabd6f51f4f0554aa1caf539`

### Phase 04 — Documentation Updates

- [x] [001-update-architecture-docs.md](./phase-04-doc-updates/001-update-architecture-docs.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-04-001` · commit `f5b76b6` · merge `2cb7f32ece89278ff89c393328850f5404c2a8c1`

### Phase 05 — Remediation Round 1

- [x] [001-fix-node-bundle-bin-resolution.md](./phase-05-remediation-01/001-fix-node-bundle-bin-resolution.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-05-001` · commit `3145e42` · merge `7ce6d7e3ffde8ba3f0bb1920dc6bacd5b28fd4fc`
- [x] [002-node-end-of-options-and-type-docs.md](./phase-05-remediation-01/002-node-end-of-options-and-type-docs.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-05-002` · commit `9df95a1` · merge `02d0158b108998b8717348b9f765bc832b30bcc9`
- [x] [003-reject-trailing-slash-output-and-dash-roots.md](./phase-05-remediation-01/003-reject-trailing-slash-output-and-dash-roots.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-05-003` · commit `928a0f4` · merge `357d27cdd1b316fe66c77e7f9a767a25965acd58`
- [x] [004-filter-pandoc-user-select-warning.md](./phase-05-remediation-01/004-filter-pandoc-user-select-warning.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-05-004` · commit `64b8280` · merge `ca5492dabe980635ae96a9f24fadadd798ee4eba`
- [x] [005-unforgeable-single-page-source-marker.md](./phase-05-remediation-01/005-unforgeable-single-page-source-marker.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-05-005` · commit `d349562` · merge `d21be7b8943fd6636b450d6445d3967d37f1c63d`
- [x] [006-harden-infer-version-git-calls.md](./phase-05-remediation-01/006-harden-infer-version-git-calls.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-05-006` · commit `adc898d` · merge `e17d3dfa9cebea21691d1d3ad60c2748669a4656`
- [x] [007-inode-safe-output-delivery.md](./phase-05-remediation-01/007-inode-safe-output-delivery.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-05-007` · commit `c5acb94` · merge `fcd107359d1bb22c0ef8cfbd0377df1edd8fbfd3`

### Phase 06 — Remediation Round 2

- [x] [001-refuse-command-bearing-repo-config-in-infer-version.md](./phase-06-remediation-02/001-refuse-command-bearing-repo-config-in-infer-version.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-06-001` · commit `3fda89b` · merge `72565167afaaf7200d5104a82990162ce9a445e5`
- [x] [002-harden-output-delivery-and-find-roots.md](./phase-06-remediation-02/002-harden-output-delivery-and-find-roots.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-06-002` · commit `82fb9b5` · merge `38cfbf66a7fa146970170ee6e60e6bd9393e482d`
- [x] [003-always-pass-filter-nonce-and-harden-test-pack.md](./phase-06-remediation-02/003-always-pass-filter-nonce-and-harden-test-pack.md) — tier `sonnet-med` · branch `plan/golden-release-hardening-06-003` · commit `9732bbb` · merge `80736059a93a9d42438bc3cbb72f224047cfd992`

### Phase 07 — Remediation Round 3

- [x] [001-allowlist-repo-config-for-infer-version.md](./phase-07-remediation-03/001-allowlist-repo-config-for-infer-version.md) — tier `sonnet-high` · branch `plan/golden-release-hardening-07-001` · commit `ea985d1` · merge `84653af61d47923189aac628fb38d23faf3fa152`

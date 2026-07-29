# Plan Summary: test-coverage-bugfix

## What was planned and why

This plan did two things at once, deliberately sequenced together rather than decoupled:

1. **Fixed followup `aI57`** — a hardcoded `/policy/` path strip in the non-`--flatten-dirs`
   (mirrored-output) branch of `src/cli/md2x.sh`. That strip silently no-op'd for any input path
   without a `/policy/` segment, placing output under a mirror of the input's *full* path instead
   of its path relative to the search root it was actually found under.
2. **Replaced md2x's manual, interactive test artifact with an automated, non-interactive suite**
   covering both of md2x's external surfaces — the bash CLI and the Node library wrapper — wired
   into `make test` / `npm test` so it runs deterministically with no human at the keyboard.

The `aI57` fix was required to land with direct regression coverage (cases red before the fix,
green after), which is why the bugfix task lived inside the same phase as the new test harness
rather than as a standalone patch. Constraints carried through the whole plan: no changes to
md2x's flag surface, no changes to the Node wrapper's public signature or pass-through
architecture, no changes to the `bin/md2x` / `dist/md2x.js` build pipeline, and no new external
runtime dependency beyond the three already declared (`pandoc`, `gs`, `pdftk`). Success meant
`make test` running to completion non-interactively and deterministically, passing even on a
machine (the maintainer's own) where real PDF conversion cannot succeed because Pandoc's
`weasyprint` engine is absent.

## What shipped

### Phase 01 — Automated Test Coverage

- **001 — Stand Up Test Infrastructure** (merge `efe11d4d`). Stood up the full harness: a
  bats-core CLI suite under `src/cli/test/{bats,helpers,stubs}`, hermetic-PATH stub
  `pandoc`/`gs`/`pdftk` executables, Jest wired in via `catalyst-scripts` with a trivial passing
  `src/node/md2x.test.js`, `make test`/`test-cli`/`test-node`/`smoke-test` wiring, and the old
  interactive `test.sh` relocated to `manual/visual-smoke-test.sh`. `AGENTS.md` and
  `docs/project-structure.md` updated to match. This task was the hard prerequisite for all of
  002–005 and owned all shared build wiring so the rest only needed to add test files.

- **002 — Fix Mirrored Output Path Derivation** (merge `d981bef2`). Replaced the hardcoded
  `/policy/` strip with a general search-root-relative derivation, resolving `aI57`. File
  discovery now emits tab-separated `<md-file><tab><search-root>` records; new
  normalize-path/relative-output-dir helpers compute and normalize the output subdirectory.
  `mkdir -p` was moved out of the mirroring-only branch so `--flatten-dirs` also creates a missing
  `--output-path`. Eleven regression cases landed red-before/green-after in
  `src/cli/test/bats/mirrored-output-paths.bats`. The `AGENTS.md` "Known issues" bullet pointing
  at `aI57` was removed; `README.md` and `docs/md2x-spec.md` gained precision clauses describing
  the corrected contract.

- **003 — Cover CLI Option Behavior** (merge `e5146bf7`). Added 27 bats cases across 5 new files
  covering `--output-format` validation, `--single-page` concatenation, stdin `-`,
  `--infer-title`, `--infer-version`, `--no-toc`, `--quiet`, `--list-files`, `--to-stdout`,
  `--help`, `--keep-intermediate`, and the exit codes for a missing binary and a bad input path.
  All cases deliberately use output-path shapes that are invariant under task 002's mirrored-path
  fix, keeping the two tasks mergeable in parallel. `make test`/`lint`/`qa` all passed.

- **004 — Cover Node Wrapper** (merge `e0009407`). Filled in `src/node/md2x.test.js` with 17 Jest
  cases covering argument marshaling, the returned file list, non-zero-exit error propagation,
  non-fatal stderr forwarding, and the markdown-string staging path plus its cleanup. `shelljs` is
  fully mocked, so no case shells out. Followups `udVi` (unreachable default-title branch) and
  `egcc` (markdown-staging producing a literal `undefined.md`) were confirmed still present, each
  with a dedicated regression-style test documenting the current behavior rather than a fix —
  production code was not touched. Coverage on `md2x.js`: 97.43% statements / 94.73% branches /
  100% functions.

- **005 — Add Gated End To End Tests** (merge `c04448fe`). Added
  `src/cli/test/bats/real-toolchain-e2e.bats`, a 4-case suite against the real
  `pandoc`/`gs`/`pdftk` toolchain. HTML, DOCX, and single-page cases ran for real and passed; the
  PDF case gates on a throwaway probe conversion and skips cleanly citing the missing
  `weasyprint` engine (followup `BfN6`). The inverse was also confirmed: with `pandoc` absent
  entirely, all four cases skip cleanly and exit 0. No files outside the new test file were
  touched.

### Phase 02 — Documentation Updates

- **001 — Update Architecture Docs** (merge `6099c9b2`). Updated `docs/architecture.md` (CLI
  entry-point section now notes search-root-carrying file discovery; "Key decisions" gained a
  bullet on the test stub boundary) and `docs/project-structure.md` (Makefile row now lists the
  `test-cli`/`test-node`/`smoke-test` targets). Verified `docs/md2x-spec.md`, `README.md`, and
  `AGENTS.md` were already correctly updated by Phase 01 tasks 001/002, so no further edit was
  needed there. `make qa` passed; no stale `/policy/`, `aI57`, or `test.sh` references remain
  outside the relocated smoke-test path.

## Key decisions

- **Stub the external-tool boundary.** The bulk of the suite runs the CLI against stub
  `pandoc`/`gs`/`pdftk` executables on a test-controlled `PATH` that record their argument
  vectors and fabricate the files their real counterparts would produce, rather than shelling out
  for real. Rationale: md2x's own logic is argument construction, source-list resolution, and
  output-path derivation — it orchestrates three subprocesses and renders nothing itself.
  Stubbing tests md2x rather than Pandoc, keeps the suite fast and reproducible, and is the only
  way to exercise the spec's `exit 2` missing-binary contract at all (it requires controlling
  `PATH`). It is also a hard requirement for the suite to be green anywhere, since real PDF
  conversion does not work on the maintainer's own machine. The accepted trade-off — that the
  stub suite cannot catch a Pandoc-side regression or a flag that is malformed but still accepted
  — is exactly what the separately-gated end-to-end suite (task 005) covers instead.
- **Hermetic `PATH` design.** Stub executables are placed on a test-controlled `PATH` rather than
  patched into the real toolchain location, so tests never depend on (or corrupt) the host
  machine's actual `pandoc`/`gs`/`pdftk` installs and can also assert the missing-binary exit
  path deterministically.
- **Tab-separated search-root record format.** The `aI57` fix's file-discovery step emits
  `<md-file><tab><search-root>` records rather than bare paths, so the mirrored-output derivation
  can compute a path relative to whichever search root (CLI directory argument, or the named
  file's own directory) actually produced the match — replacing the old hardcoded `/policy/`
  strip with a general, root-relative rule.
- **`mkdir -p` moved out of the mirroring-only branch.** As a direct consequence of the `aI57`
  fix, `--flatten-dirs` now also creates a missing `--output-path`, closing a related gap noted
  during the same task (see followup `MPHT` below for the two flag paths still not covered).
- **Task 002 owns all mirrored-output assertions; 003/004/005 add only new test files.** This
  let 002–005 run in parallel against disjoint files, with 003/004/005 required to use
  output-path shapes invariant under 002's in-flight fix.
- **Documented-but-unfixed known bugs.** Followups `udVi` and `egcc` were deliberately left
  unfixed and instead given explicit regression tests documenting current (buggy) behavior,
  keeping the bugfix scope of this plan limited to `aI57` alone.

## Follow-up items

From `plan/followups.yaml` (carried forward, not resolved by this plan):

- **`arUf` — md2x.js shell injection risk.** `src/node/md2x.js` builds shell commands by naively
  single-quoting caller-supplied `title`/`outputPath`/`sources` values with no escaping, then
  executes via `shell.exec(..., { shell: '/bin/bash' })`; a value containing a single quote can
  break out of quoting and run arbitrary shell commands. Pre-existing, not introduced by this
  plan, but task 004's new test now asserts the unescaped command string as expected behavior
  without the "documents current buggy behavior" caveat used for `udVi`/`egcc`.
- **`8ZmD` — md2x.sh find-pipe abort shift.** The `aI57` fix nests a per-root inner pipe inside
  the existing outer `for`-loop `| sort` pipe; under `pipefail`/`errexit` a `find` failure on one
  search root now surfaces after that root's already-discovered files drain through the inner
  loop, rather than aborting immediately as before. Net abort-or-not behavior is likely
  unchanged; abort *timing* has shifted. Low confidence, minor severity.
- **`r38C` — md2x.sh discovery pipe overhead.** The tab-separated record change adds one extra
  piped while/read/printf subshell per search-root iteration versus the prior direct
  `find | sort`. Still O(n) in matched files; a small constant-factor cost worth revisiting only
  if profiling on real trees shows it matters.
- **`EWuE` — e2e suite always runs in `make test`.** Task 005's four real-toolchain cases run in
  the default `make test`/`test-cli` path by design, adding real conversion time
  (~12.4s → ~13.9–17.5s measured) on any machine with a working `pandoc`. Deliberate trade-off;
  optional enhancement would be an `MD2X_SKIP_E2E=1` escape hatch for local iteration.
- **`MPHT` — `--single-page` and stdin still don't create `--output-path`.** Same class of bug as
  the `--flatten-dirs` fix (one-line `mkdir -p`), explicitly left out of task 002's scope.
- **`rm3a` — `--flatten-dirs` help text stale.** `src/cli/md2x.sh`'s help text wasn't updated to
  match the more precise `README.md`/spec wording landed by task 002. Trivial.
- **`c2s9` — `--output-format html` naming quirk.** A per-file HTML conversion produces
  `<title>-base.html` rather than `<title>.html`; undocumented in the spec or README.
- **`BfN6` — weasyprint missing locally for PDF conversion.** Pandoc's PDF engine is absent on
  the maintainer's dev machine; unrelated to this plan but is the reason the e2e PDF case (task
  005) gates and skips rather than fails. Still open: whether weasyprint should be a documented
  prerequisite and checked in the CLI's preflight.
- **`IxJH` — package.json stale bin entry.** `package.json` declares a second bin entrypoint,
  `liq-gen-roles-ref`, pointing at a script that doesn't exist in the repo. Pre-existing, unrelated
  to this plan; flagged for maintainer review.

Additional scope-boundary notes recorded during the plan (lower priority, informational): `eCzQ`
(why the `md2x_run` test helper exists, to suppress git stderr noise), `H7ej` (`bin/md2x` hard-requires
Homebrew's `gnu-getopt` on macOS, undocumented), `ZQ0m` (the `aI57` bug's visible symptom in old
smoke-test output, now fixed by task 002), `LPg7` (minor stale doc references in
`docs/project-structure.md`/`AGENTS.md`, out of scope for Phase 01, owned by Phase 02 task 001),
`aaLV`/`8SZc` (confirmation that `udVi`/`egcc` remain unfixed with regression tests in place, per
the key decisions above).

## Final Task State

# TODO

## Purpose and scope

Tracking document for the active plan.

## Tasks

### Phase 01 — Automated Test Coverage

- [x] [001-stand-up-test-infrastructure.md](./phase-01-automated-test-coverage/001-stand-up-test-infrastructure.md) — tier `opus-med` · branch `phase-01-task-01-stand-up-test-infrastructure` · commit `003ce7d` · merge `efe11d4dee5cd31c099a1ca388db9afffbed6ad1`
- [x] [002-fix-mirrored-output-path-derivation.md](./phase-01-automated-test-coverage/002-fix-mirrored-output-path-derivation.md) — tier `opus-med` · branch `phase-01-task-02-fix-mirrored-output-path-deriv` · commit `b620b0b` · merge `d981bef2224c3dcc5042f178788f2f24df76cb07`
- [x] [003-cover-cli-option-behavior.md](./phase-01-automated-test-coverage/003-cover-cli-option-behavior.md) — tier `sonnet-high` · branch `phase-01-task-03-cover-cli-option-behavior` · commit `b39d8ed` · merge `e5146bf7b95825a78a747c219f8caa32903fc7ad`
- [x] [004-cover-node-wrapper.md](./phase-01-automated-test-coverage/004-cover-node-wrapper.md) — tier `sonnet-high` · branch `phase-01-task-04-cover-node-wrapper` · commit `47b8c50` · merge `e00094071f075e684e9e4b176f52e48f65cd6641`
- [x] [005-add-gated-end-to-end-tests.md](./phase-01-automated-test-coverage/005-add-gated-end-to-end-tests.md) — tier `sonnet-med` · branch `phase-01-task-05-add-gated-end-to-end-tests` · commit `c5ac86c` · merge `c04448feada0fd10a2d7649753c624054dfabd0d`

### Phase 02 — Documentation Updates

- [x] [001-update-architecture-docs.md](./phase-02-doc-updates/001-update-architecture-docs.md) — tier `sonnet-high` · branch `phase-02-task-01-update-architecture-docs` · commit `…` · merge `6099c9b20019ad3c7701da133b71ad76aa7e42f8`

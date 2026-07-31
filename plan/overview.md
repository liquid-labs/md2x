# Title Precedence Fix

## Purpose and scope

Fix followup `CwaE` from `plan/followups.yaml`: `src/cli/md2x.sh`'s per-file conversion loop
unconditionally overwrites `TITLE` from each input file's own basename
(`TITLE=$(basename "${MD_FILE}" .md)`, currently at line ~287), so `--title`/`-t` has zero effect
on a directly-named, non-`--single-page`, non-stdin conversion's output filename or
`--infer-title` metadata — contradicting `docs/md2x-spec.md`'s API table entry for `-t`,
`--title <title>` ("Document title, used for the output filename and the PDF header text.").
`--single-page` and stdin (`-`) conversions already honor `--title` correctly today and are out
of scope; only the per-file/batch conversion path (the `else` branch of the main conversion loop
in `src/cli/md2x.sh`, used whenever `--single-page` is absent and input is not piped via stdin)
is broken.

**Resolution (confirmed with the maintainer; not open for re-litigation, not a `user_question`
for a future re-invocation of this planning session):** honor `--title` only when exactly one
input file will be converted in the non-`--single-page` path — whether that one file was named
directly on the command line, or is the sole match of a `SEARCH_DIRS` (directory-argument)
search. When the user explicitly passes `--title`/`-t` **and** more than one file will be
converted in that path, `md2x` rejects the invocation with a clear fatal error at startup, before
any conversion work begins — consistent with the script's other upfront-validation pattern (the
`--toc`/`--no-toc` conflict check, `src/cli/md2x.sh` lines ~121–129, deliberately positioned
before the `ensure-weasyprint` call at line ~133 so a doomed invocation never pays for the
potentially minute-long WeasyPrint bootstrap). A naive "just honor `--title`" fix without the
file-count gate would instead make every file in a multi-file/directory batch collide on one
output filename — this is the hazard the fatal-error path exists to prevent.

**Scope:**

- `src/cli/md2x.sh` — distinguish "user explicitly passed `--title`" from the unset default
  (`setSimpleOptions`'s existing `TITLE_SET` companion variable, emitted automatically for
  `TITLE:t=`'s value-taking spec, already provides this — no option-spec change is needed);
  determine up front, before any conversion work (including the `ensure-weasyprint` bootstrap),
  how many files the non-`--single-page` per-file path will convert, counting both directly-named
  files and every `SEARCH_DIRS` root's recursive `*.md` matches; fail fast with a descriptive
  error when `--title` was explicit and that count exceeds one; honor `--title` for both the
  output filename and the PDF header/`--infer-title` metadata when the count is exactly one.
  `--help` text and the CLI's Node wrapper (`src/node/md2x.js`) need no code change — the wrapper
  is a thin pass-through that already throws on any non-zero CLI exit — but `--help`'s `-t`
  description does need the same wording refresh as the spec, since it lives in the same file
  this task already touches.
- `docs/md2x-spec.md` — correct the `-t`, `--title <title>` API table entry (line ~86) and the
  CLI exit-behavior sentence (line ~95) to state the new single-file-only precedence and the
  batch fatal-error case accurately.
- Test coverage — new bats cases (a dedicated `src/cli/test/bats/title-precedence.bats`, matching
  the precedent set by `toc-flags.bats` for a flag getting its own focused behavioral-contract
  file) proving: `--title` honored for one directly-named file; `--title` honored when a
  directory search resolves to exactly one file; `--title` rejected (fatal, no output, `pandoc`
  never invoked) for multiple directly-named files; `--title` rejected for a directory search
  yielding multiple files; and, as a regression control, that the existing basename-per-file
  behavior is unchanged when `--title` is absent.
- This is followup-driven work with no pre-existing task doc — the phase-01 task doc below is
  authored directly from the followup text, this overview, and the cited source/spec locations
  (no separate research was needed; the `TITLE_SET` mechanism was confirmed by reading
  `node_modules/@liquid-labs/bash-toolkit/dist/cli/options.func.sh`, the library backing
  `setSimpleOptions`).

**Precedent.** `plan/phase-01-markdown-toc-generation/003-add-toc-flag-and-conflict-check.md`
(from the prior `markdown-toc-generation` plan, merged 2026-07-30) is this followup's origin: its
own `## Status` section documents this exact bug, discovered while validating that task's
checklist, and explicitly deferred it as "its own design questions ... that deserve a dedicated
task, not a rider here." This plan is that dedicated task. That task doc's structure (one task
bundling the `src/cli/md2x.sh` change, its `--help` text, and a new dedicated bats file) is the
sizing precedent this plan follows for its own phase-01 task.

## Current status

No implementation has started. Phase 01 (`title-precedence`) begins with its single task,
`001-fix-title-precedence-for-batch-conversions.md`. Phase 02 (`doc-updates`) is a follow-on
documentation-consistency review, gated on phase 01 landing.

## Overview

### Phase 01 — Title Precedence Fix

One task:

- **`001-fix-title-precedence-for-batch-conversions.md`** — the whole fix: the `src/cli/md2x.sh`
  file-count-gated `--title` precedence logic and its `--help` text, the `docs/md2x-spec.md`
  updates, and the new `title-precedence.bats` coverage. Not split further — the implementation,
  its exact error-message wording, and the tests asserting against that wording are tightly
  coupled, so a split would only add a hard sequential dependency without enabling any real
  parallelism (matching the precedent task's own bundling of source + help text + tests). No
  parallel-eligible tasks in this phase.

### Phase 02 — Documentation Updates

Added per the architectural-implications check (this plan changes spec-defined CLI behavior: the
`-t`/`--title` API contract, plus a new fatal-error case). One task:

- **`001-update-architecture-docs.md`** — an architect-tier review confirming
  `docs/md2x-spec.md` was updated correctly and completely by phase 01, and that
  `docs/architecture.md` needs no corresponding change (it documents the header/footer overlay
  mechanism and the TOC preprocessor, not per-file title derivation, so no hit is expected there
  — the review confirms rather than assumes this). Depends on phase 01's task landing first.

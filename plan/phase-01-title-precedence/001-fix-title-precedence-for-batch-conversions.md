# Fix Title Precedence For Per-File Conversions

## Purpose and scope

Fix followup `CwaE`: `src/cli/md2x.sh`'s per-file conversion loop unconditionally overwrites
`TITLE` from each input file's own basename, so `--title`/`-t` has zero effect on a
directly-named, non-`--single-page`, non-stdin conversion's output filename or `--infer-title`
metadata — contradicting `docs/md2x-spec.md`'s `-t`/`--title` API table entry. `--single-page`
and stdin (`-`) conversions already honor `--title` correctly (they always produce exactly one
output file) and must not change.

Scope: `src/cli/md2x.sh` (option-processing/validation section, the main conversion loop, and the
`--help` heredoc's `-t` entry), `docs/md2x-spec.md` (the `-t` API table row and the exit-behavior
sentence), and a new `src/cli/test/bats/title-precedence.bats`. No changes needed to
`src/node/md2x.js` — see [Assumptions](#assumptions). This is the plan's only task; nothing here
runs in parallel with anything else in this phase.

## Requirements

1. **Distinguish "explicitly passed" from "unset default" for `--title`.** No option-spec change
   is needed: `TITLE:t=` (line ~25's `setSimpleOptions` call) already carries a trailing `=`,
   which makes the underlying `setSimpleOptions` implementation
   (`node_modules/@liquid-labs/bash-toolkit/dist/cli/options.func.sh`, see its `OPT_ARG`/`_SET`
   handling) emit a companion `TITLE_SET` variable alongside `TITLE`: empty when `--title`/`-t`
   was not given, `true` when it was — regardless of what value was passed (including an empty
   string, `--title ''`, which still counts as explicit; do not special-case it). Use
   `[[ -n "${TITLE_SET:-}" ]]` as the "was `--title` explicit" test everywhere below. This
   `_SET` idiom is not used elsewhere in this codebase today — confirm it actually resolves as
   described (e.g. via a quick manual `./bin/md2x --title foo report.md` run with a stray `echo
   "TITLE_SET=${TITLE_SET:-}" >&2` while developing) before relying on it, then remove the
   diagnostic.

2. **Determine, up front, how many files the non-`--single-page` per-file path will convert.**
   That path runs whenever `[[ -z "${SINGLE_PAGE}" ]] && [[ -z "${INPUT}" ]]` (i.e. not
   `--single-page` and not stdin `-`) — the two other input modes already handle `--title`
   correctly and are untouched by this task. When that path is active, compute the total file
   count as: `list-count MD_FILES` (directly-named files; `list-count` is already available via
   the file's existing `import lists`) **plus**, for every entry in `SEARCH_DIRS`, the number of
   `*.md` files `find "${ROOT_DIR}" -name "*.md"` returns under it — the same `find` invocation
   the real processing pipe later uses (line ~337), so the count and the eventual per-root file
   set never disagree. Do not try to replicate the unreadable-search-root abort/continue
   subtlety the real pipe has (see followup `S92a`, out of scope); a plain `find ... | wc -l` per
   root is sufficient and, because `wc -l` always exits 0, cannot itself trip `errexit` under
   `pipefail` the way the real pipe's `while read` can.

3. **Fail fast when `--title` is explicit and more than one file would be converted.** When (a)
   the non-`--single-page`/non-stdin path is active, (b) `TITLE_SET` is non-empty, and (c) the
   total count from requirement 2 is greater than 1, call `echoerrandexit` with a message that
   names both the conflict and the count, e.g. along the lines of:

   ```
   Cannot use '--title'/'-t' with more than one input file (N files would be converted); '--title'
   only applies to a single-file conversion. Use '--single-page' to combine multiple files under
   one title, or omit '--title' to use each file's own basename.
   ```

   (Exact wording is at the implementer's discretion; it must name `--title`/`-t`, state that
   multiple files are involved, and suggest `--single-page` as the batch-with-one-title
   alternative — mirroring the existing `--toc`/`--no-toc` conflict message's directness.)

   Position this check where the existing `--toc`/`--no-toc` conflict check and
   `test_formats` validation already sit (lines ~111–129) — specifically, **before** the
   `ensure-weasyprint` call (line ~133), which can trigger a minute-long network install on a
   cold machine, so a doomed invocation never pays for it. This requires moving the input-path
   processing block that currently populates `SEARCH_DIRS`/`MD_FILES`/`INPUT` (the stdin branch
   and the `while (( $# > 0 )); do ... done` args loop, currently at lines ~178–197) to run
   before that check, since the count in requirement 2 depends on it. Confirm nothing between the
   old and new location depends on execution order in either direction: `OUTPUT_PATH`'s default
   assignment (line ~131) and `ensure-weasyprint` do not read `SEARCH_DIRS`/`MD_FILES`/`INPUT`,
   and the args loop does not read `OUTPUT_PATH` or anything `ensure-weasyprint` sets. Exit
   status is `echoerrandexit`'s default `1`, matching the `--toc`/`--no-toc` and unrecognized
   `--output-format` paths. No output file, no intermediate file, and no stub/tool invocation
   (including `pandoc`) may occur on this path.

4. **Honor `--title` for the single-file case.** In the main conversion loop's per-file branch
   (currently `TITLE=$(basename "${MD_FILE}" .md)`, line ~287), only fall back to the basename
   when the user did not explicitly pass `--title`:

   ```bash
   [[ -n "${TITLE_SET:-}" ]] || TITLE=$(basename "${MD_FILE}" .md)
   ```

   This is safe given requirement 3's upfront gate: whenever `TITLE_SET` is set, this loop is now
   guaranteed to process at most one file, so `TITLE` stays pinned to the explicit value for the
   loop's single iteration. Because `generate-page()` derives both the output filename
   (`BASE_OUTPUT`, built from `TITLE` a few lines below) and the `--infer-title` metadata title
   (`src/cli/lib/generate-page.sh` line ~5, `title: '${TITLE}'`) from the same `TITLE` variable,
   this one change fixes both consequences the followup names — the output filename and the
   `--infer-title` metadata — with no separate `generate-page.sh` edit needed.

5. **Update the `--help` heredoc.** The `-t, --title <title>` entry (lines ~66–67) currently
   reads "Document title; used for the output filename and the PDF header text." with no mention
   of the batch/single-file distinction. Rewrite it to state the new precedence: honored when
   exactly one file will be converted (a lone directly-named file, or a search resolving to
   exactly one file), and that passing `--title` with multiple files is a fatal error. Keep the
   heredoc's existing two-column layout and wrap width (see the surrounding `--toc`/`--no-toc`
   entries added by the precedent task for the established wrapping convention).

6. **Update `docs/md2x-spec.md`.**
   - The `-t`, `--title <title>` API table row (line ~86, under [API definition](../../docs/md2x-spec.md#api-definition))
     currently reads "Document title, used for the output filename and the PDF header text."
     with no precedence caveat. Rewrite it to state plainly that this only applies when exactly
     one file is converted outside `--single-page` (a lone directly-named file, or a search
     resolving to exactly one file), and that combining `--title` with more than one file in that
     path is a fatal error.
   - The CLI exit-behavior sentence (line ~95: "Exits non-zero with a descriptive message for any
     input path that is neither a file nor a directory, for an unrecognized `--output-format`, or
     for passing both `--toc` and `--no-toc` together") needs the new case appended, matching its
     existing "checked, and rejected, before any conversion work begins" framing — this task's
     new check belongs to that same family.
   - Skim UC3 (Batch-convert a directory, lines ~32–36) and UC4 (Concatenate multiple files,
     lines ~38–42) for anything implying `--title` behaves uniformly across a batch outside
     `--single-page`; neither currently claims that, so no change is expected there, but confirm
     rather than assume. UC1 (single file, lines ~20–24) and the "Automatic PDF header/footer"
     bullet in [General features](../../docs/md2x-spec.md#general-features) (line ~63, "from
     `--title`, or otherwise the source filename") already read correctly for the single-file
     case and need no change.
   - `README.md`'s own CLI reference table carries the same stale `-t`/`--title` wording
     (line ~84) but is **not** in this task's scope per the plan's explicit scope list — see
     [Assumptions](#assumptions); do not edit it here.

7. **Tests — new `src/cli/test/bats/title-precedence.bats`.** Follow the harness contract in
   `src/cli/test/helpers/common.bash` (`md2x_setup`/`md2x_teardown`, `md2x_run`, `md2x_write_doc`,
   `assert_*`/`refute_*` from `assertions.bash`) and the structural precedent in
   `src/cli/test/bats/toc-flags.bats` and `src/cli/test/bats/mirrored-output-paths.bats`. Cover
   at minimum:
   - **(a) `--title` with exactly one directly-named file is honored.** One file named directly
     on the command line, `--title Foo`; assert the output is `Foo.<format>` (not the input's
     basename), `assert_success`, and pandoc invoked exactly once. Add an `--infer-title` variant
     (or fold it into the same case) asserting the captured pandoc metadata carries
     `title: 'Foo'`, per the existing `--infer-title` case in `pandoc-args.bats`.
   - **(b) `--title` with a directory search resolving to exactly one file is honored.** A
     directory argument containing exactly one `*.md` file, `--title Foo`; assert the output is
     `Foo.<format>` (mirroring `mirrored-output-paths.bats`'s tree-assertion style) rather than
     the found file's own basename.
   - **(c) `--title` with multiple directly-named files is a fatal error.** Two or more files
     named directly, `--title Foo`; `assert_failure`, `assert_stderr_contains` naming
     `--title`/`-t` and the conflict, `refute_stub_called pandoc`, and no output file for either
     input's title/basename exists.
   - **(d) `--title` with a directory search yielding multiple files is a fatal error.** A
     directory argument containing two or more `*.md` files, `--title Foo`; same assertions as
     (c).
   - **(e) No `--title` with multiple files leaves the existing basename-per-file behavior
     unchanged.** A regression control: multiple directly-named files (or a multi-file directory
     search) with no `--title`; assert each output is named from its own input basename, exactly
     as `mirrored-output-paths.bats`'s existing cases already establish, confirming this task
     did not alter the no-`--title` path.
   - **(recommended, not strictly required by the plan brief) A mixed-source case** — one
     directly-named file plus a directory search that itself also resolves to at least one file,
     total count > 1, with `--title` — to directly exercise requirement 2's summing of both
     sources rather than relying on (c) and (d) to imply it.

## Validation

- `make test` passes in full (`make test-cli` including the new `title-precedence.bats`, and
  `make test-node` — unaffected, since `src/node/md2x.js` is untouched per
  [Assumptions](#assumptions)).
- `make lint` passes (no `src/node` changes are expected, so this should be a no-op pass).
- Manual smoke checks against a local build (`npm run build`, then run from a scratch directory):
  - `./bin/md2x --title Foo report.md` (single directly-named file) produces `Foo.pdf`, not
    `report.pdf`.
  - `./bin/md2x --title Foo report.md notes.md` (two directly-named files) exits non-zero, prints
    a message naming `--title`/`-t`, and creates neither `Foo.pdf` nor any per-input-basename
    output.
  - `./bin/md2x report.md notes.md` (no `--title`) still produces `report.pdf` and `notes.pdf`,
    confirming the no-`--title` baseline is unchanged.
  - `./bin/md2x --help | grep -A2 -- '-t, --title'` reflects the new precedence wording.
- `grep -n 'TITLE_SET' src/cli/md2x.sh` shows both the upfront gate (requirement 3) and the
  per-file fallback guard (requirement 4).
- `grep -n -- '--title' docs/md2x-spec.md` shows the updated API table row and exit-behavior
  sentence both mention the single-file precedence / multi-file fatal case.
- Confirm the existing `--infer-title` cases in `pandoc-args.bats` and the existing
  `--single-page`/stdin `--title` cases in `single-page-and-stdin.bats` still pass unmodified —
  this task must not touch either path's behavior.

## Assumptions

- `src/node/md2x.js` needs no code change. It is a thin pass-through that shells out to the built
  CLI and already throws an `Error` (carrying the exit code and stderr) on any non-zero CLI exit,
  per `docs/md2x-spec.md`'s Node library `Throws` contract — so the new fatal-error case
  surfaces correctly through the wrapper with no wrapper-side change. Separately, the wrapper's
  own `markdown`-string call path (`md2x.js` lines ~69–79) stages the string into a file already
  named `${title}.md`, so that call site was never actually hitting this bug in the first place
  — the staged file's basename already equals `title`. No Jest coverage is required for this
  task; if the manager wants explicit Node-side regression coverage for the new fatal-error case,
  that is a reasonable follow-up, not a gap in this task.
- `README.md`'s CLI reference table (`-t, --title <title>` row) carries the same stale wording as
  the spec's superseded text but is deliberately left unedited — it is not named in this plan's
  scope (`docs/md2x-spec.md` only). Flagged to the manager in this task's structured report as a
  candidate one-line follow-up, not folded into this task.
- The `TITLE_SET` idiom (documented in requirement 1) is confirmed by reading
  `node_modules/@liquid-labs/bash-toolkit/dist/cli/options.func.sh` directly, not by a
  pre-existing usage example elsewhere in this codebase (there is none yet) — verify it live
  early in implementation, per requirement 1's note, rather than late.

## References

- `plan/followups.yaml`, item `CwaE` — this task's origin.
- `plan/phase-01-markdown-toc-generation/003-add-toc-flag-and-conflict-check.md`'s `## Status`
  section (from the merged `markdown-toc-generation` plan) — where this bug was first surfaced
  and deliberately deferred; also the structural/sizing precedent for this task (one task
  bundling source + help text + a new dedicated bats file) and for the upfront-validation
  placement relative to `ensure-weasyprint`.
- `src/cli/md2x.sh` — lines ~25 (the `setSimpleOptions` call, `TITLE:t=`), ~103–133 (binary
  preflight, `test_formats`, the `--toc`/`--no-toc` conflict check and `TOC_MODE` resolution,
  `ensure-weasyprint`), ~176–197 (`TO_STDOUT`/`QUIET`, the input-path processing block to
  relocate), ~209–212 (`--single-page`'s already-correct `TITLE` handling, for contrast), and
  ~275–341 (the main conversion loop, including line ~287's basename overwrite and line ~306's
  already-correct `TITLE="${TITLE:-output}"` for the single-page/stdin branch).
- `src/cli/lib/generate-page.sh` line ~5 (`--infer-title`'s `title: '${TITLE}'` metadata) and
  lines ~130/~150 (the PDF header/overlay's own `${TITLE}` use) — both already read from the same
  `TITLE` this task fixes, so both consequences the followup names are fixed by requirement 4
  alone.
- `node_modules/@liquid-labs/bash-toolkit/dist/cli/options.func.sh` — `setSimpleOptions`'s
  `_SET` companion-variable mechanics (requirement 1) and `echoerrandexit`.
- `node_modules/@liquid-labs/bash-toolkit/dist/data/lists.func.sh` — `list-count`, used by
  requirement 2.
- `docs/md2x-spec.md` — lines ~78–95 ([API definition](../../docs/md2x-spec.md#api-definition)'s
  flags table and exit-behavior sentence, requirement 6) and lines ~20–48 (UC1/UC3/UC4, to skim
  per requirement 6).
- `src/cli/test/helpers/common.bash` — the bats harness contract (`md2x_run`,
  `md2x_write_doc`, PATH/stub setup) every new case must follow.
- `src/cli/test/bats/toc-flags.bats` and `src/cli/test/bats/mirrored-output-paths.bats` — the
  structural and assertion-style precedent for the new `title-precedence.bats` file (requirement
  7).
- `src/cli/test/bats/pandoc-args.bats`'s `--infer-title` cases and
  `src/cli/test/bats/single-page-and-stdin.bats`'s `--title` cases — the existing, must-stay-green
  coverage for the paths this task does not change.
- `src/node/md2x.js` lines ~30–36 and ~69–79 — the Node wrapper's `title` handling, confirming no
  code change is needed there (see Assumptions).

## Checkpoint hints

- After moving the input-path processing block and adding the file-count gate + fatal-error
  check in `src/cli/md2x.sh` (requirements 1–3), before touching the per-file loop.
- After the per-file loop's `TITLE_SET` guard and the `--help` text update (requirements 4–5).
- After the `docs/md2x-spec.md` updates (requirement 6).
- After `title-precedence.bats` is written and passing (requirement 7).

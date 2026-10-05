# Harden Input Discovery and Validation

## Purpose and scope

Make input discovery and argument validation part of the deliberate 1.0 contract:

- a usage error for no arguments and for directories that yield no Markdown
- case-insensitive `.md`/`.markdown` discovery
- deduplication
- a clear error when `-` is mixed with other inputs
- a case-insensitive `--output-format` whose error lists the valid formats
- rejection of input that is not valid UTF-8 or contains NUL bytes

This is a standard implementation task; no dedicated skill applies.

Covers the rest of S2 (Phase 1 handled empty stdin) and S15, N1, N3, and N7.

The second link in Phase 2's serial chain on `src/cli/md2x.sh`. It depends on `001-add-version-flag-and-help-contract`. It may also touch `src/cli/lib/toc-preprocess.py` for N7.

Out of scope:

- `-o`, `--to-stdout`, and collision checks (`003-add-output-option-and-collision-checks`)
- the Node `sources: []` case (`007-rewrite-node-wrapper-on-child-process`)
- README and spec wording (Phase 3)

## Requirements

Follow [Input discovery](../notes/design-decisions.md#input-discovery):

1. **No arguments.** `md2x` with no positional arguments prints the usage summary, or Phase 1's short usage hint, to stderr and exits 2. Today it exits 0 silently. `md2x --help` is unchanged.
2. **Directory search.**
   - Match `*.md` and `*.markdown` case-insensitively, for example with `find … \( -iname '*.md' -o -iname '*.markdown' \)`. Keep `find` invocations portable across BSD and GNU `find`.
   - The output basename strips whichever extension matched, case-insensitively. `Notes.MARKDOWN` becomes `Notes.<format>`. Apply the same stripping to directly named files. Today `basename "${MD_FILE}" .md` handles only `.md`. Use parameter expansion or `basename --`, so names that start with `-` work.
   - The existing mirrored-output and `--flatten-dirs` behavior must not change, apart from the newly matched files.
   - The unreadable-search-root behavior (followup 8ZmD, the `exit-codes.bats` cases) must keep working.
3. **Empty directories.**
   - If the directory arguments, plus any directly named files, yield zero files overall, exit 2 with `md2x: no Markdown files found in <dir>…`.
   - A directory that yields nothing while other inputs do yield files gets one stderr warning, and the run continues.
4. **The `--title` gate's file count.** The pre-conversion count that guards `--title` must use the same case-insensitive discovery and the deduplicated set. Today it uses a separate `find -name "*.md" | wc -l`. Build the resolved input list once and derive both the count and the conversion stream from it, so the two cannot drift. `003-add-output-option-and-collision-checks` builds target paths from this same up-front list, so make it reusable: a list of source path plus search root, built before any conversion.
5. **Deduplication.**
   - Each physical file is converted once, even when it is named more than once or reached through different spellings. Examples: `a.md a.md`, `./a.md a.md`, `d1 d1`, `d1 ./d1/`, and a file named directly that is also found under a directory argument.
   - Compare canonical paths, using the physical directory (`cd … && pwd -P`, which works in bash 3.2 without GNU `realpath`) plus the basename.
   - The first occurrence wins, which keeps today's order: directly named files first, then sorted search results. Its search root, and so its output location, is the one used.
   - Do not resolve through symlinked files beyond the directory level.
6. **Mixing `-`.** `-` together with any other positional argument is a usage error, exit 2: `md2x: '-' (stdin) cannot be combined with other inputs`. This replaces today's misleading "neither a file nor a directory". `- -` is also a usage error.
7. **Format validation.**
   - `--output-format`/`-F` is matched case-insensitively and normalized to lowercase before use. `-F PDF` writes `.pdf`.
   - Use a bash 3.2-safe lowercasing, such as `tr '[:upper:]' '[:lower:]'`. `${var,,}` is bash 4 only.
   - An unsupported value exits 2 with `md2x: unsupported output format '<value>' (expected pdf|html|docx)`.
8. **Encoding (N7).**
   - Input that is not valid UTF-8, or that contains a NUL byte, fails with exit 1 and a message naming the source file, for example `md2x: '<file>' is not valid UTF-8 text`. For stdin, name it `stdin`.
   - The design suggests the check live in `src/cli/lib/toc-preprocess.py`, which already reads every document. If it lives there, pass the display name in, for example with a new `--source-name` argument. Map the preprocessor's failure to an md2x-formatted message and exit 1. Do not let a Python traceback reach stderr.
   - The check must not change the preprocessor's output for valid input. Its 35 existing `toc-preprocess.bats` cases must stay green.
   - A UTF-8 BOM is valid input and must be accepted.
9. **Help text.** Update `--help` to say directories are searched for `*.md` and `*.markdown`, case-insensitively.
10. **Tests.** Add bats cases. Put the stub-based ones in an existing file such as `mirrored-output-paths.bats` or `exit-codes.bats`, or in a new `input-discovery.bats`. Cover:
    - no args → exit 2 with usage on stderr
    - an empty dir alone → exit 2
    - an empty dir plus a non-empty dir → warning and success
    - `X.MD`, `y.markdown`, and `z.Markdown` discovered, with the correct output names
    - each deduplication spelling above converts once, checked through the stub log
    - `- a.md` → exit 2 with the new message
    - `-F HTML` succeeds
    - `-F txt` → exit 2, and the message lists `pdf|html|docx`
    - a NUL-containing file and an invalid-UTF-8 file → exit 1 naming the file
    - a BOM file succeeds
    - a file named `-weird.md` converts
    - the `--title` gate counts `.markdown` files

## Validation

- `make qa` passes, and the bats suite also passes under the Phase 1 bash 3.2 interpreter override where `/bin/bash` is 3.x.
- Each new regression case fails on the pre-task code and passes after it. Your report states that this was checked.
- `grep -n "name \"\*.md\"" src/cli/md2x.sh` finds no remaining case-sensitive search.
- Manual: with the real toolchain, `bin/md2x -F HTML -p /tmp/out <dir containing a.MD and b.markdown>` creates `a.html` and `b.html`.

## Assumptions

- Phase 1 is complete: error helper, exit codes, parser, bash 3.2 compatibility, work directory, and byte-exact stdin. The pre-plan line numbers no longer apply.
- Treating a single empty directory among non-empty ones as a warning, and only an overall zero-file result as exit 2, is a recorded planner assumption. Do not reopen it.

## References

- [Design decisions: input discovery](../notes/design-decisions.md#input-discovery): the binding rules.
- [Design decisions: exit-code contract](../notes/design-decisions.md#exit-code-contract): exit 1 for encoding, exit 2 for usage.
- [Design decisions: bash version support](../notes/design-decisions.md#bash-version-support): 3.2 constraints such as no `${var,,}` and `nounset`-safe arrays.
- [Audit coverage](../notes/audit-coverage.md): rows S2, S15, N1, N3, and N7.
- `src/cli/md2x.sh`: argument loop, `--title` gate count, discovery process substitution.
- `src/cli/lib/toc-preprocess.py` and `src/cli/test/bats/toc-preprocess.bats`.

## Checkpoint hints

- After the up-front resolved input list with deduplication and case-insensitive discovery.
- After the no-args, empty-directory, `-` mixing, and format validation.
- After the N7 encoding check in `toc-preprocess.py`.
- After the bats cases.

## Status

Outcome: succeeded (2026-10-05).

- Resolved input list (`RESOLVED_INPUTS`/`RESOLVED_COUNT`, records `<file><tab><root>`) is built once in `src/cli/md2x.sh` before conversion with case-insensitive `.md`/`.markdown` discovery and canonical-path dedup (first occurrence wins); the `--title` gate and the conversion loop both consume it. `md2x-list-inputs` and the search-root error file are gone; an unreadable root is recorded in memory and still reported after the files found so far convert.
- No-args, empty-dir, `-` mixing, case-insensitive `-F` validation, help text: `src/cli/md2x.sh`. Helpers `md2x-has-control-chars` and `md2x-strip-markdown-ext`: `src/cli/lib/title-safe.sh`.
- N7: `src/cli/lib/toc-preprocess.py` gained `--source-name` and `--validate`, strict UTF-8/NUL check, exit status 4 mapped to md2x exit 1 in `src/cli/lib/generate-page.sh` (single-page validates each source separately).
- Tests: `src/cli/test/bats/input-discovery.bats` (new, 25 cases); `output-format.bats` message updated.
- Validation: `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` pass; new cases fail on pre-task code (BOM case is a positive guard and passes before and after).

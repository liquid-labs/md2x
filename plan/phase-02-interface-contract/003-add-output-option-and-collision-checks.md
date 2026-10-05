# Add Output Option and Collision Checks

## Purpose and scope

Give md2x an explicit output contract:

- a new `-o, --output <file|->` option with format inference
- `--to-stdout` as a pure stream that requires exactly one output
- `-p` trailing-slash normalization and non-directory rejection
- a pre-conversion check that fails when two inputs, or an input and an output, map to the same path

This is a standard implementation task; no dedicated skill applies.

Covers S14, S4, the `-p` normalization part of S10, and the output-path `mkdir` leak site from S8.

The third link in Phase 2's serial chain on `src/cli/md2x.sh` and `src/cli/lib/generate-page.sh`. It depends on `002-harden-input-discovery-and-validation`, whose up-front resolved input list this task extends with target paths. `004-resolve-links-and-images-with-lua-filter` needs the final output path that this task computes. `007-rewrite-node-wrapper-on-child-process` maps its `output` option to `-o`.

Out of scope: a `--force`/no-clobber flag (overwriting a file left by an earlier run stays allowed) and README/spec wording (Phase 3).

## Requirements

Follow [Output options](../notes/design-decisions.md#output-options) and [Output collision protection](../notes/design-decisions.md#output-collision-protection).

1. **Target planning.**
   - Before any conversion, and before `ensure-weasyprint`, which can trigger a minute-long install, compute the full list of output target paths from the resolved input list.
   - Every check below runs against that list. The conversion loop consumes it, and nothing recomputes paths.
2. **`-o, --output <file|->`.**
   - Register `-o`/`--output` in Phase 1's explicit option table if it is not already there. It takes a required argument.
   - Valid only when exactly one output results: one input file (directly named, or a directory resolving to exactly one file), stdin, or `--single-page`. Otherwise exit 2 with a message giving the output count.
   - Format inference. When `-F` is absent, a recognized extension (`.pdf`, `.html`, `.docx`, matched case-insensitively) sets the format. When `-F` is given and contradicts a recognized extension, exit 2. When the extension is not recognized and `-F` is absent, use the default format (`pdf`) and write to the path exactly as given.
   - `-o -` behaves exactly like `--to-stdout`.
   - The parent directory is created as needed. A parent path component that exists as a non-directory exits 2 with an md2x message. Any other `mkdir` failure exits 1 with an md2x message. A raw `mkdir:` error must never reach stderr.
   - `-o` together with `-p/--output-path` exits 2.
   - With `-o`, the title is display-only. Skip Phase 1's filename-sink title validation, so any printable `--title` is accepted. Keep the metadata and PostScript sinks unchanged.
   - `Created <path>` and `--list-files` print the `-o` path as given.
3. **`--to-stdout`.**
   - Writes only to stdout. The output is built inside the per-run work directory under a fixed name that is never derived from `--title`, then streamed with `cat` and removed with the work directory.
   - No file appears in the cwd or under `-p`. With `--keep-intermediate`, it stays in the kept work directory only.
   - Requires exactly one output; otherwise exit 2.
   - Combining it with `--list-files` exits 2. Combining it with `-o <file>` exits 2. `-o -` together with `--to-stdout` is allowed and redundant.
   - It still implies `--quiet`.
4. **`-p, --output-path`.**
   - Normalize trailing slashes, so `-p o3/` prints `o3/a.html`, not `o3//a.html`. Keep `/` itself as `/`.
   - An existing non-directory is a usage error, exit 2.
   - A mirrored subdirectory that cannot be created because a file is in the way exits 2 before any conversion, naming the path.
5. **Collision check (S4).**
   - Two inputs that map to the same target exit 2, naming both sources and the target. This covers batch runs, `--flatten-dirs` (`d1/x.md d2/x.md -D`), directly named `d1/x.md d2/x.md`, and `x.md` plus `x.markdown` in one directory.
   - Compare targets case-insensitively, because the default macOS filesystem is case-insensitive and `A.md`/`a.md` flattened together would silently overwrite there. This is a planner assumption. A rare false positive on case-sensitive filesystems is the accepted cost.
   - A target that equals one of the input source paths exits 2, so `md2x -F html -o a.md a.md` cannot destroy its input. Compare canonical paths here as well.
   - Overwriting a pre-existing file from an earlier run stays allowed.
   - All checks run before any output is written, so a failing invocation leaves no partial outputs.
6. **Help text.** Add the `-o, --output <file|->` row. Reword `--to-stdout` (one output only, nothing written to disk) and `-p` (conflicts with `-o`).
7. **Stub harness.** Update `src/cli/test/stubs/*` and `src/cli/test/helpers/*` only as far as the new argument shapes require.
8. **Tests.** Add bats cases, for example in a new `output-options.bats` plus additions to `output-shaping.bats`. Cover:
   - `-o out/x.html a.md` creates `out/` and writes there, with the format inferred
   - `-o x.HTML` infers html
   - `-o x.pdf -F html` → exit 2
   - `-o x a.md` writes PDF to `x`
   - `-o` with two inputs → exit 2; `-o` with `--single-page` of two inputs is allowed; `-o` with stdin is allowed
   - `-o` plus `-p` → exit 2
   - `-o -` streams and leaves no file behind
   - `--to-stdout` writes nothing to the cwd or `-p`, and the stdout bytes equal the converted output
   - `--to-stdout` with two inputs → exit 2; with `--list-files` → exit 2
   - `-p o3/` prints a single slash; `-p <existing file>` → exit 2
   - a parent path through a file → exit 2 with no raw `mkdir:` text
   - each collision shape → exit 2 naming both sources, with no outputs written
   - `-o <input>` → exit 2
   - `--title 'a/b' -o out.pdf` is accepted

## Validation

- `make qa` passes, and the bats suite also passes under the Phase 1 bash 3.2 interpreter override where `/bin/bash` is 3.x.
- The S14, S4, and S10 regression cases fail on the pre-task code and pass after it. Your report states that this was checked.
- Real-toolchain spot check, run manually or as a case in `real-toolchain-e2e.bats`: `bin/md2x -o - a.md | head -c 4` prints `%PDF`, and no `.pdf` file appears in the cwd.
- Code inspection: on the `--to-stdout` path, the file streamed to stdout is a work-directory path, never a path under the cwd or `-p`.

## Assumptions

- `002-harden-input-discovery-and-validation` is complete and exposes the up-front resolved input list.
- Phase 1's work directory variable and its fixed-name intermediates exist.
- The planner chose that an unrecognized `-o` extension falls back to the default format rather than erroring. If you find a strong reason against this, report it rather than changing it.

## References

- [Design decisions: output options](../notes/design-decisions.md#output-options).
- [Design decisions: output collision protection](../notes/design-decisions.md#output-collision-protection).
- [Design decisions: title handling](../notes/design-decisions.md#title-handling): the filename sink and `-o`.
- [Design decisions: per-run work directory](../notes/design-decisions.md#per-run-work-directory).
- [Audit coverage](../notes/audit-coverage.md): rows S4, S8, S10, and S14.
- `src/cli/md2x.sh` and `src/cli/lib/generate-page.sh`: target computation, `BASE_OUTPUT`, the `TO_STDOUT` `cat`.

## Checkpoint hints

- After the up-front target list and collision check.
- After `-o` and format inference.
- After the `--to-stdout` pure-stream change.
- After `-p` normalization, the help text, and the bats cases.

## Status

- Outcome: succeeded (2026-10-05).
- Validation: `make qa` passes (285 bats cases + node suite + lint); the full bats suite also passes with `MD2X_TEST_BASH=/bin/bash` (bash 3.2.57). The new `output-options.bats` has 29 of 34 cases failing against the pre-task code (the other 5 are exit-2-by-accident or "overwrite stays allowed" cases) and all pass after. Two real-toolchain cases added to `real-toolchain-e2e.bats` (`-o -` streams `%PDF` with no `.pdf` left in the cwd; `-o out/report` writes a real PDF).
- Files: `src/cli/md2x.sh`, `src/cli/lib/output-plan.sh` (new), `src/cli/lib/generate-page.sh`, `src/cli/lib/parse-options.sh`, `src/cli/lib/index.sh`, `src/cli/test/bats/output-options.bats` (new), `src/cli/test/bats/real-toolchain-e2e.bats`.
- Contract for later tasks: pandoc now writes to the staged `BASE_OUTPUT="${MD2X_WORK_DIR}/output.<format>"` (fixed name; needed so `-o x` without a `.pdf` extension still yields a PDF), and `generate-page` copies it to `FINAL_OUTPUT`, the planned target (empty for `--to-stdout`). Task 004 should read `FINAL_OUTPUT` for the final path. Targets are planned in `md2x.sh` into `PLANNED_TARGETS` (`<md-file><tab><target>` records) and `SINGLE_TARGET`.
- Decisions: `--title` filename validation is skipped for `--to-stdout` as well as `-o` (no file name derives from it); `-o`/`-p` containing control characters are usage errors; collision and input-overwrite checks follow a final-component symlink and compare ASCII-case-insensitively.

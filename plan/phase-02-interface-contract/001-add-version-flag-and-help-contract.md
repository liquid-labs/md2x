# Add Version Flag and Help Contract

## Purpose and scope

Add a long-only `--version` flag whose value is injected from `package.json` at build time, and bring the `--help` text up to the 1.0 contract: an exit-code section, the project homepage, `--keep-intermediate` wording that matches Phase 1's work directory, and no "other Pandoc-supported formats" claim. This is a standard implementation task; no dedicated skill applies.

Covers audit items S1, D6, D5 (help part), D16, D17, and the help-text part of S16.

This task opens Phase 2's serial chain on `src/cli/md2x.sh`. It also edits the `Makefile` `CLI_BIN` recipe, so the Node packaging task (`008-package-node-library-for-esm-cjs-and-types`) must follow it.

Out of scope: README, spec, and `AGENTS.md` edits, which belong to Phase 3. Help text for flags added by later Phase 2 tasks (`-o/--output`, `.markdown` discovery) is written by those tasks.

## Requirements

1. **`--version`.**
   - Long-only. No short form, per the [short-flag answer](../notes/short-flag-set-answer.md). Register it in Phase 1's explicit option table as long-only.
   - Prints `md2x <version>` followed by a newline to stdout and exits `0`. `<version>` is the `version` field of `package.json` at build time, for example `md2x 1.0.0-alpha.11`.
   - Like `--help`, it runs without the dependency preflight: it works with `pandoc`, `gs`, `pdftk`, `python3`, and `jq` all absent from `PATH`. Mirror whatever Phase 1 did for `--help`. If Phase 1 handles `-h`/`--help` ahead of GNU getopt resolution, handle an exact `--version` the same way, so it also works with no GNU getopt available.
   - When both `--help` and `--version` are given, `--help` wins. Pin this with a test.
2. **Build-time injection.**
   - The rolled-up `bin/md2x` carries the version as a literal. Nothing reads `package.json` at runtime for `--version`.
   - Choose a mechanism that fits `bash-rollup`. One option is a placeholder string in `src/cli/md2x.sh` that the `Makefile` recipe substitutes after rollup. Another is a generated file under a build directory that is inlined. Do not commit a generated file into `src/`.
   - `CLI_BIN` must list `package.json` as a prerequisite, so a version bump rebuilds `bin/md2x`.
   - Read the version without `jq`, because `jq` is leaving the always-required set. Use a `bun`/`node -p` one-liner, or a `sed`/`grep` extraction that is robust to whitespace.
   - The build must fail, not produce an empty version, if the version cannot be read.
   - Note in your report that the `preversion` npm script runs before the version bump. The `prepack: make all` hook that Phase 3 adds is what guarantees a published `bin/md2x` carries the bumped version. State whether this `Makefile` dependency makes that rebuild happen.
3. **Help text.** Edit the heredoc in `src/cli/md2x.sh`:
   - Drop "and other Pandoc-supported formats" from the description. Name exactly `pdf`, `html`, and `docx`.
   - Add an `Exit codes:` section listing `0` success, `1` runtime or conversion failure, `2` usage error, and `3` missing or unusable dependency, per the [exit-code contract](../notes/design-decisions.md#exit-code-contract).
   - Add a homepage line, `https://github.com/liquid-labs/md2x`, in lowercase per the org-casing decision in [Release](../notes/design-decisions.md#release).
   - Reword `--keep-intermediate` to match Phase 1's per-run work directory: the directory is kept and its path is printed to stderr. It must no longer describe the Pandoc log and overlay being written beside the output.
   - Add the `--version` row.
   - If Phase 1 has not already added it, add a short note that unambiguous long-option prefixes (`--single` for `--single-page`) and `--opt=value` are accepted, per [Short flags](../notes/design-decisions.md#short-flags).
   - Keep every option row in the existing `  -X, --long` / `      --long` shape. Phase 3's flag-table drift test parses `--help` for `(short, long)` pairs.
4. **Tests.** Add bats cases, either in a new `src/cli/test/bats/version-and-help.bats` or in an existing file that fits:
   - `--version` prints `md2x <package.json version>` and exits 0. Compare against the real `package.json` value, not a hard-coded string.
   - `--version` works with the preflight binaries removed from `PATH`.
   - `--help --version` prints help.
   - `-v` and `-V` are usage errors with exit 2.
   - `--help` contains the exit-code section and the homepage, and does not contain "other Pandoc".

## Validation

- `make qa` passes.
- Where `/bin/bash` is 3.x, the bats suite also passes under Phase 1's harness interpreter override (for example `MD2X_TEST_BASH=/bin/bash make test-cli`; use whatever variable Phase 1 actually introduced).
- `make clean && make all && bin/md2x --version` prints the `package.json` version.
- Touching `package.json`, by changing its version in a scratch copy or with `touch`, then running `make all`, rebuilds `bin/md2x`. Confirm this with `make -n` or timestamps.
- `grep -n 'other Pandoc' src/cli/md2x.sh` finds nothing.
- The new `--version` tests fail before the change and pass after it. Your report states that this was checked.

## Assumptions

- Phase 1 is complete. The project-owned option parser with its explicit short table, the error helper, the exit codes 0/1/2/3, the help-before-getopt handling, and the per-run work directory are in place. Read the current `src/cli/md2x.sh` and `src/cli/lib/` before editing, because line positions differ from the pre-plan code.
- The `md2x <version>` output format is a planner choice. No note fixes it.

## References

- [Design decisions: exit-code contract](../notes/design-decisions.md#exit-code-contract): the codes listed in help.
- [Design decisions: short flags](../notes/design-decisions.md#short-flags): `--version` is long-only.
- [Sequencing and file ownership](../notes/sequencing-and-file-ownership.md): `md2x.sh` and `Makefile` serialization.
- [Audit coverage](../notes/audit-coverage.md): rows S1, S16, D5, D6, D16, and D17.
- `src/cli/md2x.sh`: the help heredoc and option table.
- `Makefile`: the `$(CLI_BIN)` recipe.

## Checkpoint hints

- After the `Makefile` injection works and `bin/md2x --version` prints the version.
- After the help-text edits.
- After the bats cases.

## Status

Succeeded, 2026-10-05. `--version` is registered long-only in `MD2X_OPTION_TABLE` (`src/cli/lib/parse-options.sh`), handled before the dependency preflight in `src/cli/md2x.sh` (also works with no GNU getopt via an exact-match argv scan; `--help` wins). The `Makefile` `CLI_BIN` recipe substitutes the `@MD2X_VERSION@` placeholder from `package.json` (sed extraction, build fails on an unreadable or odd version) and lists `package.json` as a prerequisite. Help text updated (formats, exit codes, homepage, `--version` row, prefix/`=` note). Tests: `src/cli/test/bats/version-and-help.bats`. Validation: `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` (226 ok, 0 not ok) passed.

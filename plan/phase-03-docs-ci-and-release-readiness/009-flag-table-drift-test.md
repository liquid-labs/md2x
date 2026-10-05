# Flag Table Drift Test

## Purpose and scope

Add a bats test that fails when the set of `(short, long)` flag pairs differs between the option parser's definition table, `md2x --help`, and the README CLI table. Covers audit item D20 and success criterion 7. Touches a new file `src/cli/test/bats/flag-table-drift.bats` (and a helper under `src/cli/test/helpers/` if needed).

Hard dependencies: [README overhaul](./007-readme-overhaul.md) and [spec/AGENTS.md update](./008-spec-agents-and-structure-docs.md) (the final README table and the spec's link-instead-of-duplicate state). Last task in the phase.

## Requirements

- Locate the parser's explicit short-flag and long-flag definition table created in Phase 1 (under `src/cli/lib/`), and extract its `(short, long)` pairs with a small, robust shell or awk parse of the source (or of the built `bin/md2x`). Do not hardcode the expected list in the test; the three sources must be compared with each other.
- Extract the flag pairs from the `md2x --help` output (run `bin/md2x --help`; must work without getopt or pandoc) and from the README CLI table rows (first column, backticked short and long).
- Normalize: the pair `(short-or-empty, long)`; ignore value placeholders. `--help`, `--version`, and `-o` must be included.
- Assert all three sets are equal, with a failure message that prints which flags are missing from which source (use `diff` output).
- Also assert the spec does not carry its own flag table: it must link to the README table (grep for the link) and contain no row-style flag table.
- Prove the test detects drift: temporarily add a bogus row to the README copy, remove a flag from a help copy, and confirm failures, then restore. Do this against temp copies via an env var or function parameter so the committed README and source are untouched.
- Test must run under bash 3.2 (the Phase 1 override) and require no real toolchain.

## Validation

- `bats src/cli/test/bats/flag-table-drift.bats` passes; deliberate-drift variants fail with a clear message (report the evidence).
- `make qa` passes, and the suite passes under the bash 3.2 override.
- `git diff --stat` shows only the new test and optional helper.

## Metadata

architectural_impact: true

## Assumptions

- README table shape follows the contract in task 007: one row per flag, short and long in the first column.
- The bats runner picks up the new file automatically (`CLI_TEST_FILES` in the `Makefile`).

## References

- [Design decisions, flag table single source](../notes/design-decisions.md#flag-table-single-source)
- [Short-flag answer](../notes/short-flag-set-answer.md)
- [Audit coverage](../notes/audit-coverage.md): D20.

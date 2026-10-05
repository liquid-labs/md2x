# Reject Trailing-Slash Output Paths And Protect Dash-Leading Search Roots

## Purpose and scope

Fixes findings 3rV7 and yV1b from the Phase 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop.

- 3rV7: `-o out/ a.md` with `out/` absent passes planning and then fails at delivery with exit 1, leaving an empty directory.
- yV1b: a directory argument starting with `-` is passed to `find` unprefixed and read as a `find` option.

## Requirements

1. An `-o`/`--output` value ending in `/` is rejected with `md2x-die-usage` (exit 2) at plan time, before any conversion, and no directory is created.
2. A directory argument whose name starts with `-` is passed to `find` as a path (for example prefixed with `./`), never read as a `find` option. Displayed and listed paths stay correct.
3. Bats regression cases cover both and fail on the old code.

## Validation

1. A bats case `md2x -o out/ a.md` with `out/` absent exits 2 with a usage message, and `out/` does not exist afterwards.
2. A bats case with a directory named `-d` containing a `.md` converts or lists it successfully.
3. `make qa` is green, including under `/bin/bash` 3.2 through the harness override (`MD2X_TEST_BASH=/bin/bash make test-cli`).

## References

- Finding 3rV7, in this plan's `plan/findings.yaml`.
- Finding yV1b, in this plan's `plan/findings.yaml`.
- Files: `src/cli/md2x.sh`, `src/cli/test/bats/`.

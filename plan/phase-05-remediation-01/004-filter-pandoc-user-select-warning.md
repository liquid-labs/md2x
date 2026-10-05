# Filter Pandoc Template User-Select Warning From PDF Stderr

## Purpose and scope

Fixes finding KhXI from the Phase 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. Every PDF run prints one WeasyPrint warning that comes from pandoc's own default template, not from `github.css`.

## Requirements

1. `generate-page.sh` drops exactly the WeasyPrint line ``WARNING: Ignored `user-select: none` at 49:32, unknown property.`` (an exact-line match, not a pattern that could hide other warnings). All other stderr passes through unchanged, and the exit status is preserved.
2. The exemption is removed from the PDF no-warnings case in `real-toolchain-e2e.bats`, so the case asserts zero `WARNING: Ignored` lines.

## Validation

1. The e2e case passes with the exemption removed, and fails if the filter is removed.
2. A WeasyPrint failure still surfaces its stderr and a nonzero exit (an existing or new case).
3. `make qa` is green.

## References

- Finding KhXI, in this plan's `plan/findings.yaml`.
- Files: `src/cli/lib/generate-page.sh`, `src/cli/test/bats/real-toolchain-e2e.bats`.

## Status

Succeeded 2026-10-05. Pandoc stderr is captured to a work file and replayed with the exact `user-select` line dropped (`src/cli/lib/generate-page.sh`); exemption removed from `src/cli/test/bats/real-toolchain-e2e.bats`; new failure-passthrough case in `src/cli/test/bats/error-output.bats`. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` green; e2e case verified to fail with the filter disabled.

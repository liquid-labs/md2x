# Always Pass The Marker Nonce And Make Test-Pack Checks Fail Closed

## Purpose and scope

Fixes finding xDG1 from the Remediation Round 1 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. It runs last in the round because it edits `src/cli/md2x.sh` and `src/cli/lib/generate-page.sh` after the delivery task.

## Requirements

1. A per-run nonce is generated in every mode, not only with `--single-page`, and always passed as `-M md2x-nonce`. The filter's other settings (`md2x-source`, `md2x-out-dir` and the rest in `md2x-links.lua`) are always supplied by `-M`, with an empty or sentinel value where unused. As a result, nothing a source's YAML front matter sets can supply or change any `md2x-*` filter setting. Update the comments in `md2x-links.lua` and `generate-page.sh` to match.
2. In `scripts/test-pack.sh`, the embedded-build-path check first asserts that both installed bundles exist and are readable. It treats a `grep` exit status of 2 or higher as a failure. It checks both the logical path (`pwd`) and the physical path (`pwd -P`) of `ROOT`.
3. In `scripts/test-pack.sh`, a missing `$ROOT/node_modules/.bin/tsc` is a hard failure ("run bun install"), not a silent fallback to a grep. Update the header comment at lines 4-6.

## Validation

1. A bats case in `src/cli/test/bats/links-and-images.bats`: in multi-file (not single-page) mode, a source with front matter `md2x-nonce: x` and a `nonce=x` marker pointing its base directory elsewhere is not honored. Images resolve against the source's own directory. The case must fail on the current code.
2. The existing single-page forged-marker cases still pass.
3. `test-pack` fails when a bundle is missing or unreadable, and when `tsc` is absent. Check this by running `make test-pack` once with `tsc` temporarily moved away (in a scratch copy, not the repo); record the result in the task report. It passes normally after `bun install`.
4. `make qa` and `make test-pack` are green.

## References

- Finding xDG1, in this plan's `plan/findings.yaml`.
- Files: `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`, `src/cli/lib/md2x-links.lua`, `src/cli/test/bats/links-and-images.bats`, `scripts/test-pack.sh`.

## Status

Succeeded, 2026-10-05. The nonce and every other filter setting are now always passed by `-M` (`src/cli/lib/generate-page.sh`, `src/cli/md2x.sh`; empty values where unused; verified with real pandoc that `-M` overrides front matter and that an empty `-M` reads as unset). `scripts/test-pack.sh` now checks both bundles exist and are readable, treats grep status 2 or higher as a failure, checks both `pwd` and `pwd -P` forms of the root, and fails hard when `tsc` is absent. New bats case in `links-and-images.bats` fails on the pre-change build and passes now. `pandoc-args.bats` was updated for the always-passed settings. `make qa`, `make test-pack` and `MD2X_TEST_BASH=/bin/bash make test-cli` pass. `test-pack` with `tsc` removed in a scratch copy fails with the "run 'bun install'" message.

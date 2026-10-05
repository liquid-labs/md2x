# Make The Single-Page Source Marker Unforgeable

## Purpose and scope

Fixes finding z2v9 from the Phase 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. A source document can contain a hand-written `<!-- md2x:source-dir=... source=... -->` comment that redirects image resolution and warning attribution under `--single-page`.

## Requirements

1. A source document cannot redirect `base_dir` or `source_name` with a hand-written marker. Either require a per-run random nonce passed to the filter with `-M` (generated in `md2x.sh`, emitted by `link-filter.sh`) or strip pre-existing markers from sources during concatenation.
2. A forged marker has no effect on image resolution or warning attribution, and is not mangled in a way that changes document content beyond removing the forgery (if stripping).
3. The nonce source, if used, works under bash 3.2 and on macOS and Linux.
4. Also embed the Lua filter with a unique heredoc terminator (for example `MD2X_LUA_EOF`) instead of a bare `EOF`, or add a bats check that the extracted filter equals the source file, so a bare `EOF` line in the filter cannot silently truncate it (from finding 32b8, item 2).

## Validation

1. A bats regression case with a forged marker in a `--single-page` input shows that images resolve against the true source directory and warnings name the true source. The case fails on the old code.
2. The existing link and image filter cases still pass.
3. `make qa` is green, including the bash 3.2 run (`MD2X_TEST_BASH=/bin/bash make test-cli`).

## References

- Finding z2v9, in this plan's `plan/findings.yaml`.
- Finding 32b8 (item 2 only), in the project backlog.
- Files: `src/cli/lib/md2x-links.lua`, `src/cli/lib/link-filter.sh`, `src/cli/md2x.sh`, `src/cli/test/bats/`.

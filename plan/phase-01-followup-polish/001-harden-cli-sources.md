# Harden CLI Sources

## Purpose and scope

Resolve followup `32b8` (all four sub-items) and `HdEH` items 2 to 4 in the CLI and Node sources. No new flags or output changes beyond one new `--infer-version` refusal.

- Roles: `developer-bash` (primary) and `developer-node` (the `md2xAsync` buffer cap).
- Suggested tier: `sonnet-high` (security-sensitive git-config handling, bash 3.2 constraints, and a source split that touches the rollup).
- Background: [followup status notes](../notes/followup-status.md). Re-verify every line number with grep first; record in the report any sub-item found already satisfied.

## Requirements

### 32b8 item 1: drop `@liquid-labs/bash-toolkit`

- Remove `import lists` from `src/cli/md2x.sh` and replace the `list-add-item` calls (`SEARCH_DIRS`, `MD_FILES`, `EMPTY_DIRS`) with plain newline-terminated string appends that keep the exact record format the later `while read ... <<<` loops expect (no extra blank records, no change in order).
- `src/cli/test/manual/visual-smoke-test.sh` also uses `import strict` and `import lists` (and one `list-add-item`). Convert it too (explicit `set -o errexit/nounset/pipefail`, plain append) so `make smoke-test` still rolls up; do not run the interactive script, but confirm `make test-out/visual-smoke-test.sh` builds and `bash -n` passes.
- Remove `@liquid-labs/bash-toolkit` from `devDependencies` in `package.json` and from both places in `bun.lock` (workspace list and package entry), preferably with `bun remove @liquid-labs/bash-toolkit`; then confirm `bun install --frozen-lockfile` succeeds and `bash-rollup` still builds `bin/md2x`.
- Do not touch prose in `docs/architecture.md` or `AGENTS.md` that mentions the toolkit; task 003 owns it. Leave the historical `parse-options.sh` header comment.

### 32b8 item 2: Lua heredoc guard

- The terminator is already `MD2X_LUA_EOF`. Confirm no line of `src/cli/lib/md2x-links.lua` equals `MD2X_LUA_EOF`, and add a bats test (in `src/cli/test/bats/links-and-images.bats` or `work-directory.bats`, whichever fits) asserting that the filter file md2x writes is byte-identical to `src/cli/lib/md2x-links.lua` and that the source has no `MD2X_LUA_EOF` line. Skip the bats addition only if an equivalent guard already exists, and say so.

### 32b8 item 3: extract discovery to `src/cli/lib/input-discovery.sh`

- Move the input-argument processing and resolution block (from the `process args` loop through the empty-directory warnings, about `md2x.sh` lines 255 to 380) into functions in a new sourced-only library `src/cli/lib/input-discovery.sh`, added to `src/cli/lib/index.sh` (the Makefile's `CLI_LIB_SRC` already finds every file under `src/cli/lib`). The library sets no state at source time.
- Behavior must be byte-identical: same messages, exit codes, ordering, the `RESOLVED_INPUTS`/`RESOLVED_COUNT`/`SEARCH_ERROR_ROOT` variables consumed by the rest of `md2x.sh`, and the same control-character handling. Keep the explanatory comments with the code they describe. Bash 3.2 only: no namerefs, so return results through documented global variables, as `parse-options.sh` does.
- `src/cli/test/bats/input-discovery.bats` and `exit-codes.bats` must pass unchanged.

### 32b8 item 4: efficiency

- `md2x-percent-encode` (`src/cli/lib/link-filter.sh`): remove the per-byte forks. Bash 3.2's `printf -v` works: use `printf -v CH "\\x${BYTE}"` for pass-through bytes and `printf -v ENC '%%%02X' "0x${BYTE}"` for escapes, avoiding the command substitutions and the per-byte `tr`. Output must be identical for every byte value (add or extend a bats test covering all 256 byte values, multibyte UTF-8, space, `-`, `>`, newline) and must stay free of space, newline, `-`, `>`.
- `md2x-lookup-record` (`src/cli/lib/output-plan.sh`) with its callers in `md2x-plan-register`: first measure planning time with a few thousand generated input files. If it is not materially slow, keep the algorithm and leave a short comment recording the measured cost; if it is, replace it with a bash 3.2-compatible approach (for example a sorted comparison, or a single `awk`/`sort`-based pass) without changing messages or semantics, including case-insensitive key comparison and first-match wins. Report the measurements.
- `md2xAsync` (`src/node/md2x.js`): cap the bytes accumulated for stdout and for stderr at the existing `MAX_BUFFER` (64 MiB). On overflow, kill the child and reject with an error shaped like `failure(...)` (`exitCode` undefined and the captured `stderr`), mirroring what the sync `maxBuffer` path produces; do not silently truncate. Add `bun:test` cases (a small injected cap or a fake bin) in the existing test files; keep `make lint` clean.

### HdEH items 2 to 4 (`src/cli/lib/preflight.sh`)

- Item 2: an existing but empty `config.worktree` (with `extensions.worktreeConfig=true`) is treated as zero keys. Test the file with `-s` (non-empty) instead of `-e`; a non-empty file whose keys cannot be read still fails closed with the existing reason.
- Item 3: after resolving the top level, also resolve `git rev-parse --absolute-git-dir` through `md2x-infer-git` from the input directory and from the top level. If they differ (a `core.worktree` redirect or any other mismatch), warn once with the existing `--infer-version: not running git in '<top>': ...; no version in the footer.` pattern, naming the reason (for example `the git directory found from the input differs from the one for the work tree top (a core.worktree redirect?)`), and print no version. Failing to resolve either is also a refusal. Do not use `-c core.worktree=` (untested); refusing is the conservative decision.
- Item 4: read keys NUL-delimited with `git config -z --list --name-only` (`md2x-infer-config-keys`). bash variables cannot hold NUL, so translate as input discovery does: `tr '\000\012' '\012\001'` (NUL to newline, embedded newline to `\001`), and have `md2x-infer-scan-keys` refuse any key containing a control character (reason: the config could not be parsed). Keep the here-string/`case` scanning (no pipe into the scan, to avoid SIGPIPE under `pipefail`) and the `|| KEYS=''` fail-closed handling.
- Optional, only if trivial: when `rev-parse --show-toplevel` fails, keep the warning but append a hint about `safe.directory` for repositories owned by another user. Do not change the warning prefix, which tests match.
- Add bats cases in `src/cli/test/bats/version-inference.bats`: an empty `config.worktree` is accepted and yields the version; a `core.worktree` pointing at another repository is refused with a warning and no version; a key containing a control character (if git can be made to store one; otherwise unit-test `md2x-infer-scan-keys` directly) is refused; existing refusal cases still pass.

### Housekeeping

- Add `Unreleased` CHANGELOG entries: the `--infer-version` refusal for a redirected git directory and the empty per-worktree config acceptance; that `md2xAsync` caps buffered output at 64 MiB and rejects on overflow; and, optionally, a one-line note that the build no longer depends on `@liquid-labs/bash-toolkit`. Other internal refactors need no entry.
- Do not commit or push.

## Validation

- `make test` passes (`make test-cli` and `make test-node`), and `make lint` is clean. On macOS also run `MD2X_TEST_BASH=/bin/bash make test-cli`.
- `grep -rn "bash-toolkit\|list-add-item\|import lists" src package.json bun.lock Makefile` shows no remaining use (the `parse-options.sh` header comment excluded).
- `bun install --frozen-lockfile` succeeds against the edited `bun.lock`; `make clean all` rebuilds `bin/md2x`; the smoke-test rollup target builds and `bash -n` passes on it.
- `bin/md2x` contains the Lua filter byte-identically (the new guard test), and `src/cli/lib/input-discovery.sh` is rolled in.
- New tests exist for: filter-equals-source, percent-encode over all byte values, the `md2xAsync` cap, empty `config.worktree`, `core.worktree` redirect refusal, and control-character key refusal.
- The `md2x-lookup-record` measurements are in the task report.

## Assumptions

- `make test` is green at task start; real-toolchain bats files may skip locally.
- `bash-rollup` resolves `source ./lib/*.sh` and keeps `# bash-rollup-no-recur` semantics for the Lua file; the new library follows the existing `index.sh` pattern.
- No `architectural_impact` flag: the source split adds a module, not a subsystem. Documentation updates are task 003.

## References

- `src/cli/md2x.sh`, `src/cli/lib/index.sh`, `src/cli/lib/preflight.sh`, `src/cli/lib/link-filter.sh`, `src/cli/lib/output-plan.sh`, `src/node/md2x.js`
- `AGENTS.md` (Conventions: bash 3.2 compatibility, `nounset`-safe arrays, error helpers)
- `docs/md2x-spec.md` (`--infer-version` constraints), `docs/architecture.md` (version inference)

## Checkpoint hints

- After removing the bash-toolkit dependency and converting the list calls.
- After extracting `input-discovery.sh` with the suite green.
- After the `link-filter.sh` and `output-plan.sh` efficiency changes.
- After the `md2xAsync` cap.
- After the `preflight.sh` changes and their tests.

## Status

- Outcome: succeeded (2026-10-08). The dispatch contract required a final commit, overriding this document's "do not commit".
- Validation: `make test` (369 bats cases plus 64 bun tests) and `make lint` pass; `MD2X_TEST_BASH=/bin/bash make test-cli` (bash 3.2.57) passes; `bun install --frozen-lockfile` succeeds; `make clean all` rebuilds `bin/md2x` with `input-discovery.sh` rolled in; `make test-out/visual-smoke-test.sh` builds and `bash -n` passes; the toolkit grep shows only the historical `parse-options.sh` header comment.
- Already satisfied: 32b8 item 2 (the terminator was already `MD2X_LUA_EOF` and absent from the Lua source); only the bats guard was added.
- `md2x-lookup-record` measurement (scan alone, 2 lookups per target, generated keys): 2000 targets 7.8 s (bash 5.3) / 19.7 s (bash 3.2); 4000 targets 32.4 s / 79.6 s, i.e. quadratic. Replaced with per-key variables (`md2x-plan-key-hex`, `md2x-record-set`, `md2x-record-get` in `src/cli/lib/output-plan.sh`). Whole planning for 4000 files fell from 3m41s to 3m02s on bash 5.3 (the rest is a linear per-file fork cost, filed as a finding).
- Optional `safe.directory` hint skipped: `md2x-infer-git` drops global config, so the hint would point at a setting that cannot help.
- Files: `src/cli/md2x.sh`, `src/cli/lib/{index,input-discovery,link-filter,output-plan,preflight}.sh`, `src/cli/test/manual/visual-smoke-test.sh`, `src/cli/test/bats/{work-directory,percent-encode,version-inference}.bats`, `src/node/{md2x.js,md2x.test.js,index.d.ts}`, `package.json`, `bun.lock`, `CHANGELOG.md`.

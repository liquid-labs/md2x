# Error Helper and Exit Codes

## Purpose and scope

Replace the bash-toolkit error output with a project-owned error helper. Apply the user-confirmed exit-code contract to every exit path that exists today. This is the first task in Phase 1, and every later task reports errors through this helper. No standard skill covers it; follow the role doc and the requirements below.

In scope:

- a new helper module under `src/cli/lib/`
- migrating every `echoerrandexit` call site in `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`, and `src/cli/lib/ensure-weasyprint.sh`
- the preflight exit code
- mapping tool failures to the runtime code
- the bats assertions these changes affect

Out of scope:

- The option parser. Task 003 replaces `setSimpleOptions` and its getopt errors. Until then, getopt's own unknown-option exit path stays as it is.
- The raw-error-leak sites assigned to Phase 2: the `type` output in preflight, `basename`/`dirname`, `mkdir` failures, and the `cat: package.json` noise.
- `--help` text changes. Exit codes in help are a Phase 2 item (D16).
- README and spec edits, which belong to Phase 3.

## Requirements

- `role_doc: plugins/flow/roles/developer-bash.md`
- **Helper module.** Add `src/cli/lib/errors.sh`, or a similarly named file, and source it from `src/cli/lib/index.sh`. The `Makefile` already picks up every file under `src/cli/lib/`.
  - It must provide at least four functions. Suggested names: `md2x-die-usage`, `md2x-die-runtime`, `md2x-die-dependency`, and `md2x-warn`. Each `die` function exits with its contract code.
  - Every message goes to stderr with the prefix `md2x: `. Warnings use `md2x: warning: `.
  - Color is allowed only when stderr is a TTY (`[[ -t 2 ]]`) and `NO_COLOR` is unset or empty. Off a TTY, no byte of output may be an ANSI escape.
  - The helper must not call `tput` and must not fold lines.
  - Every usage error (exit 2) ends with a one-line hint: `Try 'md2x --help' for more information.` This satisfies N2.
  - Document the exit-code contract in a comment block at the top of the module. It is the in-code source of truth:

    | Code | Meaning |
    | --- | --- |
    | `0` | success |
    | `1` | runtime or conversion failure |
    | `2` | usage error |
    | `3` | missing or unusable dependency |

    The full rules are in [the exit-code contract](../notes/design-decisions.md#exit-code-contract).
- **Remove the toolkit error import.** Remove `import echoerr` from `src/cli/md2x.sh`. After this task, no md2x source calls `echoerrandexit`, `echoerr`, `echowarn`, or `echofmt`.
  - The toolkit's `options` module still imports `echoerr`, `echofmt`, and `colors` transitively, so the rolled-up `bin/md2x` will still contain them until task 003 removes `import options`. That is expected. The requirement here is that md2x's own code never calls them.
- **Migrate existing exit paths to the contract:**
  - Unsupported `--output-format`: exit 2.
  - `--toc` together with `--no-toc`: exit 2.
  - An input argument that is neither a file nor a directory: exit 2. This is a planner decision; record it in a code comment.
  - `--title` with more than one input file: exit 2.
  - An unreadable search root (the `SEARCH_ROOT_ERROR_TMP_FILE` path): exit 1. The current message is `md2x: could not fully search …`. Drop the now-redundant inner `md2x:`, because the helper adds the prefix.
  - Missing required executable in preflight: exit 3, through the dependency helper. Keep the existing message wording, which names the binary. Leave the `type` call as it is; Phase 2 replaces it.
  - `ensure-weasyprint-fail`, `ensure-weasyprint-lock-timeout-fail`, and `ensure-weasyprint-lock-mkdir-fail`: exit 3.
    - Keep their existing multi-line remediation text.
    - They may keep printing their own lines, but the final exit must be 3.
    - Update their header comments, which say "the same code the preflight loop uses".
- **Tool failures exit 1.** Today a failing `pandoc`, `gs`, `pdftk`, or TOC preprocessor exits with that tool's own status through `errexit`. For example, a stub exit of 64 makes md2x exit 64.
  - Make each of these failures exit 1, with one `md2x: ` line that names the failed tool and the input file.
  - Do not suppress or reword the tool's own stderr. Phase 2 owns leak cleanup.
  - Suggested approach: guard each tool invocation with `|| md2x-die-runtime …`. As a backstop, have the existing `EXIT` trap normalize any status outside 0 to 3 to 1. Later tasks rewrite that trap and must keep any such normalization; say so in a code comment.
- **Update the bats suite** to the contract:
  - `exit-codes.bats`: missing `pandoc` and `gs` now exit 3. Update the cases that only assert failure to assert the specific code.
  - `harness-smoke.bats`: the `md2x_path_without` case asserts 2 today and must assert 3. Also update the comment on `md2x_path_without` in `src/cli/test/helpers/common.bash`, which says "exit status 2".
  - `weasyprint-bootstrap-locking.bats`: the three failure functions assert 3.
  - `output-format.bats`, `toc-flags.bats`, `title-precedence.bats`, and `pandoc-stream-handling.bats`: assert the specific contract code instead of a bare `assert_failure`.
- **Add regression cases**, in `exit-codes.bats` or a new `error-output.bats`. Each must fail on the pre-change code:
  - Off a TTY (bats is never a TTY), a usage error's stderr contains no `ESC` byte (`$'\033'`).
  - Error lines start with `md2x: `.
  - A usage error prints the `md2x --help` hint.
  - With the pandoc stub driven by `MD2X_TEST_STUB_EXIT_CODE=64`, md2x exits 1, not 64.
  - TTY color is not exercised by bats. Check it manually, and report the manual check.
- The code must stay bash 3.2-compatible: no associative arrays, no `${var,,}`, and no `mapfile`. Task 002 adds the 3.2 harness override.

## Validation

- `make qa` passes: bats, `bun test`, and lint.
- Every new regression case fails against the pre-change `bin/md2x` and passes after the change. Confirm this by running the new cases against a build of the parent commit, and say so in the report.
- `grep -rn "echoerrandexit\|echoerr \|echowarn\|echofmt" src/cli/md2x.sh src/cli/lib/` returns nothing.
- `grep -n "exit 2" src/cli/lib/ensure-weasyprint.sh` returns nothing.
- `grep -rn "assert_failure$" src/cli/test/bats/` returns only cases where any non-zero status is intended. Justify each remaining one in the report.
- Manual: `bin/md2x --toc --no-toc x.md` in a terminal shows color, and `NO_COLOR=1 bin/md2x --toc --no-toc x.md` does not. Both exit 2.
- The report lists every exit path changed, with its old and new code.

## Metadata

architectural_impact: true

## Assumptions

- The project root has the plan branch checked out, and `bun install` has been run, so `node_modules/.bin/bats` and `bash-rollup` exist.
- `/bin/bash` is 3.2 on this host, and the CLI does not yet run under it (B4). Task 002 fixes that. This task validates under the default bash only.
- `bin/md2x` still contains the toolkit's `tput` color setup, through `import options`. Its removal is task 003's validation, not this task's.

## References

- [Design decisions: exit-code contract](../notes/design-decisions.md#exit-code-contract) and [error output](../notes/design-decisions.md#error-output).
- [Exit-code answer](../notes/exit-code-contract-answer.md): the user's binding acceptance of 0/1/2/3.
- [Followup verification](../notes/followup-verification.md): the three `ensure-weasyprint` failure functions move to exit 3.
- [Sequencing and file ownership](../notes/sequencing-and-file-ownership.md): `md2x.sh` is a hot file, and Phase 1 is a serial chain.
- `node_modules/@liquid-labs/bash-toolkit/dist/ui/echoerr.func.sh` and `echofmt.func.sh`: the toolkit behavior being replaced.

## Checkpoint hints

- After the helper module exists and is sourced.
- After `md2x.sh` and `ensure-weasyprint.sh` call sites are migrated.
- After tool-failure mapping and the bats updates.

# Bash 3.2 Compatibility

## Purpose and scope

Fix B4: md2x under macOS `/bin/bash` 3.2 dies with a parse error and still exits 0, with no output. Make the CLI run correctly under bash 3.2 and newer. Reject non-bash shells and too-old bash with exit 3. Give the bats harness an interpreter override, so the whole suite can run under a chosen bash. No standard skill covers this; follow the role doc and the requirements below.

This task comes early in the Phase 1 chain on purpose. From here on, every task validates under the override, so the new option parser (task 003) and later work are written against 3.2 from the start.

In scope:

- `src/cli/md2x.sh`
- `src/cli/lib/*.sh`
- `src/cli/test/helpers/common.bash`
- `harness-smoke.bats`, plus a new bats file for the guard

Out of scope:

- The toolkit option parser, which task 003 replaces. It only needs to keep working under 3.2 until then.
- CI wiring, which belongs to Phase 3.
- README and spec text about the bash floor, also Phase 3.

## Requirements

- `role_doc: plugins/flow/roles/developer-bash.md`
- **Reproduce first.** Run the built CLI with `/bin/bash bin/md2x -F html t.md` in a scratch directory.
  - Before this task it prints `bad substitution: no closing ')' in <(` and exits 0.
  - The planner reproduced this on 2026-10-04. The cause is the apostrophes in full-line comments inside the `< <( … )` file-discovery process substitution, at the end of `src/cli/md2x.sh`.
- **Remove the parse hazard.** No comment containing a `'` may sit inside a `$( … )` or `<( … )` body anywhere in `src/cli/`. Moving the explanatory comments above the construct is sufficient. Restructuring the discovery into a function is also acceptable.
- **`nounset`-safe empty arrays.** Bash before 4.4 treats `"${ARR[@]}"` on an empty array as unbound under `set -o nounset`.
  - Expand every array that can be empty with `${ARR[@]+"${ARR[@]}"}`. `INCLUDE_BODY_ARGS` in `generate-page.sh` is the known case; DOCX conversion trips it.
  - Audit every other array expansion under `src/cli/` for the same hazard.
- **Failure propagation from the main loop.** The live experiment showed that a failure inside the `{ … } < <( … )` conversion loop can end the script with exit 0 under 3.2.
  - Make any failure inside that loop, or in a function it calls, exit non-zero under every supported bash.
  - Use task 001's helper and codes: a conversion failure exits 1.
  - Investigate why 3.2 exits 0 and record the explanation in a code comment. Fix the underlying behavior rather than a symptom.
- **POSIX guard.** Add a guard at the very top of `src/cli/md2x.sh`, ahead of the strict-mode `set` lines and every `import`/`source`.
  - Write it in POSIX `sh` syntax only, so `dash` can parse and run it.
  - It rejects a shell that is not bash, and bash older than 3.2, using `BASH_VERSION`/`BASH_VERSINFO`.
  - It prints one `md2x: ` line naming the requirement (bash 3.2 or later) and exits 3.
  - Bash in POSIX mode, as when the script is run with macOS `sh`, cannot run the script either: process substitution is unavailable there in bash 3.2. The guard must reject it with exit 3 and a message saying to run it with bash.
  - Bash parses and runs top-level commands one at a time, so the guard runs before any later syntax `dash` cannot parse. Confirm that in `bin/md2x`, after rollup, the guard still comes before all inlined toolkit code.
- **Harness interpreter override.** In `src/cli/test/helpers/common.bash`, add an override variable, `MD2X_TEST_BASH` (for example `MD2X_TEST_BASH=/bin/bash`). When it is set, `md2x_run` runs the CLI under that interpreter: `"${MD2X_TEST_BASH}" "${MD2X_BIN}" …`.
  - Document it in the file's header comment.
  - Add a `harness-smoke.bats` case that proves the override is honored, for example by pointing it at a recording wrapper script that logs and then `exec`s the real bash.
  - Keep the stubs runnable as they are. They already claim 3.2 compatibility.
  - Running the suite under the override must be a one-liner: `MD2X_TEST_BASH=/bin/bash make test-cli`, or an equivalent bats invocation. Adding a `Makefile` target is optional. Say in the report whether one was added, because Phase 2 and 3 tasks also edit the `Makefile`.
- **Regression tests.** Each must fail on the pre-change code.
  - New `src/cli/test/bats/bash-compat.bats`, or similar:
    - Under `/bin/dash` or `dash` (skip when absent), the CLI exits 3 with the bash-requirement message.
    - Running the script under bash in POSIX mode (`bash --posix`, or `sh` where `sh` is bash) exits 3.
    - When `/bin/bash` is 3.x, or `MD2X_TEST_BASH` names a 3.x bash: an HTML conversion and a DOCX conversion succeed, and their output files exist.
    - A forced pandoc stub failure exits non-zero, specifically 1.
  - The whole existing suite passes under `MD2X_TEST_BASH=/bin/bash`.
- All new and changed shell code must avoid features newer than 3.2:
  - associative arrays
  - `${var,,}`/`${var^^}`
  - `mapfile`/`readarray`
  - negative array indices
  - `[[ -v ]]`
  - `printf -v` with array elements
  - `;&`/`;;&`

## Validation

- `make qa` passes under the default bash.
- `MD2X_TEST_BASH=/bin/bash` bats passes the full suite, with `/bin/bash` 3.2.57 on this host. The report includes the pass count from both runs.
- `/bin/bash bin/md2x -F html t.md` and `/bin/bash bin/md2x -F docx t.md` in a scratch directory exit 0 and produce output.
- `/bin/dash bin/md2x --help` exits 3 with the guard message.
- The new regression cases fail against the pre-change build. Confirm this and report it.
- `grep -n "\[@\]}" src/cli/md2x.sh src/cli/lib/*.sh` shows only `+`-guarded expansions, or arrays proven non-empty. Justify the latter in the report.
- `head` of `bin/md2x` shows the guard before any toolkit code.

## Metadata

architectural_impact: true

## Assumptions

- Task 001 is complete. Exit codes and the error helper exist.
- The toolkit option parser still runs at load time and still calls `brew --prefix` on macOS. The planner's live experiment showed `--help` and HTML working under 3.2 once the comment hazard was gone, so it should not block this task.
- Bash older than 3.2 cannot practically be tested. The version comparison in the guard is checked by inspection.

## References

- [Design decisions: bash version support](../notes/design-decisions.md#bash-version-support): the five-step work list and the live-experiment results.
- `.flow/audit-interface.md` B4, under the project root: the original reproduction.
- `src/cli/test/helpers/common.bash`: the harness, including `md2x_run` and the passthrough tools.

## Checkpoint hints

- After the parse hazard and array fixes, when `/bin/bash bin/md2x` converts HTML and DOCX.
- After the POSIX guard.
- After the harness override and the new bats file.

## Status

Outcome: succeeded (2026-10-04).

- Parse hazard removed by moving the file-discovery body into `md2x-list-inputs()` in `src/cli/md2x.sh`; the `< <(md2x-list-inputs)` body holds no comment.
- `INCLUDE_BODY_ARGS` in `src/cli/lib/generate-page.sh` is expanded with the `[@]+` guard; it was the only array expansion under `src/cli/`.
- Silent exit 0 under bash 3.2: a fatal `nounset` error reaches the `EXIT` trap with `$?` equal to 0 in 3.2, and the trap's own status then becomes the script's. Fixed with a `MD2X_COMPLETED=true` sentinel as the script's last line; the trap exits 1 when it sees status 0 without it. Explained in a comment above the trap.
- POSIX `sh` guard added at the top of `src/cli/md2x.sh` (exit 3 for non-bash, bash older than 3.2, and bash in POSIX mode); it sits before `set` and all inlined toolkit code in `bin/md2x`.
- `MD2X_TEST_BASH` override and a new `md2x_exec` helper in `src/cli/test/helpers/common.bash`; `weasyprint-bootstrap-locking.bats` now launches the CLI through `md2x_exec`. No Makefile change: `MD2X_TEST_BASH=/bin/bash make test-cli` works as is.
- Tests: new `src/cli/test/bats/bash-compat.bats` (9 cases) and one override case in `harness-smoke.bats`.
- Validation: `make qa` passes (159 bats cases); `MD2X_TEST_BASH=/bin/bash make test-cli` passes (159 cases, bash 3.2.57). Against the pre-change build, 8 of the 9 new cases fail under either interpreter setting; the ninth ("any bash: a failing pandoc exits 1") fails only under the 3.2 override.

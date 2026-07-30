# Pin Down And Document Find-Pipe Abort Semantics

## Purpose and scope

Closes followup `8ZmD`. `src/cli/md2x.sh`'s file-discovery process substitution (near the bottom of the file, feeding the main conversion loop) nests a per-root inner pipe:

```bash
while IFS= read -r ROOT_DIR; do
  [[ -n "${ROOT_DIR}" ]] || continue
  find "${ROOT_DIR}" -name "*.md" | while IFS= read -r FOUND_FILE; do
    printf '%s\t%s\n' "${FOUND_FILE}" "${ROOT_DIR}"
  done
done <<< "${SEARCH_DIRS}" | sort
```

inside the outer `for-loop | sort` pipe, itself inside a `< <(...)` process substitution feeding the script's main conversion loop. Under the script's `set -o errexit -o pipefail`, a `find` failure on one search root (e.g. an unreadable directory) now surfaces differently than the pre-fix code's immediate abort — the exact abort-or-continue behavior at this specific nesting (pipe status propagation through `pipefail`, and how a process-substitution subshell's early exit interacts with the parent script's `errexit`) is not obvious from reading alone and needs to be observed empirically. This task does **not** change behavior — it establishes and documents what the current behavior actually is, and adds a targeted regression test that pins it down (so a future refactor can't silently change it without a test failing).

## Requirements

- Empirically determine the current behavior: run the built CLI (or a scratch script mirroring this exact pipe structure) against a search-root directory that exists but is unreadable (e.g. `chmod 000` on a directory containing at least one `.md` file, or simply unreadable itself) alongside at least one other, readable search root or directly-named file, and observe:
  - Does the whole script abort (non-zero exit, no output files produced for any root), or does it continue processing the other, readable roots/files with only the unreadable root's files missing from the result?
  - What exit code and stderr output result?
  - Does any already-discovered file from the *same* failing root (files `find` emitted before hitting the permission error) still get processed, or is that root's contribution silently dropped entirely?
- Add a one-line (or short, a few lines if needed for clarity) comment in `src/cli/md2x.sh` at the site of the nested `find | while` pipe, documenting the abort-or-continue behavior you observed and *why* (in terms of `pipefail`'s "last command with non-zero exit" rule and how the process-substitution subshell's exit status does or doesn't propagate to the parent script's `errexit`) — so a future reader doesn't have to re-derive this from scratch.
- Add a targeted bats case (a new case in `src/cli/test/bats/exit-codes.bats` is the natural fit — it already covers non-zero-exit behavioral contracts; `src/cli/test/bats/mirrored-output-paths.bats` is a reasonable alternative if you judge the file-discovery framing fits better there) that:
  - Creates an existing-but-unreadable search-root directory (`mkdir` + `chmod 000`, or `chmod a-r` — pick whichever reliably denies `find` on this repo's CI/dev environment) alongside at least one other readable source.
  - Runs `md2x` against both.
  - Asserts on whatever the actually-observed behavior is (exit code, which output files do or don't exist, stderr content) — the test's job is to pin down current behavior, not to assert a "should be" behavior invented for this task.
  - Guards against running as `root` (which can read a mode-000 directory, making the test vacuously pass/fail differently): skip the case with a clear message if `(( $(id -u) == 0 ))`, following the pattern `src/cli/test/helpers/common.bash`'s `md2x_path_without` uses for its own "fail loudly rather than silently no-op" guard.
  - Clean up the unreadable directory's permissions in `teardown` (or before the test ends) so bats' own temp-directory removal doesn't fail on a mode-000 directory it can't delete into.

## Validation

- `make test` passes, including the new bats case.
- The comment added to `src/cli/md2x.sh` accurately reflects the behavior the new bats case asserts (no drift between the prose explanation and the test's actual assertions).
- `grep -rn "8ZmD" plan/followups.yaml` — confirm the id no longer appears after this task's report is applied (report the resolved id; removal is the manager's step via `followups_remove`).

## Assumptions

- No functional change to the abort/continue behavior is expected or required — if your empirical testing reveals a behavior that seems clearly wrong or dangerous (e.g. silent data loss with a zero exit code), stop and flag it in your task report rather than fixing it unilaterally; this task's scope is documentation and test coverage, not a behavior change.

## References

- `src/cli/md2x.sh` — the file-discovery process substitution near the end of the file (search for `find "${ROOT_DIR}"`).
- `src/cli/test/bats/exit-codes.bats` — likely home for the new bats case.
- `src/cli/test/helpers/common.bash` — `md2x_path_without`'s "fail loudly on a silent no-op" pattern, useful as a model for the root-user guard.
- `plan/followups.yaml` item `8ZmD` — full original followup text.

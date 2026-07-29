# Fix Mirrored Output Path Derivation

## Purpose and scope

Fix followup `aI57`: the non-`--flatten-dirs` (mirrored-output) branch of `src/cli/md2x.sh` derives its output subdirectory with `REL_DIR=$(dirname "${MD_FILE#*/policy/}")`, a hardcoded `/policy/` substring strip left over from another project's directory convention. For any input path without a `/policy/` segment the strip silently no-ops and the output mirrors the input's **entire** path instead of its path relative to the search root it was found under.

Replace it with the general contract, and land the regression cases that are red against the current implementation and green after the change. Both halves are this task's — the fix must not merge without its own test coverage.

No standard skill covers this; the [Requirements](#requirements) section below is the procedure.

Read [the mirrored output path contract note](../notes/mirrored-output-path-contract.md) in full before starting: it holds the verified current-behaviour table, the intended contract with worked examples, every edge case that must be settled, and the fail-before/pass-after cases.

## Requirements

### The fix

1. Without `--flatten-dirs`, each output file is written under `--output-path` at the path the input file occupies **relative to the search root it was found under**, where the search root is the directory argument given on the command line for files found by the recursive `*.md` search, or the input file's own directory for a file named directly on the command line (so a directly-named file always lands directly in `--output-path`).
2. The search root must be **carried through** the file-discovery pipeline. Today `< <(echo "${MD_FILES}"; for ROOT_DIR in $SEARCH_DIRS; do find ${ROOT_DIR} -name "*.md"; done | sort)` flattens every root into one stream, so by the time the loop reads a path the root is gone. The contract note sketches a tab-separated root/file record approach; any equivalent structure is acceptable provided it preserves the existing ordering (directly-named files first, then sorted `find` results) and keeps the existing `[[ -n "${MD_FILE}" ]] || continue` empty-line guard working.
3. Settle the edge cases enumerated in the contract note: trailing slashes on a directory argument, `.` and `./`-prefixed roots, absolute roots, a relative path of `.`, and — importantly for assertions — **no `/./` segment may appear in the path md2x prints** in its `Created …` / `--list-files` output.
4. Also `mkdir -p` the output path in the `--flatten-dirs` branch. Today `mkdir -p` runs only in the mirroring branch, so `md2x -D -p out …` fails when `out` does not exist. This is one line and is squarely within "output placement is correct".
5. `--single-page` and stdin (`-`) do not pass through this branch and must be unaffected: both still write exactly `${OUTPUT_PATH}/${TITLE}.${OUTPUT_FORMAT}`.
6. Do not repair the CLI's pre-existing unquoted word-splitting (paths with spaces). Do not add, rename, or change any flag.

### The regression tests

Add bats cases (following the harness conventions task 001 landed — read the existing files under `src/cli/test/` first) covering, at minimum, the five cases in the contract note's fail-before/pass-after section:

1. `md2x --output-path out docs` over a `docs/guide/b.md` fixture produces `out/guide/b.pdf`.
2. `md2x --output-path out ./docs` produces `out/guide/b.pdf`, with no `/./` in the reported path.
3. `md2x --output-path out docs/guide/b.md` produces `out/b.pdf`.
4. `md2x --output-path out --flatten-dirs docs` produces `out/b.pdf` and succeeds when `out` does not already exist.
5. Control: `md2x --output-path out --single-page --title Combined docs` still produces exactly `out/Combined.pdf`.

Also cover a multi-root invocation (`md2x -p out docs notes`, each root resolved against itself), a trailing-slash root, and a root of `.`.

**Before changing `src/cli/md2x.sh`, run the new cases against the unmodified CLI and record which ones fail.** Report that pre-fix failure list — it is the evidence that the coverage is real. Cases 1–4 must fail before and pass after; case 5 must pass both times.

### Documentation and followup

- Remove the "Known issues" bullet in `AGENTS.md` that points at followup `aI57`. If that leaves the section empty, remove the section heading too.
- Check the `--flatten-dirs` row in `README.md`'s CLI reference and the corresponding row plus UC3 in `docs/md2x-spec.md`. They already describe mirroring correctly at a high level; if the fixed semantics ("relative to the search root it was found under") can be stated more precisely in a phrase or two without restructuring, do it. Anything larger is Phase 02's job — leave it and say so in your report.
- **Do not edit `plan/followups.yaml`.** Per the plan-documents handling protocol, followup removal is the manager's, via the `followups_remove` MCP command. State clearly in your task report that this task resolves followup `aI57` so the manager removes it when applying the report.

## Validation

- The pre-fix run of the new cases is recorded, and cases 1–4 are among the failures.
- After the fix, `make test` passes in full with a zero exit status, non-interactively.
- Each worked example in the contract note's "Worked examples" table produces the stated output paths — verify by hand at least the `md2x -p out .` and multi-root rows if they are not all covered by automated cases.
- `grep -rn 'policy' src/` returns no hit (the hardcoded strip is gone, with no replacement leftover).
- `grep -rn 'aI57' AGENTS.md` returns nothing; `plan/followups.yaml` is unmodified (`git status` shows it untouched).
- `--single-page` and stdin behaviour is unchanged: the control case passes, and a `printf '# T\n' | md2x -p out -` invocation still writes `out/output.pdf`.
- `make lint` and `make qa` pass.
- `bash -n src/cli/md2x.sh` parses cleanly, and `make all` regenerates `bin/md2x` without error.

## Assumptions

- Task 001 has landed: the bats harness, the stub `pandoc`/`gs`/`pdftk` executables, the shared helpers, and the `make test` wiring all exist. Read the landed files and follow their conventions rather than inventing new ones.
- The bulk of the suite runs against stub external binaries, so PDF-format cases work without a functioning Pandoc PDF engine (which this machine does not have).
- Every case runs in a temp working directory outside the repo, which makes the CLI's version probe deterministically resolve to `working`.
- Tasks 003, 004, and 005 may be running in parallel. They own no part of `src/cli/md2x.sh` and assert no mirrored-output paths; if you find a conflicting assertion after merge, it is yours to reconcile.

## References

- [Mirrored output path contract](../notes/mirrored-output-path-contract.md) — the verified analysis, contract, edge cases, and test cases. Primary reference for this task.
- [Test tooling survey](../notes/test-tooling-survey.md) — harness conventions and determinism hazards.
- `src/cli/md2x.sh` lines 113–132 (source-list resolution), 149–182 (the loop and the file-discovery process substitution), 161–167 (the defect).
- `docs/md2x-spec.md` UC3 — the spec statement of the mirroring requirement.
- `README.md` — the consumer-facing `--flatten-dirs` description.
- `AGENTS.md` "Known issues" — the bullet to remove.

## Checkpoint hints

- After writing the regression cases and recording their pre-fix failures.
- After the `src/cli/md2x.sh` change makes them pass.
- After the `AGENTS.md` (and any minimal README/spec) wording updates.

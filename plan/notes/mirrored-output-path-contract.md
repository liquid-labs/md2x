# Mirrored Output Path Contract

## Purpose and scope

The analysis behind followup `aI57` and the intended contract the fix must implement: what the current code does, why it is wrong, the exact semantics the fixed code must satisfy, the edge cases that must be decided rather than discovered, and the fail-before / pass-after test cases that pin the fix down.

## The defect

`src/cli/md2x.sh` lines 161–167, inside the per-file loop:

```bash
BASE_OUTPUT="${OUTPUT_PATH}"
[[ -n "${FLATTEN_DIRS}" ]] || {
  REL_DIR=$(dirname "${MD_FILE#*/policy/}")
  BASE_OUTPUT="${BASE_OUTPUT}/${REL_DIR}"
  mkdir -p "${BASE_OUTPUT}"
}
BASE_OUTPUT="${BASE_OUTPUT}/${TITLE}"
```

`${MD_FILE#*/policy/}` strips the shortest prefix ending in `/policy/` — a leftover from a different project's directory convention. For any input path with no `/policy/` segment the expansion silently no-ops and `REL_DIR` becomes the *entire* directory portion of the input path, so the output tree mirrors the input's full path rather than its path relative to the root it was found under. Verified behaviour with a `docs/guide/a.md` fixture and `--output-path out`:

| Invocation | Current `BASE_OUTPUT` | Intended |
| --- | --- | --- |
| `md2x -p out docs` | `out/docs/guide/a.pdf` | `out/guide/a.pdf` |
| `md2x -p out ./docs` | `out/./docs/guide/a.pdf` | `out/guide/a.pdf` |
| `md2x -p out docs/guide/a.md` | `out/docs/guide/a.pdf` | `out/a.pdf` |

The second row also shows a cosmetic consequence that matters for tests: a `/./` segment leaks into the path md2x prints in its `Created …` / `--list-files` output.

There is a structural cause, not just a bad expansion. The file stream is built at line 182:

```bash
< <(echo "${MD_FILES}"; for ROOT_DIR in $SEARCH_DIRS; do find ${ROOT_DIR} -name "*.md"; done | sort)
```

By the time the loop reads a path, **the search root it came from is gone**. Any correct fix has to carry the root through the pipeline (or compute the relative path before the paths are flattened into one stream).

## Intended contract

Without `--flatten-dirs`, each output file is written under `--output-path` at the path the input file occupies **relative to the search root it was found under**, where the search root is:

- the directory argument given on the command line, for files discovered by the recursive `*.md` search; or
- the input file's own directory, for a file named directly on the command line (so a directly-named file always lands directly in `--output-path`).

With `--flatten-dirs`, every output file is written directly into `--output-path`, discarding structure — unchanged from today.

`--single-page` and stdin (`-`) do not go through this branch at all: both already write a single `${OUTPUT_PATH}/${TITLE}.${OUTPUT_FORMAT}`. The fix must not change that.

### Worked examples

Fixture tree: `docs/a.md`, `docs/guide/b.md`, `notes/c.md`.

| Invocation | Outputs |
| --- | --- |
| `md2x -p out docs` | `out/a.pdf`, `out/guide/b.pdf` |
| `md2x -p out ./docs/` | `out/a.pdf`, `out/guide/b.pdf` (trailing slash and `./` are immaterial) |
| `md2x -p out -D docs` | `out/a.pdf`, `out/b.pdf` |
| `md2x -p out docs/guide/b.md` | `out/b.pdf` |
| `md2x -p out docs notes` | `out/a.pdf`, `out/guide/b.pdf`, `out/c.pdf` (each root resolved against itself) |
| `md2x -p out .` (from the fixture root) | `out/docs/a.pdf`, `out/docs/guide/b.pdf`, `out/notes/c.pdf` |
| `md2x docs/guide/b.md` (default `-p .`) | `./b.pdf` |

### Edge cases the fix must settle

- **Trailing slashes.** `docs/` must behave as `docs`; strip trailing `/` from the root before deriving the relative path.
- **`.` and `./` prefixes.** A root of `.` yields `find`-produced paths like `./docs/a.md`; the relative path must come out as `docs/a.md`, not `./docs/a.md`. No `/./` segment may survive into the printed path.
- **Relative directory root, absolute file (or vice versa).** Roots and found paths always share a form today because `find` echoes the root as given, so string-relative computation is sufficient — but the fix must not produce a wrong answer if a root is absolute (`/abs/docs` + `/abs/docs/guide/b.md` → `guide/b.md`).
- **Relative path of `.`** (file sits directly in the root, or the file was named directly). The output path must be `${OUTPUT_PATH}/<name>.<fmt>` with no `/./` and no trailing `/.`.
- **Overlapping roots** (`md2x docs docs/guide`) already convert the same file twice today; the fix need not deduplicate, but must not crash. Leave behaviour as-is and do not test it.
- **The `--flatten-dirs` branch never creates `--output-path`.** `mkdir -p` runs only in the mirroring branch, so `md2x -D -p out …` fails when `out` does not exist. Fix this too — it is one line and it is squarely "output placement is correct".
- **Blank line in the stream.** `echo "${MD_FILES}"` emits an empty line when no files were named directly; the existing `[[ -n "${MD_FILE}" ]] || continue` guard must keep working with whatever record format the fix introduces.
- **Word-splitting.** Paths with spaces are already broken (`for ROOT_DIR in $SEARCH_DIRS`, unquoted `find ${ROOT_DIR}`). The fix is not required to repair that; it must not make it worse, and no test should assert on space handling.

### Implementation sketch (non-binding)

Emit root/file records rather than bare paths, e.g. one tab-separated record per file where the first field is the search root and an empty first field means "use the file's own directory":

```bash
< <(
    while read -r F; do [[ -z "$F" ]] || printf '\t%s\n' "$F"; done <<< "${MD_FILES}"
    for ROOT_DIR in $SEARCH_DIRS; do find ${ROOT_DIR} -name "*.md"; done | sort | ...
  )
```

and read with `IFS=$'\t' read -r SEARCH_ROOT MD_FILE`. Any equivalent structure is fine; what matters is that the loop knows the root, that the existing sort order (directly-named files first, then sorted find results) is preserved, and that the empty-line guard still holds.

## Fail-before / pass-after cases

These are the cases that must be red against the current implementation and green after the fix — the direct regression coverage the change request asks for:

1. `md2x --output-path out docs` over `docs/guide/b.md` produces `out/guide/b.pdf`. *(Before: `out/docs/guide/b.pdf`.)*
2. `md2x --output-path out ./docs` produces `out/guide/b.pdf` with no `/./` segment in the reported path. *(Before: `out/./docs/guide/b.pdf`.)*
3. `md2x --output-path out docs/guide/b.md` produces `out/b.pdf`. *(Before: `out/docs/guide/b.pdf`.)*
4. `md2x --output-path out --flatten-dirs docs` produces `out/b.pdf` — and succeeds when `out` does not already exist. *(Before: the placement was already right, but the run failed on a missing `out`.)*
5. A control case: `md2x --output-path out --single-page --title Combined docs` still produces exactly `out/Combined.pdf`.

## Followup resolution

Landing this fix resolves followup `aI57` in `plan/followups.yaml` on the working branch. Per the plan-documents handling protocol, the implementing task **must not** edit `followups.yaml` itself — it reports the resolution so the manager removes the item via the `followups_remove` MCP command when applying the task report. `AGENTS.md`'s "Known issues" section, which points at `aI57`, *is* the implementing task's to update.

## Related documents

- [`docs/md2x-spec.md`](../../docs/md2x-spec.md) — UC3 states the mirroring requirement the fix implements.
- [`README.md`](../../README.md) — the `--flatten-dirs` row states the same contract from the consumer side.
- [Test tooling survey](./test-tooling-survey.md) — the harness and stub strategy the regression tests are written against.

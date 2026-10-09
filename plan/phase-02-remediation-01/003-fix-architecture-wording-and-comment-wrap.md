# Fix Architecture Doc Wording And Re-Wrap Scan-Keys Comment

## Purpose and scope

Resolves findings `wheq` and `SJUO` of this plan. The work targets the plan branch `plan/release-followups-polish` and lands through the ordinary per-task loop. Files: `docs/architecture.md` and the comment block of `md2x-infer-scan-keys` in `src/cli/lib/preflight.sh` (comment lines only).

## Requirements

1. `docs/architecture.md`, Key decision "Version inference is lazy, config-allowlisted, and hardened" (around line 194): the ungrammatical clause reads "...and runs `git status` only when every key is on a short allowlist of harmless ones".
2. `docs/architecture.md`, "Output planning and collision checks" (around line 113), gains one sentence: collision records are one shell variable per key (`md2x-plan-key-hex`, `md2x-record-set`, `md2x-record-get` in `output-plan.sh`), so a lookup takes constant time, because bash 3.2 has no associative arrays.
3. The `md2x-infer-scan-keys` header comment in `src/cli/lib/preflight.sh` (around lines 125-131) is re-wrapped to the file's existing comment width, with no wording or code change.

## Validation

1. `grep -n 'gates only' docs/architecture.md` returns nothing, and the new sentence names the three helpers.
2. No line in the preflight.sh comment block at around lines 124-131 is longer than the neighbouring comment lines (about 90 columns).
3. `make test` and `make lint` pass. The diff of `preflight.sh` changes comment lines only.

## References

- Findings `wheq` and `SJUO` in this plan's `plan/findings.yaml`.
- `plan/phase-01-followup-polish/003-update-docs.md`.

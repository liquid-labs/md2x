# Psgq Slug Probe Optimization

## Purpose and scope

Fix followup `psgq`: `allocate_slug(base, used)` in `src/cli/lib/toc-preprocess.py` restarts its `-1`, `-2`, ... probe from 1 on every call, which is O(d^2) for d duplicate headings. Make the probe O(1) amortized with byte-identical output. Touches only `src/cli/lib/toc-preprocess.py` and `src/cli/test/bats/toc-preprocess.bats`.

Parallel-eligible: no dependency on other Phase 3 tasks.

## Requirements

- Keep a per-base "next probe index" map alongside `used` (for example a dict passed through, or owned by the caller at the call site near line 409). Each probe must still check membership in `used`, because a literal heading such as `foo-1` can already occupy a candidate slug.
- Output must stay byte-identical to today's for all inputs, preserving Pandoc slug parity. Capture before/after TOC output for a corpus (the existing fixtures plus a heading set with `foo`, `foo`, `foo-1`, `foo`, `foo-1`, `foo-2`) and compare.
- Add a bats case with many duplicate headings (for example 2000 identical headings) that asserts the expected last slugs (`foo-1999`) and completes quickly; also add a collision-interleaving case where literal `foo-1` headings sit among duplicates.
- Do not change the script's CLI or anything outside the two files. `bin/md2x` is rebuilt by `make all`, which inlines `src/cli/lib`.
- Python code must stay compatible with the `python3` versions md2x already supports (no newer syntax than the file already uses).

## Validation

- `make qa` passes, including the existing 35 `toc-preprocess.bats` cases plus the new cases.
- Run the new many-duplicates case against the old implementation (`git stash` or a copy) and confirm the output is identical and that timing improves (report both numbers); the interleaving case passes on both old and new.
- A before/after diff of TOC output on the corpus is empty.
- `git diff --stat` shows only the two named files.
- Real-toolchain e2e (`real-toolchain-e2e.bats`) still passes where the toolchain is present.

## Metadata

architectural_impact: false

## Assumptions

- The followup `psgq` stays open until the manager closes it; the task report should say the fix is complete so the manager can close it (do not edit `followups.yaml`).

## References

- [Followup verification, psgq](../notes/followup-verification.md)
- [Audit coverage](../notes/audit-coverage.md): row R8.

## Status

Succeeded 2026-10-05. `allocate_slug` now takes an optional `next_probe` dict (base -> next suffix) owned by `build_output`; each probe still checks `used`. Files: `src/cli/lib/toc-preprocess.py`, `src/cli/test/bats/toc-preprocess.bats` (2 new cases, 37 total). Old vs new output byte-identical on the slug corpus, tiny-doc, 2000-duplicate and interleaved documents. 2000 duplicates: old 0.17s, new 0.02s. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` pass; real-toolchain e2e passes (15/15).

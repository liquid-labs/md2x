# Followup Verification

## Purpose and scope

Records the verification status of the two open project followups the user folded into this plan: `zwH4` and `psgq`.

## zwH4 — WeasyPrint lock failure misdiagnosis

**Status: already fixed. Verified 2026-10-04. Closed by the manager; not re-implemented.**

- `src/cli/lib/ensure-weasyprint.sh` now tells a contended lock apart from a persistent `mkdir` failure. After a failed `mkdir "${WEASYPRINT_LOCK_DIR}"`, the loop checks `[[ -d "${WEASYPRINT_LOCK_DIR}" ]]`. If the directory does not exist, it calls `ensure-weasyprint-lock-mkdir-fail`. That function fails fast with exit 2, names an unwritable `$HOME`, a full disk, or permissions as the likely cause, and deliberately does not recommend `rm -rf` of the lock.
- The fix landed in commit `35c8d54` ("Fix weasyprint lock loop to fail fast on non-contention mkdir failures"). That commit is on `main`.
- A regression test exists: `src/cli/test/bats/weasyprint-bootstrap-locking.bats`, case "a persistent mkdir failure (not contention) fails fast without recommending 'rm -rf'".
- Plan impact: Phase 1 changes the dependency-failure exit code (see [design decisions](./design-decisions.md#exit-code-contract)). That task must update `ensure-weasyprint-fail`, `ensure-weasyprint-lock-timeout-fail`, and `ensure-weasyprint-lock-mkdir-fail` and their bats assertions to the new code. Nothing else is needed.
- The manager has closed `zwH4` against commit `35c8d54`.

## psgq — toc-preprocess slug collision probe O(d²)

**Status: open; in scope (Phase 3, nice-to-have).**

- `allocate_slug(base, used)` in `src/cli/lib/toc-preprocess.py` restarts its `-1`, `-2`, … probe from 1 on every call.
- Fix: keep a per-base "next probe index" map alongside `used`. Each probe still checks `used`, because a literal heading can already occupy `foo-1`. Output must stay byte-identical to today's, which preserves Pandoc parity. The existing 35 `toc-preprocess.bats` cases plus a new many-duplicates case are the guard.
- This touches only `toc-preprocess.py` and its bats file, so it can run in parallel with any task that does not edit that file.

# Plan Summary: followup-remediation

## What was planned and why

This plan closed 7 already-decided followup items recorded in `plan/followups.yaml`, on the
working branch `2026-07-29-weasyprint` (which already carried 8 prior fix-batches — not
greenfield work, and nothing here was evaluated against `master`). Each item had a final,
maintainer-approved fix direction reached through a prior `AskUserQuestion` round; no further
deliberation on tradeoffs was in scope for this session. The plan was deliberately single-phase:
every task touched one coherent, already-scoped area of the codebase, no task depended on research
or design output not already in hand, and the full task breakdown was complete up front. All 7
tasks were parallel-eligible (no task's implementation depended on another task's code output),
with two documented, non-blocking caveats around test-fixture overlap (tasks 001/006) and
doc-section proximity (tasks 002/005/007). Every task was required to leave `make test` green
against the cross-cutting baseline (66 bats + 17 Jest cases at 100% node coverage).

## What shipped

### Phase 1 — Resolve Followups

1. **`001-lock-weasyprint-bootstrap.md`** (`AOJw`, merge `e6f5bbf5`) — Added a mkdir-based
   mutual-exclusion lock (`~/.md2x-venv.lock`) around the cold-bootstrap body of
   `ensure-weasyprint()`, closing the concurrent-cold-start race. The losing process blocks and
   waits (bounded 180s timeout with stale-lock remediation message). Lock released via explicit
   calls at every exit path, manually traced and verified. Warm path provably untouched.
   `docs/architecture.md` documents the locking behavior. New self-contained
   `weasyprint-bootstrap-locking.bats` drives two real concurrent `md2x` PDF conversions and
   proves via timestamped log markers the install sequence never overlaps. `make test` fully
   green (68 bats + 17 Jest).

2. **`002-fix-html-output-naming.md`** (`c2s9`, merge `61ead960`) — Removed the `-base` suffix
   logic from `src/cli/md2x.sh`'s per-file conversion loop so `--output-format html` now writes
   `<title>.html`, parallel to `<title>.pdf`/`<title>.docx` naming. Updated
   `output-format.bats`, `harness-smoke.bats`, `real-toolchain-e2e.bats`, and
   `docs/md2x-spec.md`'s UC2 text. `make test` green (66 bats, 17 Jest).

3. **`003-fix-md2x-js-shell-injection.md`** (`arUf`, merge `ffcc4534`) — Closed the shell
   injection risk by adding a `shellQuote` helper implementing POSIX single-quote escaping,
   applied at all four call sites identified in the task doc: `sources` (per-entry), `title`,
   `outputPath`, and the staging path. Added four new Jest cases proving the injection is closed.
   `make test` (66 bats + 21 Jest) and `make lint` green, 100% coverage maintained. Manual trace
   with a hostile title payload confirmed the fix holds.

4. **`004-document-find-pipe-abort-semantics.md`** (`8ZmD`, merge `33d6bf18`) — Confirmed
   empirically that a `find` failure on an unreadable search root never aborts the overall script
   (still exits 0) but silently drops any search root listed after the failing one, while roots
   before it are unaffected. Documented this at the pipe's nesting site in `src/cli/md2x.sh` and
   added two `exit-codes.bats` cases pinning down exit code, stderr content, and output
   differences. `make test` green.

5. **`005-document-weasyprint-ssrf-caveat.md`** (`Kjs2`, merge `3c525fb4`) — Added a
   plainly-worded SSRF/local-file-disclosure caveat to `docs/md2x-spec.md`'s Node library API
   documentation, stating WeasyPrint fetches external resources with no allowlist and that
   embedding apps rendering untrusted markdown should apply network egress restrictions or a
   fetcher override. Added a cross-linked pointer in `README.md`. No source code changed. `make
   test` passed in full.

6. **`006-stub-weasyprint-bootstrap-in-bats.md`** (`efJF`, merge `4f6fb346`) — Made
   `md2x_setup()`'s default bats harness hermetic against WeasyPrint's cold-bootstrap path by
   adding a private per-case `HOME` override pre-populated with a fake, executable
   `~/.md2x/venv/bin/weasyprint`, so `ensure-weasyprint.sh`'s `-x` gate passes immediately and the
   real ~1-minute install never triggers for default-setup cases. `HOME` is saved/restored
   symmetrically with `PATH`. Added a `harness-smoke.bats` case asserting the fake binary's
   presence and that the cold-bootstrap notice never appears. Confirmed `real-toolchain-e2e.bats`
   untouched. Full `make test` (67 bats + JS suite) green.

7. **`007-surface-css-temp-file-path.md`** (`OUbU`, merge `7efe43a0`) — Added a one-time stderr
   announcement of the CSS temp file's path in `src/cli/md2x.sh`, printed whenever
   `--keep-intermediate` is set (independent of `--quiet`), firing exactly once per invocation.
   Extended bats coverage and updated `README.md`/`docs/md2x-spec.md`. Full `make test` suite (67
   bats, 17 Jest, 100% coverage) green.

### Additional fixes applied during phase-boundary review

- **Manager-applied integration fix (merge-order defect).** Task 004's new bats assertions were
  authored against the pre-task-002 `<title>-base.html` naming (both tasks were dispatched
  in parallel against the same pre-plan baseline). Caught during phase-boundary testing after
  both tasks landed; the manager updated the 2 affected assertions in task 004's bats file to
  expect `<title>.html`, matching task 002's shipped rename.
- **Dispatch-simple-task security fix.** The phase-boundary review surfaced that task 003's
  shell-injection fix left one sibling parameter, `format`, unescaped in `src/node/md2x.js` —
  same file, same command-building pattern task 003 had otherwise closed. Closed via a follow-up
  dispatch that applied the same `shellQuote` helper to the `format` call site.

## Key decisions

- **mkdir-based lock over staging-dir+rename (task 001).** A plain `mkdir` on a fixed lock
  directory path was chosen over a staging-directory-plus-atomic-rename scheme for mutual
  exclusion around cold WeasyPrint bootstrap, keeping the mechanism simple and directly
  auditable at every exit path.
- **Bounded-blocking-wait with 180s timeout (task 001).** The losing process on lock contention
  blocks and polls rather than failing fast, bounded by a 180-second timeout with a stale-lock
  remediation message on expiry — chosen over an immediate-failure or unbounded-wait design.
- **shellQuote-escaping over execFile (task 003).** The shell-injection fix was implemented as
  POSIX single-quote escaping of interpolated values (`shellQuote`) rather than a rewrite to
  `execFile`/argv-array command execution, keeping the fix minimal and localized to string
  construction rather than restructuring how commands are invoked.
- **No functional change to find-pipe abort semantics, documented not fixed (task 004).** The
  existing behavior (an unreadable search root silently drops itself and any root listed after
  it, without aborting the script) was pinned down and documented rather than changed, per the
  task's explicit no-behavior-change scope. The underlying latent bug is tracked as a follow-up
  (see below) rather than fixed in this plan.
- **Docs-only for the SSRF caveat (task 005).** The WeasyPrint SSRF/local-file-disclosure
  exposure was addressed by documenting the risk and recommended mitigations for library
  consumers, not by adding runtime enforcement (e.g., an allowlist or fetcher override) inside
  md2x itself.

## Follow-up items

Per `plan/followups.yaml` as it stands after this plan's own removals, 5 items remain:

- **`egW0`** — Validation check 6 (python3 preflight failure) not exercised live. Pre-existing,
  explicitly out of scope for this plan (unrelated to the remediation set). Tracked observation;
  recommend re-verifying live in an environment where `python3` isn't colocated with
  brew/gs/pandoc — no immediate maintainer decision required.
- **`S92a`** — Genuine latent bug (recorded by task 004): a healthy, readable search root's files
  silently vanish (zero exit code, no error beyond `find`'s own stderr line) merely because it's
  listed after an unreadable root. Deliberately not fixed per task 004's no-behavior-change scope.
  **Needs a maintainer decision**: abort loudly, or process every root independently regardless of
  one root's failure.
- **`ZP4P`** — Informational only (phase-review, task 001 area): `WEASYPRINT_LOCK_TIMEOUT_SECS=180`
  and `WEASYPRINT_LOCK_POLL_SECS=1` are fixed constants, not exposed via env-var override, matching
  the file's existing style. Tracked observation; worth a maintainer note if a future need (e.g.
  CI wanting a shorter timeout) arises, but no decision required now.
- **`GuQR`** — `md2x.js` `sources: []` edge case behavior change (phase-review correctness lens,
  task 003 area): the pre-fix code took a truthy branch for `sources: []` and emitted one empty
  quoted shell argument (`''`); task 003's `shellQuote` refactor instead emits no source argument
  at all — a materially different CLI code path (zero positional args vs one empty one). Neither
  the pre- nor post-diff test suite exercises this exact edge case. **Needs a maintainer decision**:
  pick the intended behavior for `sources: []` deliberately and add a Jest case covering it.
- **`zwH4`** — WeasyPrint lock failure misdiagnosis (phase-review correctness lens, low
  confidence, task 001 area): in `ensure-weasyprint.sh`'s cold-bootstrap lock loop, every `mkdir`
  failure is treated identically as "another process holds the lock" and polled for up to the
  full 180s timeout, even if the real cause is an unrelated, persistent failure (e.g. unwritable
  `$HOME`) — producing a misleading stale-lock remediation message in that case. **Worth a
  maintainer fix**: distinguish `EEXIST`-style contention (confirm via a directory-existence
  check after a failed `mkdir`) from other `mkdir` failure modes, and fail fast with an accurate
  message on the latter.

## Final Task State

# TODO

## Purpose and scope

Tracking document for the active plan.

## Tasks

### Phase 01 — Resolve Followups

- [x] [001-lock-weasyprint-bootstrap.md](./phase-01-resolve-followups/001-lock-weasyprint-bootstrap.md) — tier `sonnet-high` · branch `phase-01-task-01-lock-weasyprint-bootstrap` · commit `c80287d` · merge `e6f5bbf53f98a9d91d9168835b327d71d0baee91`
- [x] [002-fix-html-output-naming.md](./phase-01-resolve-followups/002-fix-html-output-naming.md) — tier `sonnet-med` · branch `phase-01-task-02-fix-html-output-naming` · commit `6935ec1` · merge `61ead9601df3da5bdff550b6ed7c88b0e73a5299`
- [x] [003-fix-md2x-js-shell-injection.md](./phase-01-resolve-followups/003-fix-md2x-js-shell-injection.md) — tier `sonnet-high` · branch `phase-01-task-03-fix-md2x-js-shell-injection` · commit `ce5c15a` · merge `ffcc4534cc098a6d9e441dae69385a407cfeebb7`
- [x] [004-document-find-pipe-abort-semantics.md](./phase-01-resolve-followups/004-document-find-pipe-abort-semantics.md) — tier `sonnet-med` · branch `phase-01-task-04-document-find-pipe-abort-seman` · commit `487e0c9` · merge `33d6bf18f33da4e92e3cc65a2d99ed24981c8b48`
- [x] [005-document-weasyprint-ssrf-caveat.md](./phase-01-resolve-followups/005-document-weasyprint-ssrf-caveat.md) — tier `sonnet-med` · branch `phase-01-task-05-document-weasyprint-ssrf-cavea` · commit `28d411c` · merge `3c525fb42f6cf2ccdb5811c7d2c7d56eba91d177`
- [x] [006-stub-weasyprint-bootstrap-in-bats.md](./phase-01-resolve-followups/006-stub-weasyprint-bootstrap-in-bats.md) — tier `sonnet-med` · branch `phase-01-task-06-stub-weasyprint-bootstrap-in-b` · commit `0788ca0` · merge `4f6fb346ba78df307c94b01d69dcafb8d0ea8768`
- [x] [007-surface-css-temp-file-path.md](./phase-01-resolve-followups/007-surface-css-temp-file-path.md) — tier `sonnet-med` · branch `phase-01-task-07-surface-css-temp-file-path` · commit `a3d9330` · merge `7efe43a03114443ba3af8b2af89bcece56438686`

Plus one manager-applied integration fix (commit f44fb6c) and one dispatch-simple-task fix for the phase-review security finding (commit 52e3936, merged as 400ebaa).

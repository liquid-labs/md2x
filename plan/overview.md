# Followup Remediation

## Purpose and scope

This plan closes 7 already-decided followup items recorded in `plan/followups.yaml` on the current working branch (`2026-07-29-weasyprint`), which already carries 8 prior fix-batches — this is not greenfield work and nothing here is evaluated against `master`. Each item below has a final, maintainer-approved fix direction; no further deliberation on tradeoffs is in scope. The plan is deliberately single-phase: every task touches one coherent, already-scoped area of the codebase, no task depends on research or design output not already in hand, and the full task breakdown is complete up front.

Items in scope (by `plan/followups.yaml` id):

1. `AOJw` — unlocked concurrent cold-bootstrap race in `src/cli/lib/ensure-weasyprint.sh`.
2. `c2s9` — `--output-format html` produces `<title>-base.html` instead of `<title>.html`.
3. `arUf` — shell injection risk in `src/node/md2x.js`'s naive single-quoting of title/outputPath/sources.
4. `8ZmD` — abort-semantics shift in `src/cli/md2x.sh`'s nested find-pipe file discovery.
5. `Kjs2` — undocumented SSRF/local-file-disclosure exposure via WeasyPrint when `md2x()` is embedded as a library against untrusted Markdown.
6. `efJF` — the bats suite can trigger a real, network-dependent WeasyPrint cold install on a fresh machine because it doesn't stub `python3`/the bootstrap.
7. `OUbU` — the CSS temp file `generate-page.sh`/`md2x.sh` retain under `--keep-intermediate` is never surfaced to the user, unlike the Pandoc log and PDF overlay.

Explicitly out of scope: `egW0` (a validation-coverage followup unrelated to this remediation set) is left untouched in `plan/followups.yaml`.

Each task removes its own followup item(s) from `plan/followups.yaml` when it reports completion (per the plan-documents handling protocol, the task agent does not edit `followups.yaml` directly — it reports the resolved id(s) and the manager removes them via `followups_remove` when applying the task report).

## Current status

No task has started. All 7 tasks in Phase 1 (`resolve-followups`) are queued and, with the two caveats noted under [Overview](#overview) below, parallel-eligible — a task agent can be dispatched against any of them without waiting on another task in this plan to land first.

`dependencies_installed` was reported as "not installed" for the plan worktree; each task's own worktree must run `npm install` (or rely on whatever the dispatch/execution harness does) before `make test` will succeed. This is a pre-existing environment condition, not something any task needs to fix.

## Overview

### Phase 1 — Resolve Followups

Single phase, 7 tasks, each closing exactly one followup item. Every task must leave `make test` green (the cross-cutting baseline is 66 bats + 17 jest cases at 100% node coverage; individual tasks add cases on top of that baseline) and must re-run `make test` as part of its own validation.

1. **`001-lock-weasyprint-bootstrap.md`** (`AOJw`, tier `sonnet-high`) — add a locking mechanism to `src/cli/lib/ensure-weasyprint.sh` so two concurrent cold bootstraps can't interleave venv creation/pip install.
2. **`002-fix-html-output-naming.md`** (`c2s9`, tier `sonnet-med`) — change `--output-format html` per-file output naming from `<title>-base.html` to `<title>.html` in `src/cli/md2x.sh`; update bats coverage and docs.
3. **`003-fix-md2x-js-shell-injection.md`** (`arUf`, tier `sonnet-high`) — escape embedded single quotes in `src/node/md2x.js`'s title/outputPath/sources command-building; update `src/node/md2x.test.js`.
4. **`004-document-find-pipe-abort-semantics.md`** (`8ZmD`, tier `sonnet-med`) — empirically pin down and document the current find-pipe abort behavior in `src/cli/md2x.sh` with a comment and a targeted bats case (unreadable search root).
5. **`005-document-weasyprint-ssrf-caveat.md`** (`Kjs2`, tier `sonnet-med`) — docs-only: add an SSRF/local-file-disclosure caveat to `docs/md2x-spec.md`'s Node library section (and optionally README.md).
6. **`006-stub-weasyprint-bootstrap-in-bats.md`** (`efJF`, tier `sonnet-med`) — make the bats harness's default setup hermetic against a real WeasyPrint cold install by stubbing the venv-binary check.
7. **`007-surface-css-temp-file-path.md`** (`OUbU`, tier `sonnet-med`) — print the CSS temp file's path when `--keep-intermediate` is set, in `src/cli/md2x.sh`.

**Parallel-eligible group:** all 7 tasks (`001` through `007`) may be dispatched concurrently — no task's implementation depends on another task's code output.

**Two caveats worth the manager's attention, not hard blocks:**

- **Tasks `001` and `006` both touch WeasyPrint-bootstrap-adjacent test machinery**, but by design don't share files: task `006` changes the *shared* `md2x_setup` default (`src/cli/test/helpers/common.bash`) so ordinary bats cases get a pre-populated fake `weasyprint` binary and never reach the cold-bootstrap body at all. Task `001`'s own new concurrency test needs the opposite — a *cold* environment (no pre-existing venv) plus a fast stub `python3` — so it is required to set up its own dedicated, self-contained test fixture (its own `HOME` override and stub `python3`, following the `e2e_setup`-in-`real-toolchain-e2e.bats` pattern of not reusing `md2x_setup`) rather than relying on or fighting task `006`'s shared-default change. Written this way, the two tasks don't need to land in any particular order.
- **Tasks `002`, `005`, and `007` all touch `docs/md2x-spec.md` and/or `README.md`**, but in different sections (CLI use-case/reference text for `002`, the Node library API section for `005`, no doc changes required for `007` beyond what's in its own task). Concurrent dispatch is fine; if the manager merges them in a batch, watch for (unlikely, since the edits are far apart in each file) line-adjacency conflicts.

No architectural-implications doc-updates phase is added: none of the 7 items modify a public API/component boundary, introduce a new subsystem, change spec-defined behavior in an architecturally significant way, or add/remove significant tracked state — each task's own scope already includes updating the specific doc sections its change touches (README.md CLI reference, docs/md2x-spec.md use cases/API/library sections, and, where useful, docs/architecture.md's WeasyPrint-bootstrap prose).

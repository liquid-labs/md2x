# Plan Summary: release-followups-polish

## What was planned and why

A small, single-phase follow-on plan that resolves five open project followups (`32b8`, `S0YR`, `HdEH`, `FUld`, `5E3C`) left by the golden-release hardening work. It covers CLI maintainability and efficiency, three hardening items in `--infer-version`, release-script and CI polish, softened release-facing wording, and documentation accuracy. It adds no user-visible features.

Out of scope, and flagged for the maintainer instead of changed:

- Enabling GitHub private vulnerability reporting for `liquid-labs/md2x` (a repository setting; `SECURITY.md` links to the advisory URL that depends on it).
- Verifying the `apt`/`brew` install lines and the Node README `python3-venv` claims on a real Linux host (needs a first CI run; FUld item 5).
- Pushing, tagging, or publishing anything. Nothing here is pushed.

### Phase 1: Followup Polish (`phase-01-followup-polish`)

Three strictly sequential tasks. They are not parallel-eligible: task 001 changes the behavior that task 003 documents, and tasks 001 and 002 both edit `CHANGELOG.md`. `make test` must pass after each task, each task updates the `Unreleased` section of `CHANGELOG.md` for its own user-visible changes, and none commits or pushes (the dispatcher commits).

1. [001 Harden CLI Sources](./phase-01-followup-polish/001-harden-cli-sources.md) (tier `sonnet-high`; roles `developer-bash` + `developer-node`): followup `32b8` all four sub-items and `HdEH` items 2 to 4.
2. [002 Polish Release And CI](./phase-01-followup-polish/002-polish-release-and-ci.md) (tier `sonnet-med`; role `developer-bash`): `FUld` items 1, 3, 4, `S0YR`, and the `SECURITY.md` response-time softening.
3. [003 Update Docs](./phase-01-followup-polish/003-update-docs.md) (tier `sonnet-med`; role `tech-writer`): `5E3C` all items, `HdEH` item 1, and architecture/spec updates for task 001.

Design decisions taken up front so the phase needs no `needs input` round:

- A `core.worktree` redirect (the git directory resolved from the input differs from the one resolved from the work-tree top) is refused with a warning and no version, exactly like the other `--infer-version` refusals. The untested `-c core.worktree=` alternative is not used.
- An empty `config.worktree` is zero keys; any other per-worktree read failure still fails closed.
- Efficiency work in `32b8` item 4 is measured first and kept behavior-neutral; the lookup rewrite is done only if the measurement shows it matters, and the measurement is recorded in the task report.
- The unique Lua heredoc terminator (`MD2X_LUA_EOF`) already exists; task 001 adds the bats guard only if none exists.

Documents: [followup status notes](./notes/followup-status.md).

## What shipped

### Phase 01 — Followup Polish

1. **Harden CLI Sources** (`001-harden-cli-sources.md`, tier `sonnet-high`) — Dropped the bash-toolkit dependency (incl. smoke-test script). Extracted input discovery into lib/input-discovery.sh with unchanged behaviour. Removed per-byte forks in percent-encode and replaced the quadratic plan-collision lookup (measured 32s and 80s for 4000 targets) with per-key variables. Capped md2xAsync buffering at 64 MiB. Hardened --infer-version against core.worktree redirect, control-character config keys and empty config.worktree, each with tests. make test, lint and bash 3.2 test-cli pass.
   Commit `71a4131`, merged at `b4744ae2d3d15dd4ef6579548fdbbb12b740d9f4`.

2. **Polish Release And CI** (`002-polish-release-and-ci.md`, tier `sonnet-med`) — release.sh dry-run now rehearses bun publish on the bumped tree before revert_bump; CI gained timeout-minutes, PR-only concurrency cancel and apt-get install of the legacy pandoc deb; SECURITY.md softened to best-effort; CHANGELOG CI claim phrased as intended; pandoc floor wording says unproven until CI runs; RELEASING.md artifact list already correct. Not verified end to end: release.sh --dry-run was not run.
   Commit `4f112b4`, merged at `675a2b11da1aceee710c29f604fd8284ed3ddfeb`.

3. **Update Docs** (`003-update-docs.md`, tier `sonnet-med`) — Docs-only sync of architecture, spec, README, AGENTS and project-structure to the landed code from tasks 001 and 002, resolving all 5E3C items and confirming HdEH item 1. Only source edit is the guard comment in md2x.sh. Optional Key decisions regrouping skipped. make test (380 bats, 64 node) and lint pass.
   Commit `8fe6828`, merged at `2e52387b7ac35602b83db1d7b4419e9b4922391e`.

### Phase 02 — Remediation Round 1

1. **Rehearse Publish On The Release Dry-Run Resume Path** (`001-release-dry-run-resume-rehearsal.md`, tier `sonnet-med`) — A release.sh --dry-run on the resume path now runs the bun publish --dry-run rehearsal in the publish section (fresh path unchanged); RELEASING.md documents both placements. Verified by bash -n and a read of both paths; release.sh --dry-run itself was not run.
   Commit `bcb551f`, merged at `bc8d205375fe9d8cf7fb198619523aadc914b084`.

2. **Clear Inherited Plan Record Variables And Escalate Async Child Kill** (`002-harden-plan-records-and-async-kill.md`, tier `sonnet-med`) — Plan record tables are reset (md2x-record-reset, compgen -v) before planning so inherited MD2X_PLAN_INPUT_/TARGET_ variables cannot pre-seed collisions; md2xAsync escalates to SIGKILL 2s after the overflow kill if the child has not closed. New bats case and two bun tests; make test (66), lint and bash 3.2 test-cli pass. The new bats case was not confirmed to fail without the fix.
   Commit `a6bc1e5`, merged at `d7f8c8bedb397cf30d36b1125709edfc473f70fb`.

3. **Fix Architecture Doc Wording And Re-Wrap Scan-Keys Comment** (`003-fix-architecture-wording-and-comment-wrap.md`, tier `haiku-med`) — Fixed the ungrammatical git status clause in docs/architecture.md, added the sentence on per-key collision record variables (md2x-plan-key-hex, md2x-record-set, md2x-record-get), and re-wrapped the md2x-infer-scan-keys comment in preflight.sh with comment-only changes. make test and lint pass.
   Commit `108c9fd`, merged at `c8d47a36a2f284ef9f22a9418d5a92a735131aff`.

## Key decisions

_No `## Why this shape` section is recorded in `plan/overview.md`, so this plan's cross-task rationale was never written down. Per-task outcomes are under "What shipped" above._

## Findings

- **`y217`** — **Planning phase forks per file** — promoted — ref: `y217` — 2026-10-09

- **`KPVO`** — **Input dedupe in input-discovery.sh is O(n^2)** — promoted — ref: `KPVO` — 2026-10-09

- **`wf4S`** — **release.sh resume skips publish rehearsal** — fixed — ref: `phase-02-remediation-01/001-release-dry-run-resume-rehearsal.md` — 2026-10-09

- **`iRLu`** — **Harden plan record vars and async child kill** — fixed — ref: `phase-02-remediation-01/002-harden-plan-records-and-async-kill.md` — 2026-10-09

- **`SJUO`** — **Re-wrap md2x-infer-scan-keys comment** — fixed — ref: `phase-02-remediation-01/003-fix-architecture-wording-and-comment-wrap.md` — 2026-10-09

- **`wheq`** — **Architecture doc: sentence fix, record note** — fixed — ref: `phase-02-remediation-01/003-fix-architecture-wording-and-comment-wrap.md` — 2026-10-09

## Remediation

- Rounds used: 1 (resolved max_rounds: 3).
- Remediation tasks added: 3 (resolved max_added_tasks: 14).
- Remediation phases:
  - `remediation-01` — 3 task(s)
- Security review required: yes (at least one remediation phase carries `security_review: required`).

## Final Task State

# TODO

## Purpose and scope

Tracking document for the active plan.

## Tasks

### Phase 01 — Followup Polish

- [x] [001-harden-cli-sources.md](./phase-01-followup-polish/001-harden-cli-sources.md) — tier `sonnet-high` · branch `plan/release-followups-polish-01-001` · commit `71a4131` · merge `b4744ae2d3d15dd4ef6579548fdbbb12b740d9f4`
- [x] [002-polish-release-and-ci.md](./phase-01-followup-polish/002-polish-release-and-ci.md) — tier `sonnet-med` · branch `plan/release-followups-polish-01-002` · commit `4f112b4` · merge `675a2b11da1aceee710c29f604fd8284ed3ddfeb`
- [x] [003-update-docs.md](./phase-01-followup-polish/003-update-docs.md) — tier `sonnet-med` · branch `plan/release-followups-polish-01-003` · commit `8fe6828` · merge `2e52387b7ac35602b83db1d7b4419e9b4922391e`

### Phase 02 — Remediation Round 1

- [x] [001-release-dry-run-resume-rehearsal.md](./phase-02-remediation-01/001-release-dry-run-resume-rehearsal.md) — tier `sonnet-med` · branch `plan/release-followups-polish-02-001` · commit `bcb551f` · merge `bc8d205375fe9d8cf7fb198619523aadc914b084`
- [x] [002-harden-plan-records-and-async-kill.md](./phase-02-remediation-01/002-harden-plan-records-and-async-kill.md) — tier `sonnet-med` · branch `plan/release-followups-polish-02-002` · commit `a6bc1e5` · merge `d7f8c8bedb397cf30d36b1125709edfc473f70fb`
- [x] [003-fix-architecture-wording-and-comment-wrap.md](./phase-02-remediation-01/003-fix-architecture-wording-and-comment-wrap.md) — tier `haiku-med` · branch `plan/release-followups-polish-02-003` · commit `108c9fd` · merge `c8d47a36a2f284ef9f22a9418d5a92a735131aff`

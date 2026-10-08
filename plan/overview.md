# Release Followups Polish

## Purpose and scope

A small, single-phase follow-on plan that resolves five open project followups (`32b8`, `S0YR`, `HdEH`, `FUld`, `5E3C`) left by the golden-release hardening work. It covers CLI maintainability and efficiency, three hardening items in `--infer-version`, release-script and CI polish, softened release-facing wording, and documentation accuracy. It adds no user-visible features.

Out of scope, and flagged for the maintainer instead of changed:

- Enabling GitHub private vulnerability reporting for `liquid-labs/md2x` (a repository setting; `SECURITY.md` links to the advisory URL that depends on it).
- Verifying the `apt`/`brew` install lines and the Node README `python3-venv` claims on a real Linux host (needs a first CI run; FUld item 5).
- Pushing, tagging, or publishing anything. Nothing here is pushed.

## Current status

Not started. Phase 1 begins with task 001. The worktree is at the tip of `main` plus plan bookkeeping, and `make test` is assumed green at the start. Several followup items are already partly or wholly done in the current tree (see [followup status notes](./notes/followup-status.md)); each task must re-verify before editing and record already-satisfied items instead of redoing them.

## Overview

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

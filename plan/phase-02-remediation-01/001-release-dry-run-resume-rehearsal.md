# Rehearse Publish On The Release Dry-Run Resume Path

## Purpose and scope

Resolves finding `wf4S` of this plan. The work targets the plan branch `plan/release-followups-polish` and lands through the ordinary per-task loop. Only `scripts/release.sh` and `RELEASING.md` change.

## Requirements

1. A `scripts/release.sh --dry-run` run that takes the resume path (tag `v$NEW` at HEAD, package.json already at `$NEW`) runs `bun publish --dry-run --access public --tag <dist-tag for $NEW>`. There is nothing to revert on that path, so `revert_bump` must not run there. Alternatively, the dry-run publish message is made conditional on RESUME and RELEASING.md documents the skip. Prefer running the rehearsal.
2. The dry-run message in the publish section is accurate on both the fresh and the resume path, and never claims a rehearsal that did not run.
3. The non-dry-run flow (fresh and resume) is unchanged. RELEASING.md's dry-run table (around lines 62 and 65) matches the behavior.
4. Add an Unreleased CHANGELOG entry only if the change is user-visible.

## Validation

1. `bash -n scripts/release.sh` passes. `scripts/release.sh --print-dist-tag 1.0.0` prints `latest` and `--print-dist-tag 1.0.0-rc.1` prints `rc`.
2. A careful read, recorded in the report, of both dry-run paths (RESUME=0 and RESUME=1) shows exactly one rehearsal per dry run, or an accurate skip message.
3. `make test` and `make lint` pass.
4. Never run a non-dry release, push, tag, or publish.

## References

- Finding `wf4S` in this plan's `plan/findings.yaml`.
- `plan/phase-01-followup-polish/002-polish-release-and-ci.md`, which introduced the ordering.

## Status

Succeeded 2026-10-08. Resume-path dry run now runs the publish rehearsal in the publish step (no revert needed); fresh path unchanged. See scripts/release.sh and RELEASING.md. bash -n, print-dist-tag, make test, make lint passed.

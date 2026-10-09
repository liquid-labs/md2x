# Clear Inherited Plan Record Variables And Escalate Async Child Kill

## Purpose and scope

Resolves finding `iRLu` of this plan (a `type:security` finding, so the phase is stamped for a full security review). The work targets the plan branch `plan/release-followups-polish` and lands through the ordinary per-task loop. Files: `src/cli/lib/output-plan.sh`, `src/cli/md2x.sh`, the existing bats file for output planning, `src/node/md2x.js`, `src/node/md2x.test.js`.

## Requirements

1. Before output planning records anything, every variable whose name starts with a record-table prefix (`MD2X_PLAN_INPUT_`, `MD2X_PLAN_TARGET_`, and any other table `output-plan.sh` uses) is unset, in a bash 3.2-compatible way (for example `compgen -v`). An inherited environment variable can then neither pre-seed a record nor change a collision verdict or message.
2. In `md2xAsync` (`src/node/md2x.js`), after the 64 MiB overflow kill, a child still running after a short grace period is sent SIGKILL. The timer is cleared when the child closes. The rejection shape stays the same.
3. No change to messages, exit codes, or planning semantics.
4. Add an Unreleased CHANGELOG entry for the user-visible hardening.

## Validation

1. A new bats case shows that running md2x with an exported `MD2X_PLAN_INPUT_<hex>` / `MD2X_PLAN_TARGET_<hex>` matching a real input or target does not produce a false collision refusal. Pick the existing bats file that covers output planning.
2. A bun:test case with a fake child that ignores SIGTERM shows it is killed with SIGKILL after the cap trips, and the promise still rejects as before.
3. `make test`, `make lint`, and `MD2X_TEST_BASH=/bin/bash make test-cli` pass.

## References

- Finding `iRLu` in this plan's `plan/findings.yaml`.
- `plan/phase-01-followup-polish/001-harden-cli-sources.md`, which introduced the record store and the cap.

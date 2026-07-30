# Stub WeasyPrint Bootstrap In The Bats Test Harness

## Purpose and scope

Closes followup `efJF`. The bats suite's shared harness (`src/cli/test/helpers/common.bash`, via `md2x_setup`/`md2x_use_stub_path`) stubs `pandoc`, `gs`, and `pdftk` on the case's `PATH`, but not `python3` or the WeasyPrint bootstrap — `MD2X_TEST_PASSTHROUGH_TOOLS` (`bash brew git jq perl`) doesn't include `python3`, and `MD2X_TEST_SYSTEM_PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`) leaves the real system `python3` reachable. So on a machine that has never run md2x (a fresh CI runner, or a dev machine before its first PDF conversion), the first PDF-format bats case reaches `src/cli/lib/ensure-weasyprint.sh`'s cold path and triggers a real, ~1-minute, network-dependent WeasyPrint install into `~/.md2x/venv` — breaking the hermetic-suite property every other stubbed case relies on. Make the default bats setup hermetic against this by short-circuiting the venv-binary check.

## Requirements

- In `src/cli/test/helpers/common.bash`'s `md2x_setup()`, add a private per-case `HOME` override (distinct from the case's existing private working directory / stub-`PATH` directory) and pre-populate it with a fake, already-executable `${HOME}/.md2x/venv/bin/weasyprint` file *before* the CLI is ever invoked. This makes `ensure-weasyprint.sh`'s `[[ -x "${WEASYPRINT_BIN}" ]]` gate pass immediately for every case using the default `md2x_setup` — the cold-bootstrap body never runs, and no real `python3`/network work happens. The fake binary's own contents don't matter (stub `pandoc` is what actually receives `--pdf-engine=<path>` as an inert argument string — it's never executed as `weasyprint` by the stub suite); a trivial `#!/bin/sh\nexit 0` placeholder, `chmod +x`'d, is sufficient.
- Export and restore `HOME` symmetrically with how `PATH` is already handled: save the original `HOME` in `md2x_setup()` (parallel to `MD2X_TEST_ORIGINAL_PATH`), point `HOME` at the new private directory for the duration of the case, and restore it in `md2x_teardown()` (parallel to the existing `PATH` restoration). Keep the private `HOME` directory inside the case's existing `MD2X_TEST_TMPDIR` so it's cleaned up by the existing `rm -rf "${MD2X_TEST_TMPDIR}"` teardown step — no separate cleanup needed.
- **Do not** touch `src/cli/test/bats/real-toolchain-e2e.bats`'s `e2e_setup`/`e2e_teardown` — those cases deliberately run against the real toolchain (including a real `~/.md2x/venv` if present) and must keep using the ambient `HOME`/`PATH`, not the stubbed ones. Confirm by inspection that `e2e_setup` never calls `md2x_setup`/`md2x_use_stub_path` (it currently doesn't) and that your change is additive only inside `md2x_setup()`, not any shared helper `e2e_setup` also calls.
- Add or extend harness self-verification coverage in `src/cli/test/bats/harness-smoke.bats` (the file whose stated purpose is exactly this: "self-verification for the CLI test harness itself") with a case confirming that a PDF-format conversion under the default `md2x_setup` never invokes real `python3`/`pip` — e.g. assert the fake `weasyprint` binary exists at the stubbed `HOME` path before the run, and/or that no `pip`/`ensurepip`/`venv`-creation side effect occurred (there's no real network call to assert the *absence* of directly, so the strongest available signal is: the case completes quickly, without the `"md2x: installing weasyprint..."` stderr notice `ensure-weasyprint()` prints on the cold path — assert that stderr string is absent).
- Update this file's / this task's own doc comment context: `src/cli/test/helpers/common.bash`'s header comment enumerates what `md2x_setup` establishes ("what `md2x_setup` establishes, and why") — add a bullet there describing the new `HOME`/fake-`weasyprint` stub, matching the existing bullets' style and level of detail.

## Validation

- `make test` passes, including the new/extended `harness-smoke.bats` coverage.
- Time a full `make test-cli` run before and after (informally) to confirm no case takes anywhere near ~1 minute — the whole point of this fix. (Not a scripted assertion; a sanity spot-check.)
- `grep -n "HOME" src/cli/test/helpers/common.bash` shows the new save/override/restore lines in `md2x_setup`/`md2x_teardown`.
- Confirm `src/cli/test/bats/real-toolchain-e2e.bats` is untouched by this task (`git diff` should show no changes to that file).
- `grep -rn "efJF" plan/followups.yaml` — confirm the id no longer appears after this task's report is applied (report the resolved id; removal is the manager's step via `followups_remove`).

## Assumptions

- Task `001` (`lock-weasyprint-bootstrap`) adds its own new bats file with a fully self-contained setup/teardown that deliberately does *not* rely on `md2x_setup`'s HOME/PATH defaults (specifically so it can exercise the cold-bootstrap path this task's change short-circuits by default). No coordination beyond that separation is required — see `plan/overview.md`'s notes on the `001`/`006` interaction.

## References

- `src/cli/test/helpers/common.bash` — `md2x_setup()`/`md2x_teardown()`, the primary edit location.
- `src/cli/lib/ensure-weasyprint.sh` — the `[[ -x "${WEASYPRINT_BIN}" ]]` gate this task short-circuits, and the `"md2x: installing weasyprint..."` stderr notice useful for the new harness-smoke assertion.
- `src/cli/test/bats/harness-smoke.bats` — where to add the new self-verification case.
- `src/cli/test/bats/real-toolchain-e2e.bats` — must remain unaffected.
- `plan/followups.yaml` item `efJF` — full original followup text.

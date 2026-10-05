# Harden Output Delivery Edge Cases And Find Root Handling

## Purpose and scope

Fixes findings wgQ3 and m1SB from the Remediation Round 1 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. It runs after the version-inference task because both edit `docs/md2x-spec.md`, and before the nonce task because both edit `src/cli/md2x.sh` and `src/cli/lib/generate-page.sh`.

## Requirements

1. `md2x-deliver-output` (`src/cli/lib/output-plan.sh`) refuses with a runtime error (exit 1) any target where `[[ -d T ]]` is true, including a symlink to a directory. After the `mv` it checks that the target is a regular file, not a symlink.
2. The `mktemp` template is safe when the target directory is relative and starts with `-`: prefix it with `./` (or otherwise make the template non-option-like), so `-o -d/out.pdf` delivers correctly.
3. The temp file is registered with the existing run cleanup trap in `src/cli/md2x.sh`, or otherwise removed on EXIT/INT/TERM, so an interrupted delivery leaves no `.md2x-out.*` behind. The bash 3.2 exit-status backstop in that trap must be kept.
4. In `find` discovery (`src/cli/md2x.sh`, around lines 314-319), every non-absolute root is prefixed with `./` (and the prefix stripped from results), or the `find` tokens `!`, `(`, `)` and `,` are otherwise handled. Displayed and listed names stay as the user typed them. The `Created <file>` and `--list-files` stdout contracts do not change.
5. Document in `docs/md2x-spec.md` (inputs/output section):
   - symlinked `*.md` files found in a searched directory are followed (read);
   - replacing an existing target creates a new file with a umask-derived mode, so the previous mode and ownership are not kept;
   - the output directory and its parents must not be writable by an untrusted party, because a parent directory swapped for a symlink during the run redirects delivery.

## Validation

1. A bats case for `-o <link>` where `<link>` is a symlink to an existing directory: exits non-zero, writes nothing into the linked directory, and leaves no `.md2x-out.*` file. It must fail on the current code.
2. A bats case: `-o -d/out.pdf` (with a directory `-d`) succeeds and creates `-d/out.pdf`. It must fail on the current code.
3. A bats case for search roots named `!` and `(` (directories by those names): each searches only that directory and lists the names as given. It must fail on the current code (if BSD `find` behavior cannot be reproduced on the host, report that and keep the case as a guard).
4. A bats or unit-level check that the cleanup trap removes a pending delivery temp file, for example by simulating a failure after `mktemp`.
5. The existing collision, overwrite, hard-link and symlink cases still pass. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` are green.

## References

- Finding wgQ3, in this plan's `plan/findings.yaml`.
- Finding m1SB, in this plan's `plan/findings.yaml`.
- Files: `src/cli/lib/output-plan.sh`, `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`, `src/cli/test/bats/output-options.bats`, `src/cli/test/bats/input-discovery.bats`, `docs/md2x-spec.md`.

## Status

Succeeded (2026-10-05). `md2x-deliver-output` now refuses any `-d` target (including a symlink to a directory), prefixes relative mktemp directories with `./`, registers the temp file as `MD2X_DELIVERY_TEMP` for the run EXIT trap (bash 3.2 backstop kept), and checks the result is a regular file. `find` discovery prefixes every non-absolute root with `./` and strips it from results. Spec updated (`docs/md2x-spec.md`, Input and Output delivery paragraphs). New bats cases in `src/cli/test/bats/output-options.bats` and `input-discovery.bats`. The symlink-to-directory case already passed pre-change (planning-time check exits 2), so it is a guard; the other three fail on the pre-change build. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` green.

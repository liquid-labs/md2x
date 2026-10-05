# Re-Check Input Identity And Deliver Output Without Following Symlinks

## Purpose and scope

Fixes finding m1SB from the Phase 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. The collision and input-overwrite checks compare path strings at plan time, but delivery later uses `cp --`, which follows a symlink swapped in at the final component. Hard links and alternate mount paths to an input are also not detected.

## Requirements

1. Immediately before delivery, `generate-page.sh` refuses (runtime error, exit 1) to write a target that is the same file as any input (`test -ef`), which also catches hard links and alternate mount paths.
2. Delivery writes to a temp file in the target directory and then `mv`s it into place, so a symlink at the final component is replaced, not followed.
3. Decide whether `find` discovery follows symlinked `*.md` files and either restrict it to `-type f` or keep following and report the choice for the Phase 3 docs. Do not change the `Created <file>` or `--list-files` stdout contracts.

## Validation

1. A bats case where the output path is a hard link to an input fails without modifying the input.
2. A bats case where the output path is a symlink to another file replaces the symlink and leaves the pointed-to file untouched.
3. The existing collision and overwrite cases pass, and `make qa` is green (including `MD2X_TEST_BASH=/bin/bash make test-cli`).

## References

- Finding m1SB, in this plan's `plan/findings.yaml`.
- Files: `src/cli/lib/generate-page.sh`, `src/cli/lib/output-plan.sh`, `src/cli/md2x.sh`, `src/cli/test/bats/`.

# Neutralize Repository Git Config In Version Inference

## Purpose and scope

Fixes finding SmNy from the Phase 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. `md2x-infer-version` runs `git` in a directory taken from the inputs, and a repository-local `.git/config` (for example `core.fsmonitor`) can make git execute commands.

## Requirements

1. Every `git` call in `md2x-infer-version` (`src/cli/lib/preflight.sh`) runs with `-c core.fsmonitor= -c core.hooksPath=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, and `status --no-optional-locks`, so a repository-local `.git/config` cannot execute commands.
2. Version-inference behavior and warnings are otherwise unchanged.

## Validation

1. A bats case builds a temporary repository whose `.git/config` sets `core.fsmonitor` to a command that writes a sentinel file. `md2x --infer-version` on a file in it does not create the sentinel. The case fails on the old code.
2. The existing `--infer-version` cases pass.
3. `make qa` is green.

## References

- Finding SmNy, in this plan's `plan/findings.yaml`.
- Files: `src/cli/lib/preflight.sh`, `src/cli/test/bats/`.

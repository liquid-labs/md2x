# Refuse Command-Bearing Repository Config Before Git Status In Version Inference

## Purpose and scope

Fixes finding r4Pu from the Remediation Round 1 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. `md2x-infer-git` neutralizes `core.fsmonitor` and `core.hooksPath`, but `git status --porcelain` in an untrusted input repository still executes repository-configured commands: with a tracked `.gitattributes` `* filter=x` and a `.git/config` `[filter "x"] clean = <cmd>`, the hardened command runs the clean filter when a tracked file is stat-dirty (reproduced by the reviewer and the evaluator). This is only reachable with `--infer-version`.

## Requirements

1. Before any `git status` call, `md2x-infer-version` (`src/cli/lib/preflight.sh`) reads the repository's own config without running any command. Use `git -C <TOP> config --local --list --name-only` without `--includes`. If `extensions.worktreeConfig` is set, also read `--worktree`. Run it through `md2x-infer-git`.
2. If any key could run a command or pull in other config, `md2x-infer-version` prints one `md2x-warn` naming the reason, then omits the version (prints nothing) and never runs `git status`. Match keys case-insensitively. At minimum:
   - `filter.*`
   - `include.*` and `includeif.*`
   - `core.fsmonitor` and `core.worktree`
   - any key whose last component is one of: `command`, `program`, `driver`, `textconv`, `external`, `pager`, `editor`, `askpass`, `sshcommand`, `gitproxy`, `process`, `clean`, `smudge`
   - `credential.*`

   A stricter allowlist is acceptable if it fails closed.
3. Fail closed: if the config read fails or its output cannot be parsed, warn and omit the version rather than running `git status`.
4. Repositories whose local config holds only ordinary keys (core basics, `remote.*`, `branch.*`, `user.*`) keep today's behavior: the `package.json` version when clean, `working` when dirty.
5. Document the trust assumption in `docs/md2x-spec.md`, in the `--infer-version` note near line 128: version inference runs git only in repositories whose local config has no command-bearing keys, and otherwise warns and omits the version. Also update the comment block above `md2x-infer-git`.
6. Bash 3.2 compatible. No new runtime dependencies.

## Validation

1. New bats case in `src/cli/test/bats/version-inference.bats`:
   - Set up a repo with a tracked `package.json` and `* filter=x` in `.gitattributes`, plus `.git/config` `[filter "x"] clean = <touch sentinel; cat>`.
   - Make the tracked file stat-dirty deterministically, for example with `touch -t` to a different mtime after the commit.
   - Assert that `md2x --infer-version` does not create the sentinel, warns, and has no `Version` in the footer.
   - Confirm the case FAILS on the current code before the fix.
2. Bats cases for at least an `include.path` key and an `includeIf` key: each warns and omits the version without running status.
3. The existing `--infer-version` cases still pass, including the fsmonitor sentinel case and the clean/`working` behavior.
4. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` are green.

## References

- Finding r4Pu, in this plan's `plan/findings.yaml`.
- Files: `src/cli/lib/preflight.sh`, `src/cli/test/bats/version-inference.bats`, `docs/md2x-spec.md`.

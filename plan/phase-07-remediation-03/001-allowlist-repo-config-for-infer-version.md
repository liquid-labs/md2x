# Allowlist Repository Config And Harden Git Status In Version Inference

## Purpose and scope

Fixes findings U0Pj and Qbv2 from the Remediation Round 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. Round 2 added a denylist (`md2x-infer-config-refusal` in `src/cli/lib/preflight.sh`) that refuses repositories whose local git config has command-bearing keys. The reviewers reproduced three ways around it, so `git status --porcelain` in an attacker-supplied repository can still run commands:

- Partial-clone remotes: `remote.<n>.uploadpack`/`receivepack`, or `protocol.ext.allow=always` with an `ext::` remote URL, run when a missing blob makes status lazy-fetch during rename detection. Other unlisted keys on the same path: `remote.<n>.vcs`, `remote.<n>.proxy`, `protocol.*`, `url.*.insteadOf`.
- Submodules: a checked-out submodule with its own `.git/config` (`filter.p.clean` plus a `.gitattributes` in the submodule and a stat-dirty file) runs its clean filter when the outer `git status` runs.
- Pipefail bypass: the `extensions.worktreeConfig` check pipes the key list into `grep -q` under `pipefail`; a key list larger than the pipe buffer makes `printf` take SIGPIPE, the pipeline returns 141, and the per-worktree config (`.git/config.worktree`) is never read.

Version inference only runs git with `--infer-version`. The goal is that md2x never runs a command from an untrusted repository's config.

## Requirements

1. Replace the denylist with an ALLOWLIST. Proceed to `git status` only when every key from `git config --local --list --name-only` (and the per-worktree config when `extensions.worktreeConfig` is set) is in a small known-benign set. At minimum the benign set is: `core.repositoryformatversion`, `core.filemode`, `core.bare`, `core.logallrefupdates`, `core.ignorecase`, `core.precomposeunicode`, `core.symlinks`, `extensions.worktreeconfig`, `user.*`, `branch.*`. Refuse anything not in the set, including `remote.*`, `protocol.*`, `url.*`, `extensions.partialclone` and every other `extensions.*`, and `submodule.*`. When a key is refused, print one `md2x-warn` naming it, omit the version (print nothing), and never run `git status`. Match keys case-insensitively. Keep the fail-closed behavior for an empty or unparseable key list and for git older than 2.22.
2. Add defense in depth on the status call itself: `--ignore-submodules=all` (the CLI flag overrides config), `--no-renames`, `-c protocol.allow=never`, and `GIT_NO_LAZY_FETCH=1` (ignored by older git; harmless). Keep the existing `GIT_CONFIG_NOSYSTEM=1`, `--no-optional-locks`, `-c core.fsmonitor=` and `-c core.hooksPath=/dev/null`. Also set `GIT_CONFIG_GLOBAL=/dev/null` for these git calls.
3. Fix the pipefail fail-open: no `printf | grep -q` under `pipefail` anywhere in this code path. Use a here-string or a `case` match inside the key loop (or read the key via `git config --local --bool`). Lowercase the whole key list once with `LC_ALL=C tr '[:upper:]' '[:lower:]'` instead of forking per key. Bash 3.2 compatible (no `${var,,}`, no associative arrays).
4. Optional cleanup in `md2x-deliver-output` (`src/cli/lib/output-plan.sh`): drop or reword the dead post-`mv` symlink check (`mv` replaces a symlink, so the check cannot fire).
5. Update the trust text in `docs/md2x-spec.md` (the `--infer-version` bullet) and the comment above `md2x-infer-git` to describe the allowlist and the extra status hardening. Keep the earlier remediation text about symlinked sources and delivery.

## Validation

1. New bats cases in `src/cli/test/bats/version-inference.bats`, each verified to FAIL on the current code (build a pre-change `bin/md2x` from `git archive` of HEAD and run the new cases against it; report which failed):
   - a partial-clone repo with `remote.origin.promisor=true`, a `partialclonefilter`, `remote.origin.uploadpack` set to a command that writes a sentinel, and a blob missing locally: no sentinel, a warning, no version;
   - a `protocol.ext.allow=always` plus `remote.origin.url=ext::...` repo: no sentinel;
   - a repo with a checked-out submodule whose own `.git/config` sets `filter.p.clean` to a command that writes a sentinel (with a `.gitattributes` in the submodule and a stat-dirty file): no sentinel;
   - a repo with `extensions.worktreeConfig=true` followed by more than 64 KB of ordinary keys and a `filter.x.clean` in `.git/config.worktree`: still refused, no sentinel.
   If a case cannot be made to execute on the old code on this host, say so and keep it as a guard.
2. The existing `--infer-version` cases still pass: ordinary repos (core basics, `user.*`, `branch.*`) give the `package.json` version when clean and `working` when dirty. Note that an ordinary clone has `remote.origin.*` keys; decide and test explicitly how repositories with a plain `remote.<n>.url`/`fetch` (no `uploadpack`, `receivepack`, `vcs`, `proxy`, `promisor`, `partialclonefilter`) behave. The preferred behavior is to allow `remote.<n>.url` and `remote.<n>.fetch` only (and `remote.<n>.pushurl`) so that normal checkouts keep working, since the status hardening above removes the lazy-fetch path.
3. `make qa` and `MD2X_TEST_BASH=/bin/bash make test-cli` are green.

## References

- Finding U0Pj, in this plan's `plan/findings.yaml`.
- Finding Qbv2, in this plan's `plan/findings.yaml`.
- Files: `src/cli/lib/preflight.sh`, `src/cli/lib/output-plan.sh`, `src/cli/test/bats/version-inference.bats`, `docs/md2x-spec.md`.

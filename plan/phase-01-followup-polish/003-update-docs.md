# Update Docs

## Purpose and scope

Resolve followup `5E3C` (all items), `HdEH` item 1, and bring `docs/architecture.md`, `docs/md2x-spec.md`, `docs/project-structure.md`, `AGENTS.md`, and `README.md` in line with the code changes from tasks 001 and 002.

- Role: `tech-writer`. Suggested tier: `sonnet-med`.
- Background: [followup status notes](../notes/followup-status.md). Verify each claim below against the current text and code (line numbers drift) and record items already correct instead of editing them.

## Requirements

### 5E3C (`docs/architecture.md` and one source comment)

1. Drop "stubbed" from the statements that CI runs a "stubbed CLI suite" against pandoc 2.0.6 (the Pandoc-floor and CI passages): the legacy job runs plain `make test-cli`, which includes real-toolchain bats files such as `links-and-images.bats`. Keep the claim intended-until-run per task 002; say the floor is unproven until the workflow has run.
2. Reword the interpreter-guard rationale (the architecture overview paragraph and the guard comment at `src/cli/md2x.sh` lines 16 to 17, plus the matching spec or README text if any): bash in POSIX mode is unsupported and untested, not "because process substitution is unavailable" (the CLI no longer uses process substitution). Changing a comment in `md2x.sh` is the only source edit allowed in this task; run `make test` afterwards.
3. Correct the version-inference passages (preflight/version-inference sections and Key decisions): `git rev-parse --show-toplevel` and `git config --local --list --name-only -z` run first through the hardened `md2x-infer-git`; only `git status` is gated by the key allowlist.
4. Correct the claim that any failure is one warning with the version omitted: a failing `git status` sets the status to `?` and the footer prints `working` with no warning.
5. Qualify "every failure is one `md2x: ` line": `md2x-die-usage` adds an unprefixed `Try 'md2x --help'` line, and WeasyPrint bootstrap failures print several lines.
6. Nits: the preflight check order is `gs`, `pandoc`, `pdftk`, `python3` (check `md2x.sh`'s preflight and align the prose and the architecture diagram label if it implies another order); with `--to-stdout` no output targets are planned (state this where target planning is described).
7. Optional: group the Key decisions bullets under a few `###` subheadings (for example CLI structure, safety and trust, output, release and CI). Keep each bullet's text and link anchors intact; check that no other document links to a Key decisions fragment that moves.

### HdEH item 1

- Confirm the `--infer-version` bullet in `docs/md2x-spec.md` (Constraints and assumptions) states the trade-offs of dropping global and system git config (false `working` from `core.excludesFile`, `core.autocrlf`/`core.eol`, global LFS filters; global `safe.directory` dropped so another-uid repos warn `not inside a git work tree`). It is believed already present; add or tighten one sentence only if missing, and confirm the README's version-inference section agrees. If task 001 changed the safe.directory warning text, mirror it.

### Updates for task 001 and 002

- Document in the spec's `--infer-version` bullet, the architecture version-inference section, and the README version-inference section (as brief as the surrounding detail): the new refusal when the git directory resolved from the input differs from that of the work-tree top (`core.worktree` redirect), the empty `config.worktree` being accepted, and the NUL-delimited key read (architecture only).
- Architecture and `AGENTS.md`/`docs/project-structure.md`: add `src/cli/lib/input-discovery.sh` to every lib file list and to the architecture component description; remove statements that `@liquid-labs/bash-toolkit` still contributes `lists` helpers at build time (architecture build-time dependency paragraph) and keep only the historical rationale in Key decisions, phrased as past replacement; update `AGENTS.md` "the import list" wording if it is stale. State that `md2xAsync` caps buffered output at 64 MiB in the spec's Node API section (and README Node section if it documents buffering).
- Mention the CI timeouts/concurrency and the `release.sh` dry-run ordering only where the docs currently describe CI or the dry run (`docs/architecture.md` CI bullet; `RELEASING.md` is task 002's).
- Update `CHANGELOG.md` only if a user-visible doc claim changed (normally not).
- Do not alter the README CLI flag table (single-source rule) or any flag text.
- Do not commit or push.

## Validation

- `make test` and `make lint` pass (the only source edit is a comment).
- `grep -n "stubbed" docs/architecture.md` has no hit about the legacy-pandoc suite; `grep -rn "process substitution" docs src/cli/md2x.sh README.md` shows no claim that the CLI uses or needs it (AGENTS.md bash-compat advice about `< <(` may remain).
- `grep -rn "bash-toolkit" docs AGENTS.md README.md` shows only historical or rationale mentions; `grep -rn "input-discovery.sh" docs AGENTS.md` shows the new module listed.
- Every claim about `--infer-version` git invocations matches `src/cli/lib/preflight.sh` after task 001 (read it side by side).
- Markdown links and anchors in the edited docs still resolve (check fragments for any subheading changes).
- The report lists anything left for the maintainer: private vulnerability reporting setting, unverified apt/brew lines, README `python3-venv` claim.

## Assumptions

- Tasks 001 and 002 have landed in this worktree; read their code and CHANGELOG entries rather than assuming.

## References

- `docs/architecture.md`, `docs/md2x-spec.md`, `docs/project-structure.md`, `AGENTS.md`, `README.md`, `RELEASING.md`
- `src/cli/md2x.sh`, `src/cli/lib/preflight.sh`, `src/cli/lib/input-discovery.sh`, `src/node/md2x.js`
- [Task 001](./001-harden-cli-sources.md) and [Task 002](./002-polish-release-and-ci.md)

## Checkpoint hints

- After the 5E3C corrections in `docs/architecture.md` and the `md2x.sh` comment.
- After the task 001 and 002 sync edits across spec, README, AGENTS, project-structure.
- After the optional Key decisions regrouping.

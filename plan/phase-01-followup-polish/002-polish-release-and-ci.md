# Polish Release And CI

## Purpose and scope

Resolve followup `FUld` items 1, 3, and 4, followup `S0YR`, and the `SECURITY.md` response-time softening (`FUld` item 2, wording only).

- Role: `developer-bash`. Suggested tier: `sonnet-med` (small, well-specified edits to a release script, a workflow, and prose).
- Background: [followup status notes](../notes/followup-status.md).
- Do **not** change the GitHub private vulnerability reporting setting, and do not edit the unverified `apt`/`brew` install lines or the README `python3-venv` claims (`FUld` item 5). List all three as maintainer actions in the report.

## Requirements

1. **`scripts/release.sh` dry run (FUld 1).** In the dry-run branch, run the publish rehearsal against the bumped tree before `revert_bump`: move `bun publish --dry-run --access public --tag "$DIST_TAG"` so it runs after the pack check and before the revert (the tag is computed from the new version, so `DIST_TAG` must be computed earlier, or recomputed, at that point). Revert the bump afterwards, also when the rehearsal fails. The real-run flow must not change. Keep the later `# --- publish` section's dry-run message accurate (it must not claim to run a rehearsal that already ran, or rerun it at the pre-bump version). Verify with `scripts/release.sh --dry-run prerelease` only if the working tree is clean and the credentials/prompts allow; otherwise `bash -n scripts/release.sh`, `scripts/release.sh --print-dist-tag 1.0.0-rc.1` and a careful read are sufficient, and the report says which. Never run a non-dry release, push, tag, or publish.
2. **RELEASING.md accuracy (FUld 1, S0YR 2).** Make the dry-run description match the new ordering ("the same file list and the given tag" is then true). Verify the artifact list in "Manifests and artifacts" against `package.json` `files` (`bin/*`, `dist/*`, `CHANGELOG.md`) and the actual `make all` outputs (`bin/md2x`, `dist/md2x.mjs`, `dist/md2x.cjs`, `dist/index.d.ts`); correct anything stale, including line 7-ish verification prose if it names artifacts.
3. **CHANGELOG CI wording (FUld 3).** In `CHANGELOG.md` Added, rephrase the CI workflow bullet as intended behavior ("A GitHub Actions workflow intended to run ...", noting it has not run yet) until a CI run has been observed.
4. **`.github/workflows/ci.yml` (FUld 4).** Add `timeout-minutes` to every job (for example 30 for `qa`, 20 for `legacy-pandoc`); add a top-level `concurrency` group keyed on workflow and ref with `cancel-in-progress: true` for pull requests only (do not cancel `main` push runs); and change the legacy-pandoc install to `sudo apt-get install -y "${RUNNER_TEMP}/pandoc.deb"` (or `dpkg -i ... || sudo apt-get -f install -y` followed by a re-check) so unmet dependencies resolve. Keep the version assertion line. Validate the YAML parses (`python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/ci.yml` or equivalent).
5. **Pandoc floor wording (S0YR 1).** The legacy-pandoc job (2.0.6) now exists, so the floor is validated once CI runs. Keep every statement of the floor honest: in `src/cli/lib/preflight.sh` (the comment above `MD2X_PANDOC_MIN_VERSION`), `README.md` (dependency table row), and `CONTRIBUTING.md`, say the floor is derived from changelogs, that only 3.10.1 has been exercised by hand, and that the legacy job is intended to exercise 2.0.6 and is unproven until the workflow has run. Edit the code comment only; do not change `MD2X_PANDOC_MIN_VERSION`. (`docs/architecture.md` and `docs/md2x-spec.md` wording belongs to task 003.)
6. **SECURITY.md (FUld 2, wording only).** Replace the "within a few days" acknowledgement promise with best-effort language and no guaranteed timeline (for example: reports are handled on a best-effort basis, with no guaranteed response or fix time). Keep the advisory URL and the email fallback; add a short sentence that the email address is the fallback if the advisory form is unavailable. Do not claim the advisory flow is enabled.
7. **CHANGELOG.** Note in `Unreleased` only user-visible changes (the CI/CHANGELOG rephrase is itself the change). No entry for internal release-script ordering unless useful to maintainers.
8. Do not commit or push.

## Validation

- `make test` passes (unchanged code paths; the only source edit is a comment in `preflight.sh`).
- `bash -n scripts/release.sh`; `scripts/release.sh --print-dist-tag 1.0.0` prints `latest` and `--print-dist-tag 1.0.0-rc.1` prints `rc`.
- The workflow YAML parses; `grep -n "timeout-minutes\|concurrency\|apt-get" .github/workflows/ci.yml` shows every job covered.
- `grep -n "within a few days" SECURITY.md` returns nothing; `grep -n "runs the suite under macOS" CHANGELOG.md` returns nothing.
- `RELEASING.md` artifact list matches `package.json` `files` and the build outputs.
- The report lists the maintainer-confirmation items left untouched: private vulnerability reporting setting, apt/brew install lines, README `python3-venv` claims.

## Assumptions

- Task 001 is complete and merged into the worktree; it may have edited `CHANGELOG.md`, so merge entries rather than overwriting.
- No CI run has been observed, so nothing may be asserted as proven.

## References

- `scripts/release.sh`, `RELEASING.md`, `.github/workflows/ci.yml`, `SECURITY.md`, `CHANGELOG.md`, `README.md`, `CONTRIBUTING.md`, `src/cli/lib/preflight.sh`
- `package.json` (`files`), `Makefile` (build outputs)

## Checkpoint hints

- After the `release.sh` reordering and RELEASING.md sync.
- After the `ci.yml` edits.
- After the SECURITY.md, CHANGELOG, and floor-wording edits.

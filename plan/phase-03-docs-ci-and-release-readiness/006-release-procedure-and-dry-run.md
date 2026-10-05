# Release Procedure And Dry Run

## Purpose and scope

Make `RELEASING.md` and `scripts/release.sh` accurate, give the procedure as a numbered step list, and rehearse it with a dry run where credentials allow. Covers audit items D11, R5, and R11 (documentation side). Touches `RELEASING.md` and `scripts/release.sh` only (plus dating the `CHANGELOG.md` `Unreleased` heading is **not** done here; the release itself does that).

Hard dependencies: [package metadata](./005-package-metadata-and-pack-verification.md) (final `package.json`, `prepack` finding) and [community docs](./002-community-docs.md) (`CHANGELOG.md` exists).

## Requirements

- **Verification status of `bun publish`.** `1.0.0-alpha.11` was published with `npm publish` at commit `a21f731`; the release script switched to `bun publish` afterwards, so the `bun publish` path has **never run live**. The "unverified" statements in `RELEASING.md` and the `scripts/release.sh` header remain literally true: reword them accurately (state which versions used which tool, and what has and has not been verified), do not delete them.
- `RELEASING.md` becomes a numbered procedure: preconditions (clean tree, on `main`, pushed, CI green, `CHANGELOG.md` dated, `make qa`), version bump (`npm version`/preversion hook), build and pack check, dry run, publish, dist-tag handling, tag push, and post-publish verification (install from the registry and run `md2x --version`).
- Document the **dry run**: exact commands, what each proves (`npm pack --dry-run`, `bun publish --dry-run`, the release script's own dry-run mode, adding one if it lacks it), and what it cannot prove.
- Document the **`1.0.0` to `latest` path**: how `scripts/release.sh` decides the dist-tag (prerelease versions must not take `latest`; `1.0.0` must). Read the script, test the tag logic with each of `1.0.0-rc.1` and `1.0.0` in dry-run mode, and fix it if wrong.
- Recommend a **user-run throwaway prerelease** (for example `1.0.0-rc.1` under the `rc` dist-tag) before `1.0.0` to exercise `bun publish` for real, and state the steps. The agent must **not** publish anything.
- Fix any other inaccuracy found by checking every command and path in `RELEASING.md` and the script against the repo (Makefile targets, `package.json` scripts, `prepack` finding from the metadata task). Use lowercase `liquid-labs` and `git+https` URLs.
- Perform a dry run where credentials allow (`bun publish --dry-run`, `npm publish --dry-run`). If there are no credentials or the registry refuses a dry run, record exactly what ran and what could not.
- Note in `RELEASING.md` that pushing `main` (117+ commits ahead of `origin`) and observing CI green are user actions that precede release.

## Validation

- Dry-run commands were executed; the report includes the commands and their output summaries, for both a prerelease version string and `1.0.0` for the tag logic.
- `bash -n scripts/release.sh` passes, and `shellcheck scripts/release.sh` is clean if shellcheck is installed.
- `grep -n -i "Liquid-Labs" RELEASING.md scripts/release.sh` returns nothing; the word "unverified" (or equivalent) still appears with the accurate scope.
- Every command in `RELEASING.md` was checked against the repo or ran in dry-run.
- `make qa` passes; no files other than the two named are modified.

## Metadata

architectural_impact: false

## Assumptions

- No npm/bun publish credentials are assumed; the dry run may be partial.
- The agent never runs a real publish or pushes tags.

## References

- [Design decisions, release](../notes/design-decisions.md#release)
- [Audit coverage](../notes/audit-coverage.md): rows D11, R5, R11.
- [Overview, bun publish finding](../overview.md)

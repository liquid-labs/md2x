# Docs, CI, and Release Readiness

## Goals

Make md2x shippable as a golden 1.0: accurately documented, continuously verified, and packaged and released through a rehearsed procedure. This phase covers user decisions 3 and 8 and the rest of the docs-audit and release-audit items:

- **README overhaul.**
  - Features: stdin and `--to-stdout`.
  - Installation: npm and bun, prerequisite one-liners, the pdftk-java link, the precise dependency set including the brew/gnu-getopt finding, and the bash version.
  - A platform matrix: macOS needs gnu-getopt, Linux is proven by CI, Windows is unsupported.
  - A complete CLI table, with `-h`, `-o`, and `--version`.
  - An exit-code table, troubleshooting, quickstart sample output, and the first-run note.
  - The full Node option list, sync and async.
  - The SSRF caveat, documented abbreviation and `--opt=value` behavior, and known limitations, including the fixed PDF header and footer and the overlay font's limited non-Latin glyph coverage (N8 features are deferred).
  - Lowercase org casing, and no "other formats" claims.
- **Spec, AGENTS.md, and project-structure updates.**
- **CLI flag table** single-sourced and enforced by a drift test.
- **Community files.** `CHANGELOG.md` (including breaking changes such as missing-dependency moving from exit 2 to exit 3, `-s` now meaning `--to-stdout`, the removed `-q`/`-l`/`-n`/`-i` shorts, and the Node default title), `CONTRIBUTING.md`, and `SECURITY.md`.
- **CI.** A GitHub Actions workflow on macOS and Linux running `make qa`, plus the bash 3.2 run.
- **Lint and dependencies.** `eslint .` passes, and ESLint 10 is adopted if safe.
- **`package.json` metadata.** Typo, keywords, engines, URLs, `prepack`.
- **RELEASING.md and release script.** Accuracy fixes, a numbered step list, and the dry-run, `bun publish`, and `1.0.0`-to-`latest` paths.
- **psgq.** The TOC slug-probe optimization.

This phase comes last so the documentation describes the final, tested behavior from Phases 1 and 2.

## Inputs

- The final CLI and Node behavior from Phases 1 and 2: flags, shorts, exit codes, dependency set, output options, link and image semantics, and the Node API and packaging.
- [Design decisions](../notes/design-decisions.md): the flag-table single source, CI, release, and dependency set. The [brew and getopt resolution](../notes/brew-and-getopt-resolution.md) finding. The [followup verification](../notes/followup-verification.md) note.
- The existing `README.md`, `docs/md2x-spec.md`, `docs/project-structure.md`, `AGENTS.md`, `RELEASING.md`, `scripts/release.sh`, `package.json`, and `eslint.config.mjs`.
- Registry fact: `1.0.0-alpha.11` was published with `npm publish`, so the `bun publish` path has never run live.

## Outputs

- `README.md`, `docs/md2x-spec.md`, `docs/project-structure.md`, and `AGENTS.md` updated to the final behavior and dependency set, with no "other Pandoc formats" claims and consistent lowercase `liquid-labs` casing.
- A bats drift test asserting the parser, `--help`, and README flag sets agree.
- New `CHANGELOG.md`, `CONTRIBUTING.md`, and `SECURITY.md`.
- `.github/workflows/ci.yml`: an ubuntu and macOS matrix with bun and `make qa`, plus a macOS `/bin/bash` 3.2 bats run.
- `eslint .` clean. `make lint` scope extended to the repository's JS and MJS files. ESLint bumped if compatible.
- `package.json` with corrected description, keywords, `engines`, `git+https` repository URL, lowercase URLs, `prepack`, and `files` covering the types and bundles. `npm pack --dry-run` contents verified.
- `RELEASING.md` and `scripts/release.sh`:
  - an accurate statement of `bun publish` verification status
  - a numbered procedure
  - a documented dry run
  - the `1.0.0` to `latest` path, checked
  - a recommended user-run prerelease publish before `1.0.0`
  - a dry run performed where credentials allow
- `allocate_slug` probing in O(1) amortized time, with byte-identical TOC output.
- `make qa` green.

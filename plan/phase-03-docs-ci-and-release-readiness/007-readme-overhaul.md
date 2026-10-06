# Readme Overhaul

## Purpose and scope

Rewrite `README.md` to describe the final, tested behavior of md2x 1.0. Covers audit items D1 to D5, D7, D8, D9 (casing), D12, D18, D19, S10 (document abbreviation behavior), S16 (docs side), and the N8 limitation note. Touches only `README.md`.

Hard dependencies: [GitHub Actions CI](./001-github-actions-ci.md) (the platform matrix says Linux is proven by CI) and [community docs](./002-community-docs.md) (the README links `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`). The [spec/AGENTS.md update](./008-spec-agents-and-structure-docs.md) and the [drift test](./009-flag-table-drift-test.md) follow this task. The README flag table is the single human-readable source ([flag table decision](../notes/design-decisions.md#flag-table-single-source)); keep it in a stable, machine-parseable shape (one row per flag, short and long in the first column in backticks) because the drift test parses it.

## Requirements

Derive every statement from the merged code and `bin/md2x --help`, not from older docs. Run the built CLI to confirm each example.

- **Features:** stdin (`-`) and `--to-stdout`, `-o/--output`; PDF, HTML, DOCX only. No "other Pandoc formats" claims.
- **Installation:** npm and bun (`npm i -g @liquid-labs/md2x`, `bun add -g ...`), prerequisite install one-liners for macOS (brew) and Linux (apt), a link to the pdftk-java project, and the **precise dependency set**. Confirm the set by grepping the final code (preflight checks, `command -v`, `python3`, getopt probing), starting from the [expected table](../notes/design-decisions.md#dependency-set-and-version-floor): bash 3.2+, pandoc at or above the floor version (read the floor from the code), `gs`, `pdftk`, `python3`, GNU getopt on macOS, WeasyPrint auto-managed in `~/.md2x/venv` with network on first PDF run, `git` and `jq` only for `--infer-version`; `perl` and `brew` not required. State the brew/getopt finding precisely per [brew and getopt resolution](../notes/brew-and-getopt-resolution.md): GNU getopt is required on macOS, Homebrew is only the usual way to install it, md2x never calls brew to install anything, and `MD2X_GETOPT` can point at a getopt.
- **Platform matrix:** macOS (needs gnu-getopt), Linux (proven by CI, state it as the workflow's intent without claiming a run that has not happened), Windows unsupported, WSL untested.
- **CLI reference table:** complete, including `-h/--help`, `-o/--output`, `--version`, and the TOC rows linking to the TOC section. Shorts are exactly `-D -F -h -o -p -s -t`; `-s` is `--to-stdout`. Mention that `-q -l -n -i` are not accepted. Document conflict rules for `-o`, `--to-stdout`, `--output-path`.
- **Exit-code table:** 0 success, 1 runtime or conversion failure, 2 usage error, 3 missing or unusable dependency, plus a troubleshooting section keyed to common errors and messages (read the real messages from the code).
- **Quickstart** with real sample output captured from a run, and a **first-run note** (WeasyPrint bootstrap, network, time).
- **Node API:** the full option list, sync `md2x()` and async `md2xAsync()`, `markdown` vs `sources`, `output`, `quiet`, error shape (`exitCode`, `stderr`), ESM and CJS import examples, TypeScript types, default title `output`.
- **Behavior notes:** GNU getopt abbreviations (`--single` works; `--no` currently resolves to `--no-toc`), `--opt=value`, and the attached short value form; link and image rules and their known limitations (`--flatten-dirs`, `--single-page` links, renamed outputs); the SSRF caveat (remote resources are fetched during conversion; do not convert untrusted Markdown with remote references on a sensitive network), linking `SECURITY.md`.
- **Known limitations:** header and footer fixed; the overlay font has limited non-Latin glyph coverage (N8 features deferred); a returned path containing a newline mis-splits in the Node wrapper; `--jobs`/progress not supported (N4 deferred).
- Lowercase `liquid-labs` in all URLs; fix typos (D13).

## Validation

- `grep -n -i "other formats\|Liquid-Labs\|Mardown\|perl" README.md` returns nothing, or only statements that `perl` is not required.
- Every flag in `bin/md2x --help` appears in the README table and vice versa (manual diff now; the [drift test](./009-flag-table-drift-test.md) will enforce it).
- Every shell command, and every Node snippet (run under native ESM and CJS against a packed tarball or `dist/`), was executed or syntax-checked; the report says which.
- Every relative link resolves (`CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `RELEASING.md`, `docs/*`).
- Dependency list in README matches the grep of the final code; the report lists the greps.
- Markdown style standards followed; `make qa` passes.

## Metadata

architectural_impact: false

## Assumptions

- Phases 1 and 2 and tasks 001, 002 of this phase are merged.

## References

- [Design decisions](../notes/design-decisions.md): every section; notably dependency set, exit codes, short flags, links and images, Node wrapper.
- [Audit coverage](../notes/audit-coverage.md): D rows.
- [Brew and getopt resolution](../notes/brew-and-getopt-resolution.md)
- User answers: [exit codes](../notes/exit-code-contract-answer.md), [short flags](../notes/short-flag-set-answer.md), [N4/N8](../notes/n4-n8-scope-answer.md).

## Checkpoint hints

- After installation, dependency, and platform sections.
- After CLI and exit-code tables.
- After the Node API section.

## Status

- Outcome: succeeded (2026-10-05).
- Changed: [README.md](../../README.md) rewritten against the built CLI, `bin/md2x --help`, `src/node/index.d.ts`, `src/node/md2x.js`, and `src/cli/lib/preflight.sh`.
- Validation: banned-term grep clean (only the "perl not required" row remains); every flag in `--help` is in the README table and vice versa; relative links resolve; CLI examples run; Node ESM and CJS snippets run against a packed tarball; TypeScript snippet type-checked with `tsc --noEmit`; `make qa` passed.
- Not executed: the `apt install` line (macOS host); the `brew install` line was not run either.

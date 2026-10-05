# Spec Agents And Structure Docs

## Purpose and scope

Update `docs/md2x-spec.md`, `AGENTS.md`, and `docs/project-structure.md` to the final behavior. Covers audit items D1, D2, D20 (spec side), D9 (casing), and S16. Touches only those three files.

Hard dependencies: [README overhaul](./007-readme-overhaul.md) (the spec links to its flag table), [GitHub Actions CI](./001-github-actions-ci.md) and [lint and dependency bumps](./004-lint-and-dependency-bumps.md) (AGENTS.md describes them), and [community docs](./002-community-docs.md). The [drift test](./009-flag-table-drift-test.md) follows. The Phase 4 task `update-architecture-docs` later performs a final conformance pass on the spec and `docs/architecture.md`; do not edit `docs/architecture.md` here.

## Requirements

- **`docs/md2x-spec.md`:**
  - Replace the duplicated flag reference with a link to the README CLI table; keep only normative content not in the README: the exit-code contract (0/1/2/3), conflict rules for `-o`, `--to-stdout`, `--output-path`, and `-` with other inputs, empty-input and no-args behavior, title rules, stdout contracts (`Created <file>`, `--list-files`).
  - Final dependency set including `jq` (conditional), GNU getopt on macOS (D1, D2), bash 3.2 floor, pandoc floor; `perl` and `brew` not required; `--help` runs without preflight or getopt.
  - Short flags `-D -F -h -o -p -s -t`; `-s` is `--to-stdout`.
  - Remove any "other Pandoc formats" claim. State that N4 (`--jobs`, progress) and N8's header/footer features are deferred, not supported.
- **`AGENTS.md`:** update commands (`make qa`, lint scope, bash 3.2 override, gated real-toolchain tests), repository layout (new parser module, Lua filter, work-directory convention, `.github/workflows/ci.yml`), the coding constraints (bash 3.2 compatibility, `nounset`-safe arrays, no `perl`), the doc-single-source rule for the flag table, and links to `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `RELEASING.md`. Lowercase org casing.
- **`docs/project-structure.md`:** reflect the final source tree: list `src/` by actually running `find src -type f -not -path '*/node_modules/*'`, plus `.github/`, new root docs, `scripts/`, and the rewritten Node files.
- Every statement must match the final code; verify by running or grepping, and list the greps in the report.

## Validation

- `grep -n -i "perl\|brew\|shelljs\|other formats\|Liquid-Labs" docs/md2x-spec.md AGENTS.md docs/project-structure.md` returns only statements that describe these as removed, optional, or not required.
- `grep -n "exit" docs/md2x-spec.md` shows the 0/1/2/3 contract and no text says missing dependencies exit 2.
- Each path named in `docs/project-structure.md` exists (script the check with `test -e`), and each existing source file is listed.
- Every relative link in the three files resolves.
- `make qa` passes; markdown style standards followed.

## Metadata

architectural_impact: false

## Assumptions

- Phases 1 and 2 are merged; the README table is final (task 007).
- The Phase 4 task will adjust `docs/architecture.md` and may revisit the spec.

## References

- [Design decisions, flag table single source](../notes/design-decisions.md#flag-table-single-source) and [dependency set](../notes/design-decisions.md#dependency-set-and-version-floor)
- [Audit coverage](../notes/audit-coverage.md): D1, D2, D20, S16.
- [Phase 4 task](../phase-04-doc-updates/001-update-architecture-docs.md)

# Package Metadata And Pack Verification

## Purpose and scope

Correct `package.json` metadata and verify what `npm pack` ships. Covers audit items R3, R11 (`git+https`), D13, D14, D15, and N10. Touches `package.json` (and `bun.lock` only if it changes), plus a `LICENSE` check.

Hard dependency on [lint and dependency bumps](./004-lint-and-dependency-bumps.md) (same `package.json`/`bun.lock`/`Makefile` chain). The [release task](./006-release-procedure-and-dry-run.md) depends on this one.

## Requirements

- `description`: fix the "Mardown" typo and remove any "other formats" claim. Describe the real formats (PDF, HTML, DOCX).
- `keywords`: add accurate keywords (for example markdown, pdf, html, docx, pandoc, cli, converter).
- `engines`: add `node` with the minimum version the built bundles and `node:child_process` wrapper actually need (verify, do not guess). Do not add an `engines.bun` constraint unless required.
- `repository.url`: `git+https://github.com/liquid-labs/md2x.git`. Lowercase `liquid-labs` in `bugs.url` and `homepage` too; also lowercase the `liq.orgBase` URL if it names the org.
- `prepack`: add `"prepack": "make all"` (N10). First verify that `bun publish` (and `npm pack`/`npm publish`) run the `prepack` lifecycle script, by running `bun pm pack --dry-run` / `bun publish --dry-run` and observing; record the result in the task report for the [release task](./006-release-procedure-and-dry-run.md). If bun does not run it, say so and keep the release script's explicit build instead.
- `files`: ensure it covers `bin/*`, the Phase 2 `dist` bundles (ESM and CJS), and `index.d.ts`/types. Do not change `exports`, `main`, or `types` unless they are wrong; Phase 2 owns them.
- Verify `LICENSE.txt` is included in the tarball (npm includes license files automatically; confirm by listing).
- Verify contents with `npm pack --dry-run --json` (or `bun pm pack --dry-run`): no `src/`, tests, `coverage/`, `worktrees/`, `plan/`, or `.flow/`; includes `bin/md2x`, the bundles, types, `README.md`, `LICENSE.txt`, `package.json`. Record the file list in the report.
- Install the packed tarball into a temp project and smoke-test `npx md2x --version` and `import`/`require` of the package (Phase 2 validated this; re-run after metadata changes).

## Validation

- `jq` checks: `.repository.url` starts with `git+https://github.com/liquid-labs/`; `.keywords | length > 0`; `.engines.node` is set; `.scripts.prepack == "make all"` (if bun runs it); `grep -n "Mardown\|Liquid-Labs" package.json` returns nothing.
- `npm pack --dry-run` file list matches the expectations above.
- Tarball install into a temp directory: `md2x --version` prints `package.json`'s version; `require('@liquid-labs/md2x')` and ESM named import both work.
- `bun install --frozen-lockfile`, `make qa` pass.

## Metadata

architectural_impact: false

## Assumptions

- Phase 2 produced the dual bundles, `exports`, and `index.d.ts`; re-read the current `package.json` before editing.
- Registry state: `1.0.0-alpha.11` was published with `npm publish`; this task publishes nothing.

## References

- [Design decisions, release](../notes/design-decisions.md#release) and [Node wrapper packaging](../notes/design-decisions.md#node-wrapper)
- [Audit coverage](../notes/audit-coverage.md): rows R3, R11, D13, D14, D15, N10.

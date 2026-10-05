# Interface Contract

## Goals

Lock the 1.0 public interface of both surfaces, the CLI and the Node library, into a deliberate, tested contract. This phase covers user decisions 1, 2, 4, 5, and 7 and the remaining interface-audit SHOULD and NICE items:

- `--version`
- usage hint and non-zero exit for no-args and empty-directory invocations
- `-o/--output`, and `--to-stdout` as a pure stream
- input discovery (case-insensitive `.md` and `.markdown`, deduplication, `-` mixing) and format validation
- output-collision protection
- cross-document links and images resolving against each source file's directory, through a Pandoc Lua filter that replaces the eval-built `perl` converter
- lazy, unquoted version inference with no stderr noise
- a pandoc version floor
- dead-code cleanup
- a WeasyPrint warning-free bundled stylesheet
- a modernized Node wrapper: working native ESM named import, CJS, TypeScript types, `exports` map, child_process with argv arrays, `markdown` fed through stdin, `sources: ['-']` and option validation, an async variant

This phase follows Phase 1 because it builds on that phase's error helper, exit codes, option parser, work directory, and stdin path. It comes before Phase 3 so the documentation describes the final behavior.

## Inputs

- Phase 1 outputs: error helper and exit-code contract, explicit option parser, bash 3.2-compatible CLI and harness interpreter override, per-run work directory, byte-exact stdin, inline HTML CSS, title-safe sinks.
- [Design decisions](../notes/design-decisions.md) on output options, input discovery, collisions, links and images (with the 2026-10-04 Lua-filter spike results), version inference, the dependency set and version floor, WeasyPrint warnings, and the Node wrapper.
- `src/cli/lib/github.css`, `src/cli/lib/toc-preprocess.py`, `src/node/*`, `Makefile`, `package.json`.
- The real toolchain on the development host (pandoc 3.10.1, gs, pdftk, WeasyPrint venv), for gated end-to-end verification.

## Outputs

- **CLI.**
  - `--version`, injected from `package.json` at build time.
  - Usage summary and exit 2 for no arguments and for directories with no Markdown.
  - Case-insensitive `.md`/`.markdown` discovery with deduplication.
  - Clear errors for `-` mixed with other arguments, for an unsupported format (case-insensitive, listing `pdf|html|docx`), and for invalid-UTF-8 or binary input.
  - `-o/--output <file|->` with format inference.
  - `--to-stdout` that writes only to stdout and requires exactly one output.
  - `-p` normalization.
  - A pre-conversion collision check.
- **Help text.** Exit codes, homepage, `--keep-intermediate` parity, all new flags, and no "other Pandoc formats" claim.
- **Links and images.**
  - A Pandoc Lua filter, inlined by the rollup, that rewrites every relative `.md`/`.markdown` link (fragments kept, code untouched) and resolves images against each source's directory, including in `--single-page` mode through per-source markers.
  - Missing-image warnings surfaced from pandoc's log.
  - `perl` and `eval` are gone.
- **Version inference.** Runs only with `--infer-version`, uses `jq -r` (unquoted), and resolves against the first input's repository. There is no `cat: package.json` noise. `git` and `jq` become conditional dependencies, checked lazily.
- **Hygiene.** A pandoc minimum-version preflight; no raw `type`, `basename`, or `mkdir` error leaks; dead code and the typo removed.
- **Stylesheet.** `github.css` pruned, so a PDF run emits no WeasyPrint `Ignored` warnings.
- **Node package.**
  - ESM and CJS bundles plus `index.d.ts`, with `exports`, `main`, and `types` in `package.json`.
  - A zero-runtime-dependency wrapper on `node:child_process`.
  - `md2x()` and `md2xAsync()`.
  - Option validation and errors that carry `exitCode` and `stderr`.
  - `output` and `quiet` options, and a default title of `output`.
  - Verified from a packed tarball under native ESM `import` and CJS `require`.
- **Tests.** Regression and feature tests (bats, gated real-toolchain bats, `bun test`) for every item above. `make qa` is green, including under the bash 3.2 harness override.

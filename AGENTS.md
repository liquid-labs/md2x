# md2x

Working notes for developers and AI agents contributing to md2x. md2x is a CLI (with a thin Node.js library wrapper) that converts Markdown documents to PDF, HTML, and DOCX via [Pandoc](https://pandoc.org/), adding consistent GitHub-style styling, automatic page headers/footers, batch directory processing, and single-page concatenation of multiple files.

## Build and test

The CLI (`bin/md2x`) and Node library entry point (`dist/md2x.{mjs,cjs}`) are both build outputs — do not edit them directly; edit the sources under `src/`.

Both [bun](https://bun.sh/) and `node` (20 or later) must be on `PATH`: bun is the package manager, bundler, and Node-suite test runner, while the built `dist/md2x.{mjs,cjs}` targets node. The `make` targets are the primary interface; the bun commands are thin equivalents. Run `make qa` before proposing a change: it is the full local check (tests plus lint), and CI runs it too (see [`.github/workflows/ci.yml`](./.github/workflows/ci.yml)).

```bash
bun install
make all        # or: bun run build -> make all: rolls up src/cli into bin/md2x, builds dist/md2x.mjs and dist/md2x.cjs (bun build) plus dist/index.d.ts from src/node
make test       # builds, then runs both test suites (or: bun test ./src/node for the Node suite alone)
make qa         # test + lint: the gate before every change
```

`make test` is non-interactive and runs two suites, either of which can be run alone:

```bash
make test-cli   # bats cases under src/cli/test/bats, run against the built bin/md2x
make test-node  # bun test over src/node, with coverage
```

`make test-cli` needs the build, so it depends on `all`. `make test-node` runs `bun test` directly against the sources in `src/node` (no compile step) and writes a text coverage report plus a `coverage/` directory, which is gitignored.

The bulk of the suite runs the CLI against **stub `pandoc`, `gs`, and `pdftk` executables** placed on a test-controlled `PATH`, so it does **not** require a working Pandoc PDF pipeline — only `git`, `jq`, `python3`, and GNU `getopt` (on macOS, e.g. the Homebrew `gnu-getopt` keg, which the CLI finds by probing known install paths), which the CLI itself shells out to or requires. `perl` is not required. The stubs record their argument vectors so tests can assert on what the CLI asked for; see `src/cli/test/helpers/common.bash` for the harness contract and `src/cli/test/bats/harness-smoke.bats` for worked examples.

**Gated real-toolchain tests.** Some cases run against the real tools instead of the stubs: `real-toolchain-e2e.bats` (TOC slug agreement, DOCX bookmarks, PDF links) and `links-and-images.bats` (the Lua link/image filter against real Pandoc). They skip, naming what is missing, when the real toolchain (Pandoc, and for PDF cases WeasyPrint, Ghostscript, and `pdftk`) is absent, so `make qa` passes without it; run them on a machine with the tools installed before changing the conversion pipeline.

**Bash 3.2 override.** md2x supports bash 3.2, the macOS `/bin/bash`. The harness runs the CLI under the interpreter named by `MD2X_TEST_BASH`, so on macOS run the whole CLI suite under the system shell:

```bash
MD2X_TEST_BASH=/bin/bash make test-cli
```

CI's macOS job does this too. Without the override, the suite runs the CLI under whichever `bash` is on `PATH`.

Real conversions are also covered by an opt-in, interactive, macOS-only visual check that is deliberately outside the default test path:

```bash
make smoke-test # converts the tiny-doc fixture for real, opens each result, waits for you
```

It needs `pandoc`, `gs` (Ghostscript), `pdftk`, and `python3` on `PATH`. WeasyPrint (the PDF rendering engine) is **not** a manual prerequisite — the CLI bootstraps it automatically into `~/.md2x/venv` on the first PDF conversion, so the first run that produces PDF output stalls for a minute while that install completes.

Lint (JavaScript only: `make lint` runs `eslint .` over every `.js`/`.mjs` file in the repository, skipping `dist/`, `coverage/`, `node_modules/`, `bin/`, `worktrees/`, `plan/`, and `.flow/`; the bash CLI sources are not linted):

```bash
make lint       # check
make lint-fix   # check and auto-fix
```

Release-time packaging check (not part of `make qa`, because it runs `npm pack` and a TypeScript compile that can need the network): `make test-pack`. See [`RELEASING.md`](./RELEASING.md).

## Run

After `make all` (or `bun run build`), invoke the built CLI directly:

```bash
./bin/md2x report.md
```

Or exercise the Node wrapper, which shells out to `bin/md2x`:

```javascript
import { md2x } from '@liquid-labs/md2x'

md2x({ sources: ['report.md'] })
```

## Code organization

- `src/cli/md2x.sh` — the CLI entry point source; rolled up (via `@liquid-labs/bash-rollup`) into the single-file `bin/md2x` executable. It opens with a POSIX-sh interpreter guard (exit 3 for a non-bash shell or bash older than 3.2), then handles `--help`/`--version` before any dependency check.
- `src/cli/lib/` — CLI library scripts and assets pulled into the rollup: `index.sh` (the list of modules the rollup sources), `parse-options.sh` (the option parser and its flag table, which resolves GNU `getopt`), `parameters.sh` (the output-format list), `errors.sh` (the `md2x:` error and exit-code helpers), `preflight.sh` (dependency checks, the pandoc version floor, and `--infer-version` inference), `title-safe.sh` (title validation and encoding for the filename, metadata, and PostScript sinks), `output-plan.sh` (output-path planning and collision checks), `input-discovery.sh` (input-argument processing and the resolved input list), `link-filter.sh` (writes the Lua filter and the `--single-page` source markers), `md2x-links.lua` (the Pandoc Lua filter that rewrites `.md` links and resolves images), `generate-page.sh` (Pandoc/Ghostscript/pdftk conversion pipeline), `toc-preprocess.py` (the Markdown-in/Markdown-out table-of-contents stage `generate-page()` runs ahead of Pandoc), `ensure-weasyprint.sh` (bootstraps the `~/.md2x/venv` WeasyPrint install used as Pandoc's `--pdf-engine`), and `github.css` (the built-in stylesheet).
- `src/cli/test/` — the CLI test suite: `bats/` (bats-core cases), `helpers/` (shared bash helpers, loaded as `load '../helpers/common'`), `stubs/` (the fake `pandoc`/`gs`/`pdftk`), `manual/visual-smoke-test.sh` (the interactive check `make smoke-test` rolls up), and the `tiny-doc.md` and `toc-slug-corpus.md` fixtures.
- `src/node/` — the Node.js library wrapper (`index.js`, `md2x.js`, and the hand-written `index.d.ts`) that runs `bin/md2x` via `node:child_process`; built into `dist/md2x.{mjs,cjs}`. `bun:test` cases are colocated as `src/node/*.test.js` and excluded from the build inputs.
- `scripts/` — `release.sh` (the release procedure; see [`RELEASING.md`](./RELEASING.md)) and `test-pack.sh` (`make test-pack`).
- `.github/workflows/ci.yml` — the CI workflow: `make qa` on Ubuntu and macOS, the CLI suite under macOS `/bin/bash` 3.2, and a legacy-Pandoc job.
- `bin/`, `dist/`, `coverage/`, `test-out/` — build and test outputs, gitignored; regenerated by `bun run build` / `make test` / `make smoke-test`.
- `docs/` — deeper documentation: the [project specification](./docs/md2x-spec.md), [`project-structure.md`](./docs/project-structure.md), and [`architecture.md`](./docs/architecture.md).
- `plan/` — the active development plan and tracked [followups](./plan/followups.yaml).
- **Per-run work directory.** Every intermediate file (CSS, TOC-preprocessed Markdown, the `--single-page` concatenation, captured stdin, the Pandoc log, the PDF overlay) goes in one `mktemp -d` directory under `TMPDIR`, removed by a single `EXIT` trap unless `--keep-intermediate` is given. Never write intermediates to the working or output directory, and never derive a work-directory path from user input such as `--title`.

## Conventions

- The CLI is authored as modular bash source under `src/cli/`, combined into one distributable file by `bash-rollup` — always edit the source modules, never `bin/md2x` directly.
- **Bash 3.2 compatibility.** All CLI shell code must run under bash 3.2: no associative arrays, `mapfile`/`readarray`, namerefs, `${var,,}`/`${var^^}` case conversion, `|&`, or `sort -V`, and no comments or apostrophes that break parsing inside `< <( ... )` process substitutions. Run the suite under `/bin/bash` with `MD2X_TEST_BASH` (above).
- **`nounset`-safe arrays.** The CLI runs under `set -o nounset`, and bash before 4.4 treats an empty array as unset, so expand a possibly-empty array as `${ARR[@]+"${ARR[@]}"}`.
- **No `perl`, `brew`, or `shelljs`.** `perl` is not a dependency (links and images go through the Lua filter, options through the project parser); `brew` is never run to install anything; the Node wrapper uses `node:child_process`, not `shelljs`. Do not add any of them. New dependencies must be added to the README dependency table and the spec.
- **Errors and exit codes.** Report failures through the helpers in `src/cli/lib/errors.sh`, not raw tool output or the bash-toolkit echo helpers: `md2x-die-usage` (exit 2), `md2x-die-runtime` (exit 1), `md2x-die-dependency` (exit 3). The contract is in the [spec](./docs/md2x-spec.md#cli).
- **Documentation single source for the flag table.** The README's [CLI reference](./README.md#cli-reference) is the only human-readable flag table. Do not copy it into the spec, `--help`, or elsewhere as another table; link to it. A drift test checks that the parser's flag table (`MD2X_OPTION_TABLE` in `src/cli/lib/parse-options.sh`), `md2x --help`, and the README agree, so a flag change touches all three.
- JavaScript under `src/node/` is linted by eslint (`make lint`) with the flat config in `eslint.config.mjs`; no separate style guide beyond what the linter enforces.
- `--infer-version` behavior depends on `git status --porcelain` cleanliness versus `package.json`'s version, and md2x ignores global and system git config for it — keep this in mind when testing that flag locally, since a dirty working tree changes the observed output.
- `~/.md2x/venv` persists across runs — once WeasyPrint is installed, later PDF conversions skip the bootstrap silently. When testing `src/cli/lib/ensure-weasyprint.sh` changes or the first-run install notice, `rm -rf ~/.md2x/venv` first to force a cold start.
- Record user-visible changes in the `Unreleased` section of [`CHANGELOG.md`](./CHANGELOG.md).

## Documentation

- [README.md](./README.md) — consumer-facing overview, installation, and CLI reference (the single flag table).
- [CONTRIBUTING.md](./CONTRIBUTING.md) — development setup and how to propose changes.
- [docs/md2x-spec.md](./docs/md2x-spec.md) — specification: use cases, behavioral requirements, and the normative CLI/Node API contract (exit codes, conflict rules).
- [docs/project-structure.md](./docs/project-structure.md) — file and directory layout.
- [docs/architecture.md](./docs/architecture.md) — design-level material, including the PDF header/footer overlay mechanism.
- [CHANGELOG.md](./CHANGELOG.md) — release history; record user-visible changes under `Unreleased`.
- [SECURITY.md](./SECURITY.md) — supported versions, private vulnerability reporting, and the trust notes for untrusted Markdown.
- [RELEASING.md](./RELEASING.md) — release procedure: version bump (bun), build, tag, and publish (bun, including `bun publish`).
- [plan/](./plan/) — current development plan and followups, when active.

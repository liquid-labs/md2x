# Contributing

## Purpose and scope

This guide covers setting up a development environment for md2x, running its checks, and proposing changes. For the project's architecture and layout, see the [architecture overview](./docs/architecture.md) and the [project structure](./docs/project-structure.md); for release steps, see [RELEASING.md](./RELEASING.md).

## Development setup

Prerequisites match the [README installation list](./README.md#installation): `pandoc` (3.4 or later, the release that made weasyprint the default PDF engine; only 3.10.1 has been exercised by hand), Ghostscript (`gs`), `pdftk`, `python3`, and GNU `getopt` (on macOS, `brew install gnu-getopt`). `jq` and `git` are needed only for `--infer-version`. [Bun](https://bun.sh/) installs the Node dependencies and runs the Node tests.

```bash
bun install
make all
```

`make all` builds the CLI (`bin/md2x`, rolled up from `src/cli`) and the Node wrapper (`dist/`). Rebuild after changing anything under `src/`.

## Running checks

```bash
make qa          # the full local check: tests plus lint
make test        # the bats CLI suite and the Node tests
make test-cli    # the bats suite only
make test-node   # the Node tests only
make lint        # ESLint over the Node sources
make lint-fix    # ESLint with autofix
```

The bats suite runs the built `bin/md2x` against stub `pandoc`, `gs`, and `pdftk` executables, so `make test` needs no working PDF pipeline. A few real-toolchain end-to-end cases in `src/cli/test/bats/real-toolchain-e2e.bats` run against the real tools and skip (rather than fail) when a tool is missing.

### Bash 3.2

md2x supports bash 3.2, the macOS system shell, so keep shell code 3.2-compatible: no associative arrays, no `mapfile`, no `${var,,}` case conversion, and so on. The test harness runs the CLI under the interpreter named by `MD2X_TEST_BASH`:

```bash
MD2X_TEST_BASH=/bin/bash make test-cli   # macOS: runs the suite under /bin/bash 3.2
```

### Visual smoke test

`make smoke-test` converts a small fixture for real, opens each result, and waits for you. It is interactive, macOS-oriented, and not part of `make qa`.

### Packaging check

`make test-pack` packs the tarball and verifies ESM import, CJS `require`, and the TypeScript types. It can need the network, so it is not part of `make qa`.

## Making changes

- Every bug fix carries a regression test that fails without the fix.
- Run `make all` and `make qa` before proposing a change.
- Keep behavior, the `--help` text, [README](./README.md), and the [specification](./docs/md2x-spec.md) in agreement; a drift test checks the documented flags.
- Record user-visible changes in the `Unreleased` section of [CHANGELOG.md](./CHANGELOG.md).

### Style

JavaScript style is enforced by `make lint`. Markdown uses sentence-case headings, fenced code blocks with a language tag, and no trailing whitespace.

## Proposing changes

Open an issue at [liquid-labs/md2x](https://github.com/liquid-labs/md2x/issues) to discuss larger changes, then open a pull request from a branch. Continuous integration runs the test suite on the pull request; address any failures it reports. To report a security problem, follow [SECURITY.md](./SECURITY.md) instead of opening a public issue.

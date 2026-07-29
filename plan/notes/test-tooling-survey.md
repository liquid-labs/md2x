# Test Tooling Survey

## Purpose and scope

Findings from surveying md2x's existing test/build conventions and the decision record for the automated test suite this plan introduces: which runner each surface uses, how the external-binary boundary (`pandoc`, `gs`, `pdftk`) is handled, and the determinism hazards a test author must work around. Read this before implementing any task in the plan.

## What exists today

| Artifact | State |
| --- | --- |
| `src/cli/test/test.sh` | The only test artifact. Interactive: `open -Fn` on each generated file, then `read -r` waits for a human before killing the viewer processes. Rolled up by `bash-rollup` into `test-out/test.sh`; imports `strict` and `lists` from `@liquid-labs/bash-toolkit`. Not automatable. |
| `src/cli/test/tiny-doc.md` | A six-line fixture document. |
| `Makefile` `test:` target | `test: all $(CLI_TEST_OUT) $(CLI_TEST_DATA)` → clears `test-out/tiny-doc.*`, runs the interactive script. There is no Node-side test target. |
| `package.json` | `"test": "make test"`. No `pretest` script. No test runner in `devDependencies`. |
| `Makefile` `NODE_FILES` | `find $(NODE_SRC) -name "*.js" -not -path "*/test/*" -not -name "*.test.js"` — the build already excludes colocated `*.test.js` files, i.e. the intended Node test convention is already encoded in the build. Lines 11–12 also carry commented-out `NODE_TEST_SRC_FILES` / `test-staging` scaffolding. |
| `.gitignore` | Already ignores `/test-staging`, `/coverage`, and `/test-out`. No `.gitignore` change is needed for either runner. |

## Runner decisions

### Node wrapper → Jest, via `catalyst-scripts`

Jest is present in `node_modules` as a **transitive** dependency of `@liquid-labs/catalyst-scripts` (which declares `jest: ^27.5.1`), not as a direct devDependency of md2x. It is nonetheless the project's sanctioned JS test runner: `catalyst-scripts` ships two relevant subcommands, and `node_modules/.bin/jest` and `node_modules/.bin/babel` both resolve today with no further install.

- `JS_SRC=src/node catalyst-scripts pretest` — `rm -rf test-staging`, then Babel-compiles `./src/node` (test files included) into `test-staging/` with inline source maps.
- `JS_SRC=src/node catalyst-scripts test` — runs `jest --config=<catalyst>/config/jest.config.js --runInBand ./test-staging`.

That config sets `testEnvironment: "node"`, `collectCoverage: true`, `coverageDirectory: "coverage"`, `rootDir: process.cwd()`, and merges `package.json`'s `catalyst.jestConfig` over itself if present, so per-project overrides are possible without forking the config.

**Decision:** invoke Jest through `catalyst-scripts pretest` / `catalyst-scripts test` (mirroring how the Makefile already invokes `catalyst-scripts build` and `catalyst-scripts lint`) rather than adding a direct `jest` devDependency and a hand-written `jest.config.js`. Test files are colocated as `src/node/*.test.js`, which is what the existing `NODE_FILES` exclusion already anticipates. Zero new dependencies; works offline with the currently-installed tree.

One consequence worth remembering: Jest runs against the Babel-compiled copies under `test-staging/`, not against `src/node/` directly. A test file therefore imports its subject as `./md2x` (the sibling compiled copy), and a stale `test-staging/` must be rebuilt by `pretest` before every run.

### Bash CLI → bats-core

Considered and rejected:

- **Driving `bin/md2x` from Jest via `child_process`.** One runner for both surfaces and no new dependency — but `catalyst-scripts pretest` only stages `src/node`, so CLI tests would have to live under the Node source tree (semantically wrong), and bash-level assertions read poorly in JS.
- **A bespoke in-repo bash assertion harness.** No install risk and closest to today's convention, but it is ~80 lines of untested infrastructure that has to be correct before any test written against it can be trusted.

**Decision:** add `bats` (the npm distribution of [bats-core](https://github.com/bats-core/bats-core)) as a devDependency and run it with `npx bats`. It is bash-native (so CLI tests sit beside the CLI source in the same language), gives per-case isolation with `setup`/`teardown` — exactly the shape the temp-dir + `PATH`-stub pattern needs — emits TAP, and needs no global install.

**Install risk and pre-authorized fallback.** `bats` is not currently installed anywhere on this machine (no global binary, not in `node_modules`, not in the npm cache), so the foundation task needs registry access. If `npm install --save-dev bats` cannot complete, the foundation task is pre-authorized to fall back to a minimal in-repo bash harness (a `src/cli/test/helpers/harness.bash` providing test registration plus `assert_success` / `assert_failure` / `assert_output_contains` / `assert_file_exists`, and a runner that exits non-zero on any failure) — provided it reports the substitution prominently so the manager and the later test-writing tasks know which harness landed. Later tasks are written to read the landed harness's existing files and follow their conventions rather than assuming bats syntax.

## The external-binary boundary: stub by default

`docs/architecture.md` describes the CLI as an orchestrator: it runs a `PATH` preflight, rewrites relative `.md` links, builds a `pandoc` invocation, and — for PDF — renders a Ghostscript overlay and merges it with `pdftk multistamp`. Essentially all of md2x's own logic is *argument construction, source-list resolution, and output-path derivation*; the pixels are Pandoc's, Ghostscript's, and pdftk's. Testing that logic does not require the real tools, and running the real tools proves mostly that Pandoc works.

Three further facts push the same way:

1. `docs/md2x-spec.md` specifies exit code `2` and the named-binary message for a *missing* binary — a case that is only testable by controlling `PATH`.
2. Real conversions are slow, produce binary artifacts that are awkward to assert on, and are not reproducible across Pandoc versions.
3. Real PDF conversion **cannot run on this machine at all**: `pandoc`, `gs`, `pdftk`, `jq`, and `perl` are on `PATH`, but Pandoc's PDF engine (`weasyprint`) is not — this is exactly followup `BfN6`. A suite that hard-requires the full toolchain would be red on the maintainer's own laptop.

**Decision:** the bulk of the CLI suite runs against stub `pandoc` / `gs` / `pdftk` executables placed on a test-controlled `PATH`, which record their argument vectors to a log file and fabricate the output files their real counterparts would produce. A small, separately-tagged end-to-end set exercises the real toolchain and **skips** (does not fail) when the toolchain is unavailable. Trade-off accepted: the stub suite cannot catch a Pandoc-side regression or a malformed-but-accepted flag; the gated e2e set is what covers that, at whatever fidelity the running machine allows.

### What each stub must do to survive `set -o errexit`

The CLI runs under `errexit`/`nounset`/`pipefail`, and `generate-page.sh` unconditionally removes files it assumes the tools created. A stub that only logs its arguments will break the run. Required side effects:

| Stub | Must |
| --- | --- |
| `pandoc` | Create the file named by `-o`, and create the file named by `--log` (`pandoc-log.log` in the CWD) — `generate-page.sh` line 54 does `rm pandoc-log.log` unless `--keep-intermediate`. |
| `gs` | Create the file named by `-o` (the `${OUTPUT_PATH}/${TITLE}-overlay.pdf`), which is `rm`'d afterwards unless `--keep-intermediate`. |
| `pdftk` | For a `dump_data` invocation, print at least a numeric `NumberOfPages: N` line and a `PageMediaDimensions: <x> <y>` line — the CLI feeds both into `$(( ))` arithmetic. For a `multistamp ... output <file>` invocation, create `<file>` (it is then `mv`'d onto `${BASE_OUTPUT}`). |

The stubs should append their full argument vector (and their `argv[0]`) to a log file named by an environment variable (e.g. `MD2X_TEST_STUB_LOG`) so tests can assert on what the CLI *asked for*: the `-o` target, presence/absence of `--toc`, the `--metadata-file` contents, the `Version:` text baked into the Ghostscript PostScript string, and so on.

`perl` (the link rewriter) and `jq` are **not** stubbed — `perl` is genuinely part of md2x's own logic and is universally present, and `jq` is only reached by the version probe described below.

## Determinism hazards

- **The version probe runs on every invocation**, not just under `--infer-version`: `src/cli/md2x.sh` line 135 is `VERSION=$(OUTPUT=$(git status --porcelain) && [ -z "${OUTPUT}" ] && cat package.json | jq '.version' || echo 'working')`. It reads `package.json` from the **current working directory** and shells out to `git` and `jq`. Outside a git work tree (or with no `package.json`) it falls through to the literal `working`. Running each test case in a fresh temp directory outside the repo therefore makes `VERSION` deterministically `working`; running from the repo root makes it depend on whether the tree happens to be dirty. **Tests must `cd` into a per-case temp directory.** (`jq` being an undocumented dependency of this line is noted for the manager, not fixed here.)
- **Unquoted word-splitting.** `for ROOT_DIR in $SEARCH_DIRS` and `find ${ROOT_DIR} ...` mean paths containing spaces are already broken today. Keep every fixture path space-free; do not write a test that asserts space handling works.
- **Output-path assertions and the `aI57` fix.** Any test that asserts a *mirrored* (non-`--flatten-dirs`) output path is coupled to the fix. Tests written outside the fix task must choose inputs whose placement is invariant under the fix — an input file in the case's own working directory, or `--flatten-dirs`, or stdin/`--single-page` (neither of which goes through the mirroring branch at all).
- **`--to-stdout` implies `--quiet`**, so a `--to-stdout` case asserts on the (stubbed) file content echoed to stdout, not on a `Created …` line.
- **`--single-page` writes its concatenation buffer (`${TITLE:-input}.md`) into the CWD** and does not clean it up; a temp-dir-per-case setup absorbs that.

## Related documents

- [`docs/architecture.md`](../../docs/architecture.md) — the component boundaries and fail-fast error model this stubbing strategy is grounded in.
- [`docs/md2x-spec.md`](../../docs/md2x-spec.md) — the behavioral contract the test cases assert against.
- [`AGENTS.md`](../../AGENTS.md) — the build/test/lint conventions the new targets must fit into.
- [Mirrored output path contract](./mirrored-output-path-contract.md) — the `aI57` analysis and the intended path-derivation contract.

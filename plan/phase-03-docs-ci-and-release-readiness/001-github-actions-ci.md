# Github Actions Ci

## Purpose and scope

Add a GitHub Actions workflow that runs `make qa` on Linux and macOS and runs the bats suite once more under macOS's `/bin/bash` 3.2. Covers audit items R1 and R6. Touches only `.github/workflows/ci.yml`.

Role doc: `plugins/flow/roles/devops-engineer.md` if present in the Role/Standards Registry, otherwise the generic implementer role.

Parallel-eligible: no dependency on any other Phase 3 task. [AGENTS.md and project-structure updates](./008-spec-agents-and-structure-docs.md) and the [README](./007-readme-overhaul.md) depend on this task.

## Requirements

- Create `.github/workflows/ci.yml`, triggered on `push` to `main` and on `pull_request`.
- A job with a matrix of `ubuntu-latest` and `macos-latest`. Steps: checkout, set up bun (`oven-sh/setup-bun`), install system packages, `bun install --frozen-lockfile`, `make qa`.
- System packages, per [design decisions, CI](../notes/design-decisions.md#ci):
  - Ubuntu: `apt-get install -y pandoc ghostscript pdftk-java jq python3`.
  - macOS: `brew install pandoc ghostscript pdftk-java jq gnu-getopt` (python3 is preinstalled).
- A second step or job on macOS that runs the bats suite under `/bin/bash` 3.2 using the Phase 1 interpreter override. Read `src/cli/test/helpers/common.bash` for the override's actual variable name (design decisions give `MD2X_TEST_BASH` as an example) and the Makefile's `test-cli` recipe for how to invoke bats, rather than guessing. Build first (`make all`) so `bin/md2x` exists.
- Real-toolchain e2e cases must skip (not fail) where a tool cannot be installed. Do not make a missing optional package fail the job. If a package is unavailable on a platform, leave a short comment in the workflow naming the limitation.
- Pin action versions to major tags. Set least-privilege `permissions: contents: read`.
- Do not claim the workflow is green. It cannot run until the branch is pushed, which is a user action; state that in the task report.

## Validation

- `.github/workflows/ci.yml` exists and parses as YAML (`python3 -c 'import sys,yaml; yaml.safe_load(open(".github/workflows/ci.yml"))'`, or `bunx yaml-lint` / `actionlint` if available).
- The matrix lists both `ubuntu-latest` and `macos-latest`; the macOS `/bin/bash` 3.2 step is present and uses the override variable name that exists in `common.bash` (grep to confirm).
- Locally, run the exact bash-3.2 command the workflow uses (`/bin/bash` is 3.2.57 on this host) and confirm the suite passes.
- No file outside `.github/workflows/` is modified.
- `make qa` still passes.

## Metadata

architectural_impact: true

## Assumptions

- Phases 1 and 2 are merged: the harness interpreter override exists, `make qa` is green, and `bun.lock` is current.
- Use `@liquid-labs/md2x` repo conventions: lowercase `liquid-labs` in any URL.

## References

- [Design decisions, CI](../notes/design-decisions.md#ci)
- [Audit coverage](../notes/audit-coverage.md): rows R1, R6.
- [Design decisions, bash version support](../notes/design-decisions.md#bash-version-support)

## Status

- Outcome: succeeded (2026-10-05). Workflow written at `.github/workflows/ci.yml`; NOT proven green: it cannot run until the branch is pushed (a user action).
- Jobs: `qa` matrix (ubuntu-latest, macos-latest) running `make qa`, plus a macOS step running the bats suite under `/bin/bash` 3.2 via `MD2X_TEST_BASH=/bin/bash make test-cli`; and `legacy-pandoc` (ubuntu) running `make test-cli` against pandoc 2.0.6 installed from the jgm/pandoc release `.deb`, to validate the `MD2X_PANDOC_MIN_VERSION='2.0'` floor.
- Validation: actionlint and a YAML parse pass; the exact bash 3.2 command passes locally; `make qa` passes.
- Unproven until pushed: the pandoc 2.0.6 `.deb` URL/asset name, whether the suite actually passes on pandoc 2.0.6 (a failure there means the floor claim is wrong and should be raised, not hidden), and the macOS brew package names. The legacy job targets the oldest release believed to ship a Linux `.deb`; if it cannot be installed, the floor remains unvalidated and must be treated as a documented follow-up rather than lowered silently.

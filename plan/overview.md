# Plan Overview: PDF Engine WeasyPrint

## Purpose and scope

Make md2x's PDF output work again — and keep working — by pinning Pandoc to a WeasyPrint binary that md2x installs and manages itself in a per-user virtual environment, and by correcting the project documentation that currently claims md2x never manages its own dependencies.

**Background (already root-caused; not re-investigated by this plan).** `src/cli/lib/generate-page.sh` invokes `pandoc --to html5 -o <file>.pdf` with no `--pdf-engine` flag, so PDF rendering has always relied on whatever Pandoc's *default* HTML-to-PDF engine happened to be. Pandoc 3.4 (Nov 2024) changed that default from `wkhtmltopdf` to `weasyprint` (upstream `jgm/pandoc#10142`). Neither engine has ever been a documented md2x prerequisite, so on Pandoc >= 3.4 every PDF conversion fails with `'weasyprint' not found` — reproduced locally on Pandoc 3.10.1. This is the condition recorded as followup `BfN6`. A `pagedjs-cli` alternative was spiked and rejected before this plan (fragile Puppeteer/Chromium bootstrap); no trace of that spike exists in the repository.

### What must change

1. **`src/cli/lib/ensure-weasyprint.sh`** (new) — a bootstrap module, rolled into the CLI via `src/cli/lib/index.sh`. On each invocation it does a cheap `[[ -x "${HOME}/.md2x/venv/bin/weasyprint" ]]` test; when that fails it creates `~/.md2x/venv` with `python3 -m venv`, bootstraps pip with the venv's `python3 -m ensurepip`, and `pip install weasyprint`, printing a clearly-labeled one-time "installing weasyprint" notice **to stderr** so first-run latency is not a silent stall.
2. **`src/cli/md2x.sh`** — add `python3` to the existing binary preflight loop (same fail-fast, exit `2`, name-the-binary pattern as `gs`/`pandoc`/`pdftk`), and call the bootstrap after option processing, gated on `OUTPUT_FORMAT == 'pdf'`.
3. **`src/cli/lib/generate-page.sh`** — pass `--pdf-engine="${HOME}/.md2x/venv/bin/weasyprint"` (absolute path) on the Pandoc invocation for PDF output only.
4. **Documentation** — `README.md`, `AGENTS.md`, and `docs/project-structure.md` for the new `python3` prerequisite and the explicitly *non*-prerequisite status of WeasyPrint; `docs/architecture.md` and `docs/md2x-spec.md` for the genuine shift in product principle described below.

### What must not change

- No LaTeX PDF engine (`pdflatex`/`xelatex`/...) is reintroduced; the HTML5 intermediate stays.
- No `wkhtmltopdf` or `pagedjs-cli` code path is added — neither ever existed in this repository.
- No `pip` binary check is added to the preflight (`ensurepip` covers it), and no `weasyprint`-on-`PATH` check is added — WeasyPrint is deliberately not expected on `PATH` at all; the bootstrap script's own error handling covers its absence.
- `src/node/*` is untouched. The Node wrapper shells out to the built CLI and needs no change. Its stdout contract, however, constrains the CLI: it parses generated file paths out of the CLI's stdout, so no bootstrap output may go there.
- `--quiet` keeps its documented meaning (suppresses only the `Created <file>` message).

### Success criteria

- `md2x <file>.md` produces a valid, page-stamped PDF on a machine with Pandoc >= 3.4 and no system WeasyPrint, from a cold `~/.md2x` state, without any manual WeasyPrint install.
- A warm re-run reuses the existing venv with no reinstall and no extra output.
- HTML and DOCX conversions are unaffected, and never trigger a WeasyPrint install.
- `--list-files` stdout carries only file paths and `--to-stdout` carries only document bytes, including on the cold-start run.
- A missing `python3` fails fast at exit `2` naming `python3`; a failed bootstrap fails with exit `2`, names the failing step, and gives a manual remediation command.
- `docs/md2x-spec.md` and `docs/architecture.md` no longer assert that md2x manages none of its dependencies or that it holds no state between invocations — both statements become false when this lands.

### The documented-principle shift

This is a real, deliberate change of product principle, not an incidental edit. `docs/md2x-spec.md` currently states (Constraints, and again under Non-goals) that "md2x does not install these dependencies itself" and that installation "is the operator's responsibility"; `docs/architecture.md`'s *Minimal, mature external dependency set* decision makes the same claim, and its *Tech stack* section asserts md2x "holds no state between invocations" — which `~/.md2x/venv`, a persistent per-user cache, contradicts. The new contract must be stated accurately and asymmetrically: `pandoc`, `gs`, `pdftk`, and now `python3` are operator-installed and preflight-verified; WeasyPrint alone is md2x-managed, because it is a Pandoc *implementation detail* the user never invokes directly and would otherwise have to install to satisfy a requirement md2x never told them about. Leaving these docs silently contradicting the implementation is an explicit failure of this plan.

Design decisions behind the bootstrap — the failure-mode exit code, why the install notice is not `--quiet`-suppressible, why there is no venv staleness check, and the interactive-test-suite constraint on validation — are recorded in [the WeasyPrint bootstrap design notes](./notes/weasyprint-bootstrap-design.md). Task documents reference that note rather than restating it.

## Current status

Plan created; no implementation work has started. Phase 01 begins first, from a clean `plan/pdf-engine-weasyprint` branch state.

Pre-conditions for the first task:

- Task worktrees start without `node_modules`; `npm install` must run before `npm run build` / `make all`, since the build shells out to `npm exec bash-rollup`.
- `~/.md2x` does not currently exist on this machine, so a genuine cold-start path is available for the first PDF conversion; validation steps re-create that state with `rm -rf ~/.md2x` rather than assuming it.
- `make test` / `npm test` cannot be used for validation: `src/cli/test/test.sh` opens each output file with `open -Fn` and then blocks on `read` waiting for a keypress. All validation is via direct `./bin/md2x` invocations.
- Followup `BfN6` records the originally-observed symptom this plan resolves. Whether it is cleared is the manager's call at apply-task-report time, not this plan's.

## Overview

Two phases, run in order. The implementation lands first so that the documentation describes what actually shipped rather than what was intended.

### Phase 01 — WeasyPrint PDF Engine

Delivers the working PDF pipeline and the contributor/consumer-facing documentation of its new prerequisites. Both tasks run **sequentially**, not in parallel: task 002 documents the behavior task 001 lands, and writing it first risks documenting a design that shifted during implementation.

- **001 — Bootstrap WeasyPrint And Pin PDF Engine.** Adds `src/cli/lib/ensure-weasyprint.sh`, registers it in `src/cli/lib/index.sh`, adds `python3` to the preflight loop and the gated bootstrap call in `src/cli/md2x.sh`, and pins `--pdf-engine` in `src/cli/lib/generate-page.sh`. Validated end-to-end against both a cold (`rm -rf ~/.md2x`) and a warm `~/.md2x` state, plus HTML/DOCX regression and stdout-purity checks. Carries `architectural_impact: true`.
- **002 — Update Consumer And Contributor Docs.** `README.md` (prerequisites, the WeasyPrint-is-not-a-prerequisite note, the `rm -rf ~/.md2x/venv` reinstall escape hatch), `AGENTS.md` (build/test prerequisites, code organization), and `docs/project-structure.md` (the new `src/cli/lib/` module). Deliberately excludes `docs/architecture.md` and `docs/md2x-spec.md`, which Phase 02 owns.

### Phase 02 — Documentation Updates

Registered by the analyze-change-request architectural-implications check: this change introduces a new component, adds persistent cross-invocation state, and changes spec-defined preflight behavior.

- **001 — Update Architecture Docs.** Brings `docs/architecture.md` (system diagram, component list, tech stack, key decisions) and `docs/md2x-spec.md` (preflight general feature, constraints, non-goals, Node library requirements) into line with what Phase 01 landed, including the honest trade-off rationale for why WeasyPrint is self-managed while `pandoc`/`gs`/`pdftk`/`python3` are not.

# Update Consumer And Contributor Docs

## Purpose and scope

Update the consumer- and contributor-facing documentation to match what task 001 landed: `python3` is a new required binary on `PATH`, and WeasyPrint — now genuinely required for PDF output — is explicitly **not** a manual prerequisite, because md2x installs it into an isolated `~/.md2x/venv` on the first PDF conversion.

Files this task changes:

| File | Change |
| --- | --- |
| `README.md` | Installation/prerequisites; the WeasyPrint note and reinstall escape hatch |
| `AGENTS.md` | Build/test prerequisites; code-organization listing of `src/cli/lib/` |
| `docs/project-structure.md` | `src/cli/lib/` module description |

**Explicitly out of scope:** `docs/architecture.md` and `docs/md2x-spec.md`. Phase 02's `update-architecture-docs` task owns both, including the correction of their now-false claims that md2x manages none of its dependencies and holds no state between invocations. Do not edit either file here, and do not edit any file under `src/`.

No standard skill covers this; it is a direct documentation edit against the shipped behavior of task 001.

## Requirements

Read the merged task 001 changes (`src/cli/lib/ensure-weasyprint.sh`, `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`) before writing, and document what actually shipped — paths, message wording, and behavior — rather than what this document anticipates.

### `README.md`

- In **Installation**, add `python3` to the list of external binaries required on `PATH` (currently `pandoc`, `gs`, `pdftk`), with a link to <https://www.python.org/>. Keep the existing "md2x checks for these at startup and exits (code `2`) naming the first missing binary" sentence accurate — it now covers four binaries.
- Add a short note, adjacent to that list, stating that [WeasyPrint](https://weasyprint.org/) — the PDF rendering engine Pandoc uses — is **not** a manual prerequisite: md2x installs it automatically into an isolated per-user virtual environment at `~/.md2x/venv` the first time a PDF conversion runs, and prints a one-time notice while doing so. Mention that the first PDF conversion therefore takes noticeably longer and needs network access, and that `rm -rf ~/.md2x/venv` forces a clean reinstall on the next PDF conversion. Note that `python3` is what makes this possible — that is why it is on the required list.
- Keep the existing tone and length; this is a prerequisites note, not an essay. Do not restructure the Installation section.
- Check whether any other README statement is now inaccurate — in particular the Features bullet "Converts Markdown to PDF, HTML, or DOCX via Pandoc, rendering PDF through an HTML5 intermediate so no `pdflatex` install is required", which remains true but may read better naming the engine. Adjust only what is genuinely inaccurate or actively misleading; do not rewrite correct prose.

### `AGENTS.md`

- Update the build/test prerequisites sentence ("Building and running the test suite requires `pandoc`, `gs` (Ghostscript), and `pdftk` on `PATH`, since the tests exercise real conversions") to include `python3`, and to note that WeasyPrint is bootstrapped automatically into `~/.md2x/venv` on the first PDF conversion rather than being a manual install. A contributor whose first `make test` stalls for a minute should find the explanation here.
- Add `ensure-weasyprint.sh` to the `src/cli/lib/` file list under **Code organization**, with a brief parenthetical describing it (the `~/.md2x/venv` WeasyPrint bootstrap).
- Consider whether the **Conventions** section warrants a line about the `~/.md2x` cache affecting local testing — the existing `--infer-version` convention bullet is the model for this kind of "keep this in mind when testing locally" note. Add one only if it earns its place.

### `docs/project-structure.md`

- Update the `## src/` prose paragraph, which enumerates `src/cli/lib/` contents by name (`generate-page.sh`, `github.css`, `parameters.sh`, `index.sh`), to include `ensure-weasyprint.sh`.
- Check the directory-tree code block's `lib/` comment line ("CLI library modules (page generation, GitHub CSS, parameters)") and extend it if it still reads as an exhaustive list.
- This file documents the repository layout only. `~/.md2x` is a per-user runtime cache outside the repository, so it does not belong in the directory tree; mention it only if a one-line note genuinely aids orientation.

### Cross-cutting

- Do not contradict `docs/architecture.md` or `docs/md2x-spec.md` in a way Phase 02 then has to reconcile — but do not soften the new facts to match those (temporarily stale) documents either. State the accurate contract: `pandoc`, `gs`, `pdftk`, and `python3` are operator-installed and preflight-verified; WeasyPrint alone is md2x-managed.
- Do not document `--quiet` as suppressing the install notice; it does not (the notice goes to stderr).
- Do not claim md2x checks for `weasyprint` on `PATH` or that `pip` is a prerequisite. Neither is true.

## Validation

1. **Accuracy against the implementation.** Every path, exit code, and behavior claim in the new prose is checkable against the merged source: `grep -n 'md2x/venv' src/cli/lib/*.sh` confirms the `~/.md2x/venv` path, and `grep -n 'python3' src/cli/md2x.sh` confirms the preflight entry. The documented first-run behavior matches what a real cold-start run does — if `~/.md2x` is currently warm, `rm -rf ~/.md2x` and run one PDF conversion to observe the actual notice wording before finalizing the prose.
2. **Prerequisite lists agree.** `grep -rn 'pdftk' README.md AGENTS.md` shows every prerequisite list now naming four binaries including `python3`, with no list left at three.
3. **No stray WeasyPrint-as-prerequisite claim.** `grep -rni 'weasyprint' README.md AGENTS.md docs/project-structure.md` — every hit reads as "installed automatically / not a manual prerequisite", none as "install WeasyPrint" or "requires WeasyPrint on PATH".
4. **Link integrity.** Any newly added link (python.org, weasyprint.org) is well-formed; existing relative links in the edited sections still resolve.
5. **Scope check.** `git diff --name-only` lists exactly `README.md`, `AGENTS.md`, and `docs/project-structure.md`. Confirm `docs/architecture.md`, `docs/md2x-spec.md`, and everything under `src/` are untouched.
6. **Markdown conventions.** The edits match the surrounding document's existing style — table formatting, list markers, heading levels, and sentence tone — and no document's table of contents is invalidated by a new or renamed heading.

## Assumptions

- Task 001 has landed and is merged into this task's starting state; its source changes are readable and its runtime behavior observable.
- The observed first-run notice wording comes from the shipped `src/cli/lib/ensure-weasyprint.sh`, not from this plan's suggested phrasing — quote the real thing if quoting at all.
- `docs/architecture.md` and `docs/md2x-spec.md` still contain statements contradicting the new behavior at the time this task runs. That is expected and is Phase 02's work; it is not a defect to fix here.

## References

- [Plan overview](../overview.md) — the full change and the documented-principle shift, including which claims in which documents become false.
- [WeasyPrint bootstrap design notes](../notes/weasyprint-bootstrap-design.md) — why the notice is not `--quiet`-suppressible, and why there is no venv staleness check (relevant to the `rm -rf ~/.md2x/venv` escape hatch this task documents).
- [Task 001](./001-bootstrap-weasyprint-and-pin-engine.md) — the implementation this documentation describes.
- `README.md` Installation section (lines ~5-21) and Features list (lines ~56-63).
- `AGENTS.md` Build and test section (line ~15) and Code organization list (lines ~43-49).
- `docs/project-structure.md` `## src/` section and the directory-tree code block.

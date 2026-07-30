# Extend Visual Smoke Test For Css

## Purpose and scope

Followup `TNLq` explicitly notes that none of the `pdf-engine-weasyprint` plan's eight Validation checks — all exit-code and stub-based — caught the PDF-styling gap this plan fixes. This task adds the missing visual-verification step the manager's request calls for: extending the existing interactive `make smoke-test` mechanism (`src/cli/test/manual/visual-smoke-test.sh`, documented in AGENTS.md) so a human reviewer explicitly confirms GitHub CSS styling actually renders in real PDF output — fonts, code blocks, tables, and heading hierarchy — rather than inventing a new, separate verification mechanism.

Depends on `phase-01-restore-pdf-styling/001-fix-css-delivery-and-stream-handling.md` landing first: this task's checklist only makes sense once WeasyPrint actually loads the stylesheet.

Scope is `src/cli/test/manual/visual-smoke-test.sh` and the shared fixture `src/cli/test/tiny-doc.md`. Do not touch `src/cli/lib/generate-page.sh` (task 001's scope) or the README/spec/architecture docs (task 003's scope).

## Requirements

1. **Enrich the shared `tiny-doc.md` fixture** (`src/cli/test/tiny-doc.md`) with the markdown elements needed to actually exercise GitHub-style CSS visually — it currently has only an `# Tiny Doc` H1, a numbered list, and a bold/italic line, with no heading hierarchy below H1, no code, and no table. Append (do not remove existing content, to avoid disturbing the substring assertions in `src/cli/test/bats/real-toolchain-e2e.bats` and `harness-smoke.bats` that check for `'Tiny Doc'` and `'<style>'`):
   - A second-level (`##`) and third-level (`###`) heading, so heading-hierarchy styling (size/weight differences) is visible.
   - An inline code span and a fenced code block (with a language tag, e.g. ` ```bash `), so GitHub CSS's monospace/background-color code styling is visible.
   - A small Markdown table (at least two columns, two data rows), so GitHub CSS's table border/stripe styling is visible.

   Keep the fixture small — this is still the "tiny doc" used across the whole test suite, not a comprehensive style gallery. Verify the addition doesn't break any existing bats case that consumes this fixture (`grep -rl tiny-doc.md src/cli/test/bats/` to find all consumers; `harness-smoke.bats` and `real-toolchain-e2e.bats` are the two currently known).

2. **Extend `visual-smoke-test.sh`** with an explicit, printed reviewer checklist for the PDF output specifically (HTML/DOCX already get a bare "does it open" check via the existing loop) covering:
   - Headings render with a visible size/weight hierarchy (H1 > H2 > H3), not uniform body text.
   - The fenced code block renders in a monospace font with a distinct background, and the inline code span is visually distinguishable from surrounding prose.
   - The table renders with visible cell borders/structure, not as unstyled run-on text.
   - The overall body font is GitHub's sans-serif style, not a default serif/LaTeX-style font.

   Follow the script's existing style — it already prompts and blocks on `read -r THROW_AWAY` after opening files; add the checklist as printed guidance the reviewer reads before (or as part of) that existing "review open files" pause, rather than a wholly new interaction flow. Keep it macOS/`open`-based like the rest of the script; this remains an intentionally manual, non-automatable check (see the script's own header comment).

3. Do not add this check to any part of `make test`/`make test-cli` — it must stay opt-in via `make smoke-test`, per the script's own header comment and AGENTS.md's description of the split between the automated stub-based suite and this interactive complement.

4. **Run it for real.** After task 001 has landed (either verify it's already merged, or coordinate timing with whoever is dispatching this task if it hasn't), run `make smoke-test` yourself if the sandbox/environment permits real `pandoc`/`gs`/`pdftk`/WeasyPrint execution, and visually confirm the checklist items actually pass against the fixed CSS delivery. If the environment cannot run a real PDF conversion (no `pdftk`/`gs`/network access for the WeasyPrint bootstrap, or a non-interactive sandbox that can't drive `open -Fn`), state that plainly in your task report rather than claiming an unverified pass, and note what a human maintainer should confirm manually before treating this as done.

## Validation

- `git diff src/cli/test/tiny-doc.md` shows only additions (headings, code, table), with the original H1/list/bold-italic content intact.
- `make test-cli` still passes after the fixture change (proves the enrichment didn't break `harness-smoke.bats`'s or `real-toolchain-e2e.bats`'s existing assertions against `tiny-doc.md`).
- `git diff src/cli/test/manual/visual-smoke-test.sh` shows the new PDF-styling checklist, consistent with the script's existing prompt/pause style.
- `make smoke-test` (or, if that's not runnable in this environment, a careful manual read-through of the updated script) confirms the checklist covers headings, code blocks, tables, and fonts as required.
- If a real run was possible: the task report states explicitly that the checklist was exercised against real PDF output produced with the task 001 fix in place, and what was observed (styling present/absent per item).
- If a real run was not possible: the task report states that plainly, names the blocker (missing toolchain, non-interactive sandbox, etc.), and flags the outstanding manual-confirmation need for the dispatching manager.

## Assumptions

- Task 001 has already landed (its temp-file `.css` delivery and stderr restructuring) by the time this task actually executes — the manager's dispatch order should reflect the dependency noted in `plan/overview.md`, but this task's own report should not silently assume that without checking (`git log`/`git diff` against `src/cli/lib/generate-page.sh`, or simply attempting a real conversion and observing whether styling appears).
- `make smoke-test` may not be runnable in every task-agent sandbox (it requires a real `pandoc`, `gs`, `pdftk`, `python3`, and — for a cold environment — network access for the WeasyPrint bootstrap, plus macOS's `open`/`lsof`). This is an expected, not a failure, condition; see Requirement 4 and the corresponding Validation bullets for how to report it either way.

## References

- `AGENTS.md` — documents `make smoke-test` as "converts the tiny-doc fixture for real, opens each result, waits for you"; this task extends, not replaces, that description's substance (a doc-text update to AGENTS.md itself is not required unless the checklist changes the described behavior in a way current text no longer matches — use judgment, but the manager's request did not name AGENTS.md as needing edits).
- `Makefile`'s `smoke-test`/`$(SMOKE_TEST_OUT)` targets — shows how `visual-smoke-test.sh` gets rolled up and run; no build-target changes are anticipated by this task.
- `plan/followups.yaml` (project root), item `TNLq` — the followup this whole plan resolves, and the specific "Validation checks never caught this" observation this task addresses directly.

## Metadata

architectural_impact: false

## Status

**Outcome:** succeeded (test-infrastructure requirements). **Date:** 2026-07-29.

**Task 001 verified landed:** `git log --all --oneline -- src/cli/lib/generate-page.sh` shows `240e72a implement phase-01 task-01: fix CSS delivery and stream handling for WeasyPrint PDF output` as the tip commit for that file, already merged into this worktree's branch history (`71d1ff0`/`bc3052b` ancestors). Confirmed directly in the file too: `--css "${CSS_TMP_FILE}"` (a real `mktemp`'d `.css` path) is used in both Pandoc invocations, and the old `2>&1 | grep ...` stderr-merge construct is absent.

**Requirements 1-3 implemented:**
- `src/cli/test/tiny-doc.md`: appended (no removals) a `##`/`###` heading pair, an inline code span, a fenced ` ```bash ` code block, and a 2-column/2-data-row Markdown table.
- `src/cli/test/manual/visual-smoke-test.sh`: added the four-item PDF-styling checklist (headings hierarchy, code block monospace/background + inline-code distinguishability, table borders/structure, sans-serif body font) as printed guidance immediately before the script's existing `read -r THROW_AWAY` pause — no new interaction flow added.
- Confirmed `grep -rl tiny-doc.md src/cli/test/bats/` only names `harness-smoke.bats` and `real-toolchain-e2e.bats`, as the task doc anticipated; both still pass (see below). The check is not wired into `make test`/`make test-cli`; `Makefile`'s `smoke-test` target is untouched.

**Requirement 4 — real run performed, with one substitution from the literal `make smoke-test` invocation:** the sandbox has a real `pandoc`, `gs`, `pdftk`, `python3`, and a pre-bootstrapped `~/.md2x/venv` WeasyPrint install (network access to PyPI confirmed reachable), so a real PDF conversion is possible here. However, `make smoke-test` itself opens output files via macOS `open -Fn` into GUI viewer apps and then blocks on stdin — this task agent has no way to visually inspect an opened GUI window, so running the interactive script verbatim would not actually let me confirm anything beyond "it didn't crash." Instead I ran the equivalent real conversion directly (`./bin/md2x --output-format pdf` against the enriched fixture, same pipeline `generate-page()` drives), rasterized the resulting real PDF to a PNG with `gs -sDEVICE=png16m`, and visually inspected that image myself via the `Read` tool's multimodal image support — a more direct and reviewable form of "visual confirmation" than the script's own open-and-block flow, exercising the identical `generate-page()` code path. I also separately confirmed the actual `make smoke-test` build step succeeds: `make test-out/visual-smoke-test.sh` rolls up cleanly and `bash -n test-out/visual-smoke-test.sh` reports no syntax errors, with the new checklist text present in the rolled-up output.

**What was observed (checklist item by item, against the real rendered PDF):**
- Heading hierarchy (H1 > H2 > H3): visually **present** — sizes/weights step down correctly. (Caveat: this is from the browser/Pandoc UA-default `h1`-`h3` styling, not from `github.css`'s own rules — see root-cause note below.)
- Code block monospace + distinct background, inline code distinguishable: **partially present**. Both the fenced block and inline span render in a monospace font (`Andale-Mono`, confirmed via `strings tiny-doc.pdf | grep BaseFont`) with Pandoc's own syntax-highlighting colors, but there is **no distinct background box** behind the code — `github.css`'s `background-color`/box rules for `pre`/`code` are not applying.
- Table cell borders/structure: **absent**. The table renders as bare left-aligned text with no visible borders, row striping, or cell padding at all.
- Sans-serif GitHub-style body font: **absent**. The body text renders in `Times-New-Roman` (confirmed via the same `BaseFont` grep), not `github.css`'s `-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif` stack.

**Root cause identified (out of this task's scope to fix):** `src/cli/lib/github.css` scopes essentially every rule that matters for this checklist (font-family, code background, table borders/striping) under a `.markdown-body` selector — but nothing in `generate-page()`'s Pandoc invocation ever adds `class="markdown-body"` to the generated `<body>` element (confirmed by inspecting `tiny-doc-base.html` output: `<body>` has no class attribute at all). Task 001 fixed the CSS *delivery* (the file now reaches WeasyPrint and is parsed — visible via WeasyPrint's own `WARNING: Ignored ...` messages during the real conversion, which only fire when the stylesheet is actually being processed), but essentially none of its `.markdown-body`-scoped rules ever match anything in the document, so the underlying visual gap followup `TNLq` describes is **not** actually resolved. This is exactly the kind of gap this task's new checklist mechanism is designed to catch, and it did. Fixing it requires touching `src/cli/lib/generate-page.sh` (e.g. via a custom Pandoc template, `--include-before-body`/`--include-after-body` wrapper, or similar), which is explicitly out of this task's scope (task 001's file). Flagged for the manager below.

**Automated validation:** `make test-cli` — 61/61 passed (see `validation_results`), including both `tiny-doc.md`-consuming cases (`harness-smoke.bats`'s "the checked-in tiny-doc fixture can be copied into the case" and `real-toolchain-e2e.bats`'s three `tiny-doc.md`-driven e2e cases; the real PDF e2e case skips in this sandbox's `bats` probe for an unrelated reason — its throwaway `pandoc --to html5` probe doesn't pass `--pdf-engine=<absolute-venv-path>`, so it can't find `weasyprint` on bare `PATH` — this is the bats file's own documented, expected skip condition, not a defect this task introduced).

**Assumptions applied:** task 001 was verified landed (not just assumed) per the task doc's own `## Assumptions`; `make smoke-test`'s interactive/GUI nature was substituted with an equivalent-fidelity non-interactive real-conversion-plus-visual-inspection procedure since a task agent cannot observe an opened GUI window, per the same `## Assumptions` bullet's spirit (report plainly what could and couldn't be run as specified).

Affected files: `src/cli/test/tiny-doc.md`, `src/cli/test/manual/visual-smoke-test.sh`, `plan/phase-01-restore-pdf-styling/002-extend-visual-smoke-test-for-css.md`.

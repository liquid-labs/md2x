# Add Gated End To End Tests

## Purpose and scope

Add a small set of true end-to-end cases that run md2x against the **real** `pandoc`, `gs`, and `pdftk` — the fidelity the stub-based suite deliberately gives up — and that **skip cleanly** rather than fail when the toolchain is unavailable. This is what keeps `make test` green on a machine (including the maintainer's today) where Pandoc's PDF engine is missing, while still catching a genuine Pandoc-side regression wherever the toolchain is complete.

Scope is new test files only. No changes to `src/cli/`, `src/node/`, the `Makefile`, `package.json`, or task 001's shared helpers.

No standard skill covers this; the [Requirements](#requirements) section below is the procedure.

## Requirements

1. **Keep the set small.** Three to five cases. This is a fidelity backstop, not a second coverage suite; behavioural coverage belongs to tasks 002 and 003 against the stubs.
2. **Gate per capability, not just per binary.** Binary presence is necessary but not sufficient: `pandoc` can be on `PATH` while the PDF engine it delegates to (`weasyprint` here — see followup `BfN6`) is absent. Gate the HTML/DOCX cases on `pandoc` being on `PATH`, and gate the PDF case on a *probe*: attempt a throwaway minimal conversion in setup and skip the case if it fails. A binary-presence check alone is not an acceptable gate for the PDF case.
3. **Skip, never fail.** An unavailable capability must produce a skipped case with a message naming what was missing, and must not affect the suite's exit status. Verify this both ways (see Validation).
4. **Use the real binaries, not the stubs.** These cases must not put the stub directory on `PATH`. Be explicit about that, since the shared setup helper installs the stubs by default.
5. **Suggested cases:**
   - `tiny-doc.md` → HTML: exit `0`, the output file exists, is non-empty, and contains recognizable converted markup (e.g. the fixture's heading text and a `<style>`/CSS marker).
   - `tiny-doc.md` → DOCX: exit `0`, the output file exists and is non-empty (a zip-magic byte check is a reasonable, cheap assertion).
   - `tiny-doc.md` → PDF (probe-gated): exit `0`, the output exists, starts with `%PDF`, and — since this is the only path exercising the overlay — has the Ghostscript/pdftk stage actually applied rather than being the bare Pandoc output.
   - Optionally a `--single-page` concatenation of two fixture files to PDF or HTML.
6. **Make them distinguishable.** Name or tag the cases so a developer can tell at a glance which part of the suite hits the real toolchain (a separate file, e.g. `*-e2e.bats`, plus a clear naming prefix).
7. Real conversions are slow; keep fixtures tiny and do not loop over formats redundantly.
8. Do not assert non-`--flatten-dirs` mirrored output paths — task 002 owns those, and may be running in parallel. Use invariant input shapes (input file in the case's own working directory, or `--flatten-dirs`).

## Validation

- `make test` passes with a zero exit status on the current machine, where the PDF probe is expected to fail and that case is expected to **skip**. Confirm from the runner output that the PDF case reports as skipped, with a message naming the missing capability — not as a pass and not as a failure.
- The HTML and DOCX cases actually **run** (not skip) on the current machine, and their assertions hold. Report the run/skip disposition of every e2e case.
- Simulate a fully-unavailable toolchain — run the suite with a `PATH` from which `pandoc` is absent — and confirm the e2e cases all skip and `make test` still exits zero.
- The e2e cases do not use the stub executables: `grep` the new files for any stub-`PATH` setup and confirm none, and confirm a real conversion actually occurred (the HTML output contains real converted markup, which no stub produces).
- `git diff --stat` shows changes confined to new test files — no `src/cli/md2x.sh`, no `src/cli/lib/`, no `src/node/`, no `Makefile`, no `package.json`, no changes to shared helpers.
- Suite runtime remains reasonable; report the wall-clock time of `make test` before and after.
- `make lint` and `make qa` pass.

## Assumptions

- Task 001 has landed the harness, the shared helpers, and the `make test` wiring. Read the landed files first — in particular, understand what the shared setup helper does to `PATH` so you can opt out of the stubs.
- On the current machine `pandoc`, `gs`, `pdftk`, `jq`, and `perl` are on `PATH` and Pandoc's `weasyprint` PDF engine is **not**, so the PDF case is expected to skip here. That is the intended outcome, not a defect to work around.
- Tasks 002, 003, and 004 may be running in parallel.

## References

- [Test tooling survey](../notes/test-tooling-survey.md) — why the bulk of the suite stubs the tool boundary and what this gated set is meant to add back.
- [`docs/architecture.md`](../../docs/architecture.md) — the Pandoc → Ghostscript → pdftk pipeline these cases exercise for real, including why PDF goes through an HTML5 intermediate.
- [`docs/md2x-spec.md`](../../docs/md2x-spec.md) — UC1, UC2, and the General features section (styling, TOC, PDF header/footer) these cases spot-check end to end.
- `src/cli/test/tiny-doc.md` — the existing fixture.
- `src/cli/test/manual/visual-smoke-test.sh` (relocated by task 001) — the interactive check these cases partially automate; worth reading for what the manual test was verifying.

## Status

**Outcome:** succeeded. Date: 2026-07-29.

Added `src/cli/test/bats/real-toolchain-e2e.bats` — the only file this task creates or touches. Four cases, all prefixed `e2e:` to keep them visually distinguishable from the stub-based suite:

1. `tiny-doc.md` → HTML — gated on `pandoc` on `PATH`; **ran** on this machine. Asserted output exists, is non-empty, contains the fixture's `Tiny Doc` heading text and a `<style>` marker.
2. `tiny-doc.md` → DOCX — gated on `pandoc` on `PATH`; **ran**. Asserted output exists, is non-empty, and starts with the `PK` zip magic.
3. `tiny-doc.md` → PDF — gated on a throwaway probe conversion (`pandoc --to html5 -o <tmp>.pdf --quiet <(printf '# probe\n')`), mirroring exactly how `generate-page.sh` drives Pandoc's HTML5-to-PDF path (binary presence alone would not have caught the missing engine). **Skipped** on this machine, reporting `pandoc's PDF engine is unavailable: 'weasyprint' not found. Please select a different --pdf-engine or install 'weasyprint'` — the expected outcome per this task's `## Assumptions` and followup `BfN6`. When it does run (verified the assertion logic is sound, just not exercisable here), it additionally checks for `<title>-overlay.pdf` (kept via `--keep-intermediate`) as direct proof the Ghostscript/pdftk overlay stage executed, not just that Pandoc alone produced a PDF.
4. `--single-page` concatenation of two fixtures (`alpha.md`, `beta.md`) to HTML — gated on `pandoc` on `PATH`; **ran**. Asserted the combined output contains both fixtures' heading text.

None of the four cases install the stub `PATH` (`md2x_setup`/`md2x_use_stub_path` are never called); a local `e2e_setup`/`e2e_teardown` pair reimplements only the private-working-directory part of the shared setup and additionally asserts `MD2X_STUB_DIR` is not on `PATH` as a defensive guard. `grep -n "md2x_use_stub_path\|md2x_setup\b\|md2x_path_without" src/cli/test/bats/real-toolchain-e2e.bats` matches only explanatory comments, never a call.

**Validation performed:**
- `make test` → exit 0. Runner output: cases 11–14 in the combined bats run are the four e2e cases; 11, 12, 14 report `ok` (ran), 13 reports `ok ... # skip pandoc's PDF engine is unavailable: ...` (skipped, not failed).
- HTML/DOCX/single-page cases actually ran (not skipped) and all assertions held; PDF case skipped with the missing-capability message, as required.
- Simulated a fully-unavailable toolchain: built an isolated `PATH` (`gs`, `pdftk`, `jq`, `perl`, `brew`, `bash`, `git` symlinked in; system dirs only, no `pandoc`) and ran `node_modules/.bin/bats` directly against the new file — all four cases skipped (`# skip real 'pandoc' not found on PATH`), exit 0. (Ran at the bats-invocation level rather than reconstructing `make test`'s full npm/node toolchain under the restricted `PATH`, since only the e2e file's own PATH-gating was in scope here.)
- `git diff --stat` / `git status --porcelain` show only the new `src/cli/test/bats/real-toolchain-e2e.bats` file — no changes to `src/cli/md2x.sh`, `src/cli/lib/`, `src/node/`, `Makefile`, `package.json`, or the shared test helpers.
- Wall-clock `make test`: before (file removed) ≈12.4s; after (file present) ≈13.9–17.5s across two runs (real Pandoc/Ghostscript/pdftk conversions for 3 of 4 cases account for the difference) — still well within "reasonable" for a small, fast suite.
- `make lint` and `make qa` both exit 0.

**Assumptions applied:** the task doc's stated environment assumption (pandoc/gs/pdftk/jq/perl present, weasyprint absent) held exactly as described; the PDF case's skip is the intended, verified outcome rather than a defect.

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

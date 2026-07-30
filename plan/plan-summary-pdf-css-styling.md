# Plan Summary: pdf-css-styling

## What was planned and why

This plan set out to fix followup `TNLq`: PDF output shipped with **no** GitHub-markdown CSS styling at all. The root cause identified at planning time was that `generate-page()` in `src/cli/lib/generate-page.sh` delivered the bundled stylesheet to Pandoc via `--css <(echo "${CSS}")` — a process-substitution path (`/dev/fd/N`) with no `.css` extension. WeasyPrint (the pinned `--pdf-engine` since the `pdf-engine-weasyprint` plan) cannot MIME-sniff a stylesheet from that path and silently drops it, surfacing only an "Unsupported stylesheet type" warning on stderr — which the pre-existing code merged onto stdout via `pandoc ... 2>&1 | grep -vE ...` and then filtered away. That grep patched over the symptom (a stray warning line) without restoring actual styling. HTML and DOCX output were unaffected, since Pandoc's own `--css` handling doesn't MIME-sniff the way WeasyPrint does.

The plan was scoped as three tasks:

1. **Fix CSS delivery and stream handling** — replace the process-substitution `--css` delivery with a real `mktemp`-created `.css` temp file, and restructure stderr handling so Pandoc/WeasyPrint's non-fatal warning chatter no longer gets pattern-matched/grepped off the CLI's real stdout.
2. **Extend the visual smoke test** — add an explicit reviewer checklist to `make smoke-test` confirming GitHub CSS styling actually renders (fonts, code blocks, tables, headings) in real PDF output, since none of the `pdf-engine-weasyprint` plan's exit-code/stub-based validation checks had caught this gap.
3. **Update stale docs** — correct README.md's Features bullet, docs/architecture.md's "Bundled stylesheet" section, and review docs/md2x-spec.md's styling claims for continued accuracy.

The plan grew a fourth task mid-execution. Task 002 built its new visual-verification checklist and then actually ran it end-to-end against a real WeasyPrint-bootstrapped environment — and that run is what discovered task 001's fix, while itself correct, was **necessary but insufficient**. WeasyPrint now loaded `github.css` (confirmed via its own parse warnings), but the Pandoc-generated `<body>` never received `class="markdown-body"`, so essentially every rule that matters in `github.css` (font stack, code-block background, table borders) was scoped under a selector that never matched anything. The rendered PDF still showed a serif body font, a borderless table, and code with no background — exactly the class of gap the new checklist mechanism was built to catch, and it did. Rather than close the plan with the underlying visual bug still unresolved, the user decided to extend the plan with a fourth task (**Wrap generated body in markdown-body div**) to fix the real root cause in `generate-page.sh`.

## What shipped

- **Task 001 — Fix CSS Delivery And Stream Handling** (merge `bc3052b`). Replaced `generate-page()`'s process-substitution `--css` delivery with a real `.css`-suffixed temp file per call (so WeasyPrint can MIME-sniff the stylesheet), and removed the `2>&1 | grep ... || true` construct from both Pandoc invocations so stderr flows untouched to the CLI's real stderr — never onto the parsed `--to-stdout`/`--list-files` stdout channel, and never masking a genuine fatal exit under `errexit`. Added an explicit `1>/dev/null` on Pandoc's own stdout as defense-in-depth. Extended the pandoc test stub with `MD2X_TEST_STUB_STDERR`/`MD2X_TEST_STUB_EXIT_CODE` overrides and added bats coverage. Also discovered and fixed a real defect in its own task doc's guidance: on macOS (BSD) `mktemp`, a literal suffix after the X's is not randomized — worked around with a trailing-X-only `mktemp` + `mv`-to-add-suffix.

- **Task 002 — Extend Visual Smoke Test For CSS** (merge `6874f82`). Implemented all three infrastructure requirements (enriched fixture, PDF-styling checklist in the manual smoke-test script, kept opt-in-only), then actually ran the pipeline end-to-end against a real WeasyPrint-bootstrapped environment. That real run is what surfaced the missing-`markdown-body`-class gap described above — confirmed by rasterizing the real PDF to PNG and visually inspecting it, and by grepping embedded font names (Times-New-Roman for body text) and the intermediate HTML (`<body>` has no class attribute). Only the heading-size-hierarchy checklist item passed, and only incidentally via browser/Pandoc UA defaults, not via `github.css`. The underlying fix was explicitly out of this task's scope (belongs to `generate-page.sh`).

- **Task 003 — Update Stale PDF Styling Docs** (merge `d314405`). Corrected the two doc locations describing the pre-task-001 broken CSS delivery: README.md's Features bullet now states PDF gets consistent GitHub-style CSS unconditionally (restored to pre-regression wording, dropping the `TNLq` followup reference), and docs/architecture.md's "Bundled stylesheet" section now describes the actual landed mechanism (mktemp `.css` temp file passed to `--css`, cleaned up unless `--keep-intermediate`). docs/md2x-spec.md needed no edit: both `LUhO`-flagged passages already stated PDF gets the built-in CSS with no hedge, and were verified accurate post-task-001. All `TNLq` references were scrubbed from the three in-scope docs.

- **Task 004 — Wrap Generated Body In Markdown Body Div** (merge `c46d8b7`). Implemented `--include-before-body`/`--include-after-body` wrapping in `generate-page()` exactly as specified: new `MARKDOWN_BODY_OPEN`/`MARKDOWN_BODY_CLOSE` literals written to trailing-X-only `mktemp` temp files, referenced in both Pandoc invocations via the file's existing conditional-word-splitting idiom, gated out of docx, and cleaned up under the existing `KEEP_INTERMEDIATE` gate. Extended the pandoc test stub to parse/capture the two new flags and added full bats coverage (pdf/html wrap assertions, docx-exclusion regression guard, keep-intermediate temp-file pairs, a real-Pandoc e2e assertion). `make all && make test-cli` passed 66/66. Performed a full real PDF render, rasterized it, and visually confirmed all four styling checklist items now render correctly — followup `TNLq`/`yJ9C`'s visual bug is genuinely fixed, not just mechanically wired. Also ran a real (non-stub) docx conversion confirming zero `<div` leakage into `word/document.xml`.

## Key decisions

- **Task 001 — mktemp BSD-vs-GNU workaround.** A literal suffix placed directly after the `X` sequence in `mktemp` is only randomized correctly on GNU `mktemp`; on macOS's BSD `mktemp` the suffix is treated as a literal, non-randomized string, risking collisions. Worked around by using a trailing-X-only template with `mktemp` and then `mv`-ing to add the `.css` (and later `.html` snippet) suffix, portable across both implementations.

- **Task 001 — stop merging pdf-engine stderr onto stdout entirely.** Rather than continuing to pattern-match/grep around WeasyPrint's non-fatal warning chatter (which has no reliable machine-parseable boundary, per followup `TNLq`'s own investigation, and risked either leaking noise onto stdout or swallowing a genuinely fatal error), the fix stops merging stderr into the CLI's real stdout at all. This is a more structural fix than the incremental grep patches it replaces, per the note recorded in followup `rndR`.

- **Task 004 — `--include-before-body`/`--include-after-body` wrapping over a custom Pandoc template or `-V` variable.** Chose Pandoc's existing before/after-body injection flags (pointing at two small mktemp-generated snippet files containing the opening/closing `markdown-body` div markup) instead of introducing a custom Pandoc template or a `-V` template variable, minimizing new surface area and reusing the same temp-file delivery pattern task 001 established for the CSS file.

- **Task 004 — DOCX-corruption gotcha, gated around.** The `markdown-body` div wrapping is explicitly excluded from the docx output path — applying it there would leak raw `<div>` markup into `word/document.xml` and corrupt the DOCX file, since DOCX has no HTML-body concept for Pandoc to target. The task added a real (non-stub) docx conversion as a regression guard confirming zero `<div` leakage.

## Follow-up items

Items tagged `plan/phase:restore-pdf-styling` in `plan/followups.yaml`:

- **`qEQi` — mktemp BSD-suffix deviation is worth broader awareness.** Flags that the BSD-`mktemp`-does-not-randomize-a-literal-suffix pitfall (task 001's finding) could resurface if another task or doc repeats the same incorrect assumption.
- **`OUbU` — CSS temp file location is undiscoverable under `--keep-intermediate`.** Unlike `pandoc-log.log` and the PDF overlay file (written into the user's working/output directory), the CSS temp file lives in system `TMPDIR` and its path is never surfaced to the user, so `--keep-intermediate` effectively leaves it orphaned.
- **`djfw` — docs/architecture.md's cleanup description is incomplete.** The "Page generation / conversion pipeline" section says intermediate-artifact cleanup covers "the Pandoc log and, for PDF, the overlay file" but doesn't mention the CSS temp file (or, now, the two body-wrapper temp files from task 004).
- **`yJ9C` — the missing-`markdown-body`-class finding.** This is the followup that documented the exact gap task 004 was created to fix; it remains listed in `followups.yaml` as-authored (task 004's fix is not yet reflected as a resolution there) but is functionally closed by task 004's shipped work.
- **`9hZL` — CSS temp file leaks on Pandoc failure.** Under `errexit`/`pipefail`, a non-zero Pandoc/WeasyPrint exit aborts `generate-page()` before its unconditional cleanup line runs, leaving `CSS_TMP_FILE` behind in `TMPDIR` on every failed conversion.
- **`QBKX` — CSS temp file recreated per file in batch conversions.** `$CSS` is static across all `generate-page()` calls within one `md2x` invocation, but the temp file is currently recreated (mktemp + mv + printf) once per input file in a multi-file/batch conversion — an avoidable linear per-file cost.
- **`vjPJ` — CHANGELOG.md unreachable from README.** Pre-existing condition (not introduced by this plan) noted by the phase-review's documentation link-chain check.
- **`ZfSv` — shellcheck warning count drifted between tasks.** Task 001 recorded 15 baseline warnings; task 004's pre-change measurement found 17 already present (some intervening change added 2), and task 004 adds exactly 2 more, both the same accepted `SC2046` class already present on adjacent conditionals using the same idiom.
- **`qbZF` — doc follow-up remains open for the body-wrapper mechanism.** docs/architecture.md's "Bundled stylesheet"/"Page generation" prose does not yet describe the `--include-before-body`/`--include-after-body` mechanism task 004 introduced; explicitly out of task 004's scope.
- **`5gem` — unquoted word-split risk in the new markdown-body flags.** The `--include-before-body`/`--include-after-body` flag+value pairs are injected via unquoted command substitution relying on IFS word-splitting; a `TMPDIR` containing a space would silently misalign the resulting Pandoc arguments (low real-world likelihood, but differs from the `=`-fused `--pdf-engine=...` idiom used elsewhere).
- **`MwYH` — two more temp files added to the same errexit leak surface as `9hZL`.** Task 004's `BODY_OPEN_TMP_FILE`/`BODY_CLOSE_TMP_FILE` are created unconditionally per `generate-page()` call and share the same mid-invocation-failure cleanup gap as `9hZL`'s `CSS_TMP_FILE`; recommends addressing both together (e.g. a single trap-based cleanup) rather than separately.

## Final Task State

# TODO

## Purpose and scope

Tracking document for the active plan.

## Tasks

### Phase 01 — Restore Pdf Styling

- [x] [001-fix-css-delivery-and-stream-handling.md](./phase-01-restore-pdf-styling/001-fix-css-delivery-and-stream-handling.md) — tier `sonnet-high` · branch `phase-01-task-01-fix-css-delivery-and-stream-ha` · commit `240e72a` · merge `bc3052b`
- [x] [002-extend-visual-smoke-test-for-css.md](./phase-01-restore-pdf-styling/002-extend-visual-smoke-test-for-css.md) — tier `sonnet-med` · branch `phase-01-task-02-extend-visual-smoke-test-for-c` · commit `60edbc9` · merge `6874f82`
- [x] [003-update-stale-pdf-styling-docs.md](./phase-01-restore-pdf-styling/003-update-stale-pdf-styling-docs.md) — tier `sonnet-med` · branch `phase-01-task-03-update-stale-pdf-styling-docs` · commit `d485599` · merge `d314405`
- [x] [004-wrap-generated-body-in-markdown-body-div.md](./phase-01-restore-pdf-styling/004-wrap-generated-body-in-markdown-body-div.md) — tier `sonnet-high` · branch `phase-01-task-04-wrap-generated-body-in-markdow` · commit `d08a989` · merge `c46d8b7`

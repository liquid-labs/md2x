# Wrap Generated Body In Markdown Body Div

## Purpose and scope

Task 001 fixed followup `TNLq`'s CSS *delivery* mechanism (`--css <(echo "${CSS}")` → a real `.css` temp file WeasyPrint can MIME-sniff), and task 002's real-conversion visual smoke test confirmed WeasyPrint now genuinely loads and parses `src/cli/lib/github.css` — but also found the underlying visual bug `TNLq` describes is **still not fixed**: `github.css` (the vendored `github-markdown-css` package) scopes essentially every rule that matters — body font-family, code-block background, table borders/striping — under a `.markdown-body` class selector, and nothing in `generate-page()`'s Pandoc invocation ever puts `class="markdown-body"` on any element in the generated document. Confirmed directly against this worktree's `src/cli/lib/github.css`: every one of its 259 `markdown-body` occurrences is a bare `.markdown-body` class selector (e.g. `.markdown-body .octicon`, `}.markdown-body {`) — there is no `body.markdown-body` compound (element+class) selector anywhere in the file. That matters because it means the class does not need to land on the `<body>` element specifically; any ancestor element carrying `class="markdown-body"` around the rendered content satisfies every selector in the file.

This task closes that gap: it makes the class actually present in Pandoc's generated output for both PDF and HTML (the two CSS-consuming outputs `generate-page()` produces; DOCX does not use CSS and must not be touched by this mechanism — see Requirement 3 below), so `github.css`'s rules genuinely match and followup `TNLq` is fully resolved, not just partially addressed.

This is not a standard-skill task; there is no dedicated CSS/Pandoc-templating skill to invoke. Follow the [Requirements](#requirements) below.

Scope is `src/cli/lib/generate-page.sh` (the fix itself), `src/cli/test/stubs/pandoc` (stub support for the new flags), and `src/cli/test/bats/pandoc-args.bats` and `src/cli/test/bats/real-toolchain-e2e.bats` (test coverage). Do not touch `README.md`, `docs/architecture.md`, or `docs/md2x-spec.md` — prose describing this mechanism is a follow-up, out of this task's scope (flag it in your report if you think one is warranted; do not act on it here).

## Requirements

### 1. Mechanism: `--include-before-body`/`--include-after-body` wrapping a `<div class="markdown-body">`, not a custom template or `-V` variable

Three candidate mechanisms were evaluated against this environment's actual `pandoc` (3.10.1, Homebrew, confirmed via `pandoc --version` and `pandoc -D html5`) rather than assumed from memory:

- **`-V`/`--variable` metadata mechanism** — ruled out. `pandoc -D html5`'s actual default template hardcodes `<body>` with no `$body-class$` (or similarly named) variable anywhere in the template; there is no metadata-driven hook for adding an attribute to the `<body>` tag in the stock html5 writer.
- **Custom `--template`** — ruled out as disproportionate. A full copy of `pandoc -D html5`'s default template (currently ~70 lines, hardcoding everything from the `<head>` block's `$styles.html()$` through the TOC/`$body$`/`$include-after$` structure) would need to track upstream template drift across future Pandoc version upgrades — a maintenance burden and version-skew risk for a change that only needs one word (`class="markdown-body"`) added to one tag. Not warranted for a targeted defect fix.
- **`--include-before-body FILE` / `--include-after-body FILE`** — chosen. These do not add an attribute to the `<body>` tag itself (confirmed empirically: the default template's `<body>` line is untouched either way), but they inject literal content immediately after the opening `<body>` tag and immediately before the closing `</body>` tag respectively — verified by running `pandoc --standalone --from gfm --to html5 --include-before-body <(printf '<div class="markdown-body">') --include-after-body <(printf '</div>') ...` against this repo's fixture and inspecting the output: the resulting `<body>...</body>` content is `<div class="markdown-body">` immediately after `<body>`, the full rendered document (title header, `--toc` nav, and body content, in that order) inside it, and `</div>` immediately before `</body>`. Because `github.css`'s selectors are all bare `.markdown-body` (not `body.markdown-body`), this div satisfies them exactly as well as a class on `<body>` itself would. This was further verified end-to-end with the pinned `--pdf-engine` (`~/.md2x/venv/bin/weasyprint`) producing a real PDF, rasterized with `gs -sDEVICE=png16m` and visually inspected: the sans-serif GitHub font, code-block background, and table borders/stripes — all previously absent per task 002's `## Status` findings — now render correctly.

### 2. Implement in `generate-page.sh`

In `generate-page()`, alongside the existing `CSS`/`CSS_TMP_FILE` setup (`src/cli/lib/generate-page.sh`, currently around lines 14-35):

- Define two literal content strings for the wrapper, e.g.:
  ```bash
  MARKDOWN_BODY_OPEN='<div class="markdown-body">'
  MARKDOWN_BODY_CLOSE='</div>'
  ```
- Create two real temp files (mirroring the `CSS_TMP_FILE` pattern task 001 established) and write the content into them, e.g.:
  ```bash
  BODY_OPEN_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-body-open.XXXXXX")"
  BODY_CLOSE_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-body-close.XXXXXX")"
  printf '%s' "${MARKDOWN_BODY_OPEN}" > "${BODY_OPEN_TMP_FILE}"
  printf '%s' "${MARKDOWN_BODY_CLOSE}" > "${BODY_CLOSE_TMP_FILE}"
  ```
  Unlike `CSS_TMP_FILE`, these do **not** need a `.css`-style forced extension and do **not** need task 001's trailing-suffix `mv` workaround for BSD `mktemp` (that workaround was specifically because a literal suffix *after* the `X` run doesn't randomize on macOS's native `mktemp`; a plain trailing-`X`-only template like the one above randomizes correctly on both BSD and GNU `mktemp`, confirmed by task 001's own finding). `--include-before-body`/`--include-after-body` are consumed directly by Pandoc itself (never handed to the `--pdf-engine` subprocess as a path the way `--css` is), so there is no MIME-sniffing/extension sensitivity to work around — verified empirically: both a bare-name temp file and a `/dev/fd/N` process-substitution path work identically for these two flags, unlike `--css`. Real temp files (not process substitution) are still specified here for consistency with the file's established `CSS_TMP_FILE` idiom and because Requirement 3 needs the flags conditionally *absent* from the docx invocation, which is simplest to express as a conditionally-included plain path string using the same idiom already used for `--pdf-engine=${WEASYPRINT_BIN}` (see Requirement 3).
- Add cleanup for both new temp files immediately alongside the existing `CSS_TMP_FILE` cleanup line (`[[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${CSS_TMP_FILE}"`, currently line 73), using the identical `KEEP_INTERMEDIATE` gate for consistency:
  ```bash
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${BODY_OPEN_TMP_FILE}"
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${BODY_CLOSE_TMP_FILE}"
  ```

### 3. Gate the new flags out of DOCX output — critical correctness requirement

**Empirically confirmed this task doc's mechanism corrupts DOCX output if added unconditionally.** Running `pandoc --standalone --from gfm --to docx --include-before-body <(printf '<div class="markdown-body">') --include-after-body <(printf '</div>') ...` does not error, but inspecting the resulting `.docx`'s `word/document.xml` shows the literal, invalid `<div class="markdown-body">` text inserted as raw content directly inside `<w:body>` — an element the OOXML schema does not permit there. This must never happen.

Add the two new flags to **both** Pandoc invocations in `generate-page()` (the `[[ -z "${INPUT}" ]]` file-input branch, currently around lines 38-50, and the stdin/single-page branch, currently around lines 58-70) using the same conditional-word-splitting idiom the file already uses for `--pdf-engine=${WEASYPRINT_BIN}` (`$( [[ "${OUTPUT_FORMAT}" != 'pdf' ]] || echo "--pdf-engine=${WEASYPRINT_BIN}" )`) and for `--toc` (`$( [[ "${OUTPUT_FORMAT}" == 'docx' ]] || [[ -n "${NO_TOC}" ]] || echo '--toc' )`):

```bash
$( [[ "${OUTPUT_FORMAT}" == 'docx' ]] || echo "--include-before-body ${BODY_OPEN_TMP_FILE} --include-after-body ${BODY_CLOSE_TMP_FILE}" )
```

Both temp files may still be created and written unconditionally (cheap, and keeps the two Pandoc-invocation branches structurally uniform) — only their *use* in the Pandoc command line is conditional on `OUTPUT_FORMAT`. Confirm the final invocation never emits `--include-before-body`/`--include-after-body` when `OUTPUT_FORMAT` is `docx`.

### 4. Test-stub support

`src/cli/test/stubs/pandoc` currently parses `-o`/`--log`/`--metadata-file`/`--css`/`--to` and drains+optionally-captures the process-substitution content behind `--metadata-file`/`--css`/the input document (see the stub's own header comment and its `pandoc-<n>-<kind>` capture-file convention under `MD2X_TEST_STUB_CAPTURE_DIR`). Extend it, following that exact convention:

- Parse `--include-before-body` and `--include-after-body` in the stub's argument-parsing loop, capturing each flag's file-path argument (e.g. into `INCLUDE_BEFORE_FILE`/`INCLUDE_AFTER_FILE`).
- Drain (and, when `MD2X_TEST_STUB_CAPTURE_DIR` is set, capture) their content the same way `CSS_CONTENT`/`CSS_FILE` already are, writing to `${MD2X_TEST_STUB_CAPTURE_DIR}/pandoc-<n>-body-open` and `pandoc-<n>-body-close` respectively, so `md2x_pandoc_capture body-open` / `md2x_pandoc_capture body-close` (the existing generic helper in `src/cli/test/helpers/stub-log.bash`) work unchanged for the new kinds.
- Update the stub's header comment to document the two new captured kinds, following the existing documentation style for `metadata`/`css`/`input`.

### 5. Automated coverage

Add or extend `bats` cases (in `src/cli/test/bats/pandoc-args.bats`, alongside the existing `--css`/`--keep-intermediate` cases, unless a case reads more naturally added to `src/cli/test/bats/real-toolchain-e2e.bats` per the split below) asserting:

- For `--output-format pdf` and `--output-format html`: the last `pandoc` invocation includes `--include-before-body` and `--include-after-body` (`assert_last_call_has_arg`), and the captured content behind each (`md2x_pandoc_capture body-open` / `body-close`) is exactly `<div class="markdown-body">` and `</div>` respectively.
- For `--output-format docx`: the last `pandoc` invocation includes **neither** `--include-before-body` nor `--include-after-body` (`refute_last_call_has_arg` for both) — this is the regression guard for the DOCX-corruption risk found in Requirement 3; treat it as load-bearing, not a nice-to-have.
- `--keep-intermediate` retains both new temp files after conversion, and without it both are removed — mirror the existing `--keep-intermediate retains the css temp file handed to pandoc after conversion` / `without --keep-intermediate, the css temp file...is removed` cases exactly, using `md2x_stub_last_call_args pandoc | grep 'md2x-body-open\.'` / `'md2x-body-close\.'` to locate each path (the `md2x-body-open.XXXXXX` / `md2x-body-close.XXXXXX` naming from Requirement 2 makes this grep unambiguous, the same way `md2x-css` does for the existing CSS temp-file cases).

In `src/cli/test/bats/real-toolchain-e2e.bats`, extend the existing `"e2e: tiny-doc.md converts to real HTML with recognizable Pandoc/CSS markup"` case (which already runs the real, non-stub `pandoc` against `tiny-doc.md` and checks for `'Tiny Doc'`/`'<style>'` in the output) with one more assertion: `assert_file_contains './tiny-doc-base.html' 'class="markdown-body"'`. This is the mechanism's real-Pandoc, non-stub proof — it needs only `pandoc` (no WeasyPrint/`--pdf-engine`), so it runs under the same capability gate (`e2e_require_pandoc`) the case already uses, and directly confirms the wrapper div actually appears in genuine Pandoc output, not just in the stub's recorded arguments.

Run `make test-cli` (which depends on `make all`) locally and confirm all cases pass, including the new/extended ones.

### 6. Real-render confirmation (mirrors task 002's validation approach)

Because a passing bats suite proves the *mechanism* fires but cannot, on its own, prove `github.css`'s rules visually apply the way task 002's investigation showed they weren't (WeasyPrint parsing successfully does not mean its rules match anything), also perform a real conversion and inspect the actual rendered output, following task 002's own precedent (`plan/phase-01-restore-pdf-styling/002-extend-visual-smoke-test-for-css.md`'s `## Status` section):

- If the environment has a real `pandoc`, `gs`, `pdftk`, and a working WeasyPrint (`~/.md2x/venv/bin/weasyprint` or equivalent bootstrap): run `./bin/md2x` (after `make all`) against `src/cli/test/tiny-doc.md` with default (PDF) output, rasterize the result with `gs -sDEVICE=png16m -r150 -o <out>-%d.png <out>.pdf`, and visually inspect the PNG (e.g. via the `Read` tool). Confirm, item by item, against task 002's checklist: sans-serif GitHub-style body font (not serif/`Times-New-Roman`), a visible background box behind the fenced code block, table cell borders/striping, and a visible H1>H2>H3 size/weight hierarchy. State plainly in the task report what was observed for each item.
- If the environment cannot run a real conversion (missing toolchain, no WeasyPrint bootstrap, non-interactive sandbox), state that plainly rather than claiming an unverified pass, and name what a human maintainer should confirm manually before treating this as fully resolved.

## Validation

- `grep -n "include-before-body\|include-after-body" src/cli/lib/generate-page.sh` shows both flags present in both Pandoc invocations, each gated by the `OUTPUT_FORMAT != docx` conditional from Requirement 3.
- `grep -n "markdown-body" src/cli/lib/generate-page.sh` shows the two new literal content strings (`MARKDOWN_BODY_OPEN`/`MARKDOWN_BODY_CLOSE` or equivalently named variables).
- `make all && make test-cli` passes, including the new/extended stub-based bats cases (Requirement 5) and the extended real-toolchain HTML e2e case.
- Manually confirm (or via the extended e2e case) that a real, non-stub `pandoc --to html5` conversion of `tiny-doc.md` produces output containing `class="markdown-body"`.
- Confirm the docx-exclusion regression guard: `refute_last_call_has_arg pandoc '--include-before-body'` and `'--include-after-body'` pass for `--output-format docx`, and (if feasible) a real `--output-format docx` conversion's `word/document.xml` contains no literal `<div` text.
- Requirement 6's real-render confirmation is performed and reported on plainly, one way or the other (observed styling per checklist item, or a stated environment blocker) — do not claim an unverified visual pass.
- `shellcheck src/cli/lib/generate-page.sh` (if available locally) reports no new warnings beyond the pre-existing baseline task 001's `## Status` section recorded (15 warnings as of that task).

## Assumptions

- Task 001 and task 002 have both already landed in this worktree (confirmed at investigation time via `git log`: `03d2874` is the current tip, with task 001's `240e72a` and task 002's fixture/smoke-test commits both ancestors) — `CSS_TMP_FILE`, the real `.css` delivery, and the enriched `tiny-doc.md` fixture (headings, code, table) this task's validation depends on are all already present.
- `github.css`'s selectors are exclusively bare `.markdown-body` class selectors with no `body.markdown-body` compound anywhere in the file (confirmed via `grep -c "markdown-body" src/cli/lib/github.css` → 259 matches, and a targeted search for `body\.markdown-body` → zero matches) — this is what makes a wrapping `<div>` equivalent to putting the class on `<body>` itself for every rule in the file. If a future `github.css` update introduces a `body.markdown-body`-anchored rule, this mechanism would need revisiting (not applicable today).
- `--include-before-body`/`--include-after-body` content is injected around the *entire* rendered body — title header (if `--infer-title`/`title` metadata is set) and `--toc` nav included, not just the Markdown-derived content — which was confirmed by inspection to be harmless and, if anything, desirable (consistent styling across the whole document, matching GitHub's own rendering behavior).
- No change to `docs/architecture.md`'s "Bundled stylesheet" or "Page generation" prose is made by this task, even though that prose (updated by task 003 to describe task 001's delivery fix) does not yet describe this mechanism — flagged as a documentation follow-up, out of this task's explicit scope per the dispatch instructions.

## References

- `plan/phase-01-restore-pdf-styling/002-extend-visual-smoke-test-for-css.md`'s `## Status` section — the root-cause finding this task fixes, and the visual-checklist/rasterize-and-inspect validation approach Requirement 6 mirrors.
- `plan/phase-01-restore-pdf-styling/001-fix-css-delivery-and-stream-handling.md` — the `CSS_TMP_FILE`/`mktemp` idiom and BSD-`mktemp` trailing-suffix pitfall this task's temp-file handling follows and avoids, respectively.
- `plan/followups.yaml` (project root) — followup `TNLq` (the original bug this task, together with task 001, fully resolves) and `yJ9C` (this specific gap, tracked pending this task).
- `src/cli/lib/github.css` — the vendored `github-markdown-css` stylesheet; every rule is scoped under a bare `.markdown-body` class selector (verified: 259 occurrences, none as `body.markdown-body`).
- `src/cli/test/stubs/pdftk` / `src/cli/test/stubs/pandoc` — the existing env-var-override and process-substitution-capture conventions (`MD2X_TEST_STUB_CAPTURE_DIR`, `pandoc-<n>-<kind>`) this task's stub extension follows.
- `src/cli/test/bats/real-toolchain-e2e.bats` — the real (non-stub) Pandoc e2e case this task extends for a genuine-Pandoc-output assertion.
- Pandoc 3.10.1 manual (`pandoc --help`, `pandoc -D html5`) — verified directly in this environment rather than assumed from memory; confirms `--include-before-body`/`--include-after-body` semantics and the default html5 template's lack of a body-class variable.

## Metadata

architectural_impact: false

## Checkpoint hints

- After implementing and testing the `generate-page.sh` change (Requirements 1-3) in isolation via a manual Pandoc invocation, before touching the test stub.
- After extending the `pandoc` stub (Requirement 4), before writing the new bats cases that depend on it.
- After the automated bats coverage (Requirement 5) passes, before performing the real-render confirmation (Requirement 6), since the latter is a report-only step with no further code changes.

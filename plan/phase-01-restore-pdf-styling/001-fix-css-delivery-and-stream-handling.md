# Fix Css Delivery And Stream Handling

## Purpose and scope

Fix followup `TNLq`'s root cause in `src/cli/lib/generate-page.sh`: `generate-page()` delivers the bundled GitHub CSS to Pandoc via `--css <(echo "${CSS}")` — a process-substitution path (`/dev/fd/N`) with no `.css` extension. WeasyPrint (the pinned `--pdf-engine`, wired in by the `pdf-engine-weasyprint` plan) cannot MIME-sniff a stylesheet from that path and silently drops it; HTML/DOCX output is unaffected since Pandoc's own `--css` handling doesn't depend on the path's extension. This task replaces that delivery mechanism with a real temp file, and — because WeasyPrint will now actually load the stylesheet and start emitting roughly ten non-fatal, multi-line `WARNING` lines per PDF conversion (per `TNLq`'s own investigation) — restructures how the conversion pipeline's stderr is handled so those warnings can never leak onto the CLI's real stdout (a parsed data channel via `--to-stdout`/`--list-files`) and a genuine fatal Pandoc/WeasyPrint error can never be silently swallowed.

This is not a standard-skill task; there is no dedicated CSS-delivery or stderr-handling skill to invoke. Follow the [Procedure](#procedure) below.

Scope is `src/cli/lib/generate-page.sh` plus the test-support files needed to cover the change: `src/cli/test/stubs/pandoc` and one or more `src/cli/test/bats/*.bats` files. Do not touch `docs/architecture.md`, `README.md`, or `docs/md2x-spec.md` — those belong to task 003 (`phase-01-restore-pdf-styling/003-update-stale-pdf-styling-docs.md`), which depends on this task landing first.

## Requirements

### 1. Real `.css` temp file for `--css`

- In `generate-page()`, before the `if [[ -z "${INPUT}" ]]; then ... else ... fi` block that builds the two Pandoc invocations, create one temp file per `generate-page()` call holding the existing `$CSS` content, with a filename ending in `.css` so WeasyPrint can MIME-sniff it. `mktemp` accepts a full path template with a literal suffix after the `X`s on both GNU (Linux) and BSD (macOS) `mktemp` — e.g. `mktemp "${TMPDIR:-/tmp}/md2x-css.XXXXXX.css"` — so this does not need a `mv`-after-creation workaround. Write `$CSS`'s content into it (e.g. `printf '%s' "${CSS}" > "${CSS_TMP_FILE}"`).
- Replace `--css <(echo "${CSS}")` with `--css "${CSS_TMP_FILE}"` in **both** the file-input branch (currently around line 33) and the `$INPUT`/stdin/single-page branch (currently around line 51). No process substitution should remain for `--css` anywhere in this file.
- Clean up `${CSS_TMP_FILE}` after both branches, gated on `KEEP_INTERMEDIATE` — mirror the existing convention immediately below the two branches (`[[ -n "${KEEP_INTERMEDIATE}" ]] || rm pandoc-log.log`, line 58): add an equivalent `[[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${CSS_TMP_FILE}"` line. `KEEP_INTERMEDIATE`'s documented purpose (README.md, docs/md2x-spec.md) is "the Pandoc log and the PDF header/footer overlay" — decide during implementation whether the CSS temp file is worth documenting as a third retained artifact (it's not user-authored content, just a copy of the bundled stylesheet) or should always be removed regardless of the flag; either is acceptable as long as the behavior is deliberate and consistent, not accidental. If choosing to keep it under `KEEP_INTERMEDIATE`, no CLI-facing doc text changes are required by this task (that class of doc update belongs to task 003, which will already be reviewing the affected docs, and can note the addition if you flag it).
- Under `set -o errexit`/`nounset`/`pipefail` (this file's rollup target `src/cli/md2x.sh` sets these), a `mktemp` or `printf > file` failure aborts `generate-page()` immediately — this is consistent with the file's existing fail-fast style (e.g. the unguarded `pdftk "${BASE_OUTPUT}" dump_data` call) and needs no additional error handling.
- The Pandoc test stub (`src/cli/test/stubs/pandoc`) already reads whatever `--css` points to via a plain `[[ -r "${CSS_FILE}" ]] && cat -- "${CSS_FILE}"` (see the file's "drain (and optionally capture)" section) — it works unchanged against a real file path, so no stub change is required purely for this requirement.

### 2. Stop merging pdf-engine stderr into stdout

- Remove the `2>&1 | { grep -vE '(\(\d+/\d+\)\s*$|Done|Unsupported stylesheet type)' || true; }` construct from both Pandoc invocations (and its explanatory comment, which references the now-obsolete filtering rationale and a nonexistent "this task's notes" pointer).
- Per followup `rndR`'s structural note, do not replace it with a different pattern-match filter — WeasyPrint's ~10 multi-line `WARNING` messages have no reliable machine-parseable boundary, so any `grep`-based approach either risks leaking unmatched noise onto stdout or swallowing a real fatal error inside a broad match. Instead, stop merging pdf-engine stderr into the CLI's real stdout at all: let Pandoc's (and, transitively, WeasyPrint's, since Pandoc invokes it as a subprocess that inherits Pandoc's own stderr fd) stderr output flow to the CLI's own real stderr, untouched. That is exactly what stderr is for, and nothing about the stdout-purity contract (`--to-stdout`, `--list-files`) constrains stderr content.
- As a defense-in-depth measure — not strictly required if Pandoc's own stdout is empirically inert when `-o <file>` is given, but cheap and removes reliance on that assumption holding across Pandoc/WeasyPrint versions — consider redirecting Pandoc's own stdout explicitly to `/dev/null` (e.g. `1>/dev/null`) while leaving stderr unredirected, so stdout purity is guaranteed by construction rather than by observed behavior. Use your judgment on whether this is warranted; document the choice either way in a short code comment.
- The pipeline's own exit status must directly reflect Pandoc's real exit code, so that a genuine fatal Pandoc/WeasyPrint failure still triggers `errexit` and aborts `generate-page()` (and therefore the whole CLI invocation) with a non-zero exit. Removing the `| grep ... || true` construct achieves this as a side effect — the old construct's `|| true` was itself a latent risk of swallowing a real failure under `pipefail` (grep exiting 1 on "no output" would otherwise falsely fail the pipeline even when Pandoc succeeded); removing the pipe removes that risk too.
- Do not reintroduce `2>&1` anywhere in the two Pandoc invocations.

### 3. Automated coverage

Add `bats` coverage proving the fix's core properties. The stub `pandoc` (`src/cli/test/stubs/pandoc`) currently has no way to emit stderr content or a non-zero exit; extend it with env-var-controlled overrides, following the same convention `src/cli/test/stubs/pdftk` already uses for `MD2X_TEST_STUB_PAGE_COUNT`/`MD2X_TEST_STUB_PAGE_DIMENSIONS` (documented at the top of that stub file) — e.g. `MD2X_TEST_STUB_STDERR` (content to write to the stub's stderr) and `MD2X_TEST_STUB_EXIT_CODE` (exit code override, default `0`). Update the stub's header comment to document the new overrides in the same style as the existing documentation block.

Add case(s) — in `src/cli/test/bats/pandoc-args.bats` or a new `src/cli/test/bats/pandoc-stream-handling.bats`, whichever reads more naturally given the existing file boundaries — asserting:

- When the stub writes arbitrary noise to stderr (including something that resembles the old filtered patterns, e.g. a `Loading pages (3/6)` or `Unsupported stylesheet type` line), `md2x`'s own stdout (`$output` from `md2x_run`) stays completely clean of that text, while `$stderr` does contain it — proving the content reached real stderr rather than being swallowed or leaked onto stdout. `--list-files` or `--to-stdout` output should be exactly what's expected with no extraneous lines mixed in.
- When the stub exits non-zero, `md2x` itself exits non-zero (`assert_failure`) — proving a real Pandoc/WeasyPrint failure still propagates and isn't masked.
- The `--css` argument passed to `pandoc` is a real path ending in `.css` (not a `/dev/fd/*` process-substitution path) — e.g. `assert_last_call_contains pandoc '.css'` plus `refute_last_call_contains pandoc '/dev/fd/'`. The existing `md2x_pandoc_capture css` helper should still work unchanged (it reads whatever `--css` pointed to) and can be used to assert the captured content still matches the bundled CSS.
- `--keep-intermediate` retains the CSS temp file, and without it the file is removed after conversion — extend or add alongside the existing `--keep-intermediate retains the pandoc log and pdf overlay after conversion` / `without --keep-intermediate, the pandoc log and pdf overlay are removed after conversion` cases in `pandoc-args.bats`. Extracting the actual temp path from the logged invocation (`md2x_stub_last_call_args pandoc`, which contains the full argument vector including the `--css` value) is the way to locate it for an existence check; whichever decision task 1's implementation made in Requirement 1 about whether `KEEP_INTERMEDIATE` gates this file should be reflected accurately here.

Run `make test-cli` (which depends on `make all`) locally and confirm all cases pass, including the new ones.

## Validation

- `grep -n "process substitution\|<(echo \"\${CSS}\")\|2>&1 | { grep" src/cli/lib/generate-page.sh` returns no matches — the process-substitution `--css` delivery and the `2>&1 | grep` construct are both gone from both Pandoc invocations.
- `grep -n "mktemp" src/cli/lib/generate-page.sh` shows the new temp-file creation, used in both branches.
- `make all && make test-cli` passes, including the new stderr/`.css`-delivery bats cases.
- Manually (or via a bats case) confirm: a `--css` argument recorded in the stub invocation log ends in `.css`, never matches `/dev/fd/`.
- Confirm via inspection that `KEEP_INTERMEDIATE`'s existing behavior for `pandoc-log.log` and the PDF overlay file is unchanged by this task — only the new CSS temp file's cleanup was added.
- `shellcheck src/cli/lib/generate-page.sh` (if available locally) reports no new warnings introduced by this change; not a hard requirement since bash sources aren't linted in CI (see AGENTS.md), but a useful sanity check given the strict-mode constraint.

## Assumptions

- Pandoc's own stdout is empty/inert when `-o <file>` is given (true across the Pandoc versions this project has targeted); the task allows an explicit `1>/dev/null` defensive redirect as an option rather than mandating one, since either choice satisfies the stdout-purity requirement as long as it's deliberate.
- `TMPDIR` may be unset in some environments (bats' own harness always sets it, but a bare interactive shell might not) — use `"${TMPDIR:-/tmp}"` rather than assuming it's set, consistent with `nounset`.
- This task does not attempt to reduce or curate the volume of stderr chatter a real PDF conversion now produces (WeasyPrint's ~10 warning lines plus any progress lines) — it only guarantees that chatter never reaches stdout and never masks a real failure. Task 002's visual smoke test extension is where a human confirms the actual rendered output looks right; this task's automated coverage is stub-based and cannot observe real WeasyPrint output.

## References

- `plan/followups.yaml` (project root) — followups `TNLq` (root cause), `rndR` (stderr-merge structural note), `egW0`/`Kjs2`/`efJF`/`zjG5` (explicitly out of scope for this plan).
- `docs/architecture.md` — "Bundled stylesheet" section (~line 81-83) and "Page generation / conversion pipeline" section describe the mechanism this task changes; task 003 updates that prose after this task lands.
- `src/cli/test/stubs/pdftk` — the existing `MD2X_TEST_STUB_PAGE_COUNT`/`MD2X_TEST_STUB_PAGE_DIMENSIONS` env-var override convention to mirror when extending the `pandoc` stub.
- `src/cli/test/helpers/common.bash`'s `md2x_run` — already captures stdout and stderr separately (`$output` vs `$stderr`), which is what makes the stdout-purity assertions in this task possible without further harness changes.

## Metadata

architectural_impact: false

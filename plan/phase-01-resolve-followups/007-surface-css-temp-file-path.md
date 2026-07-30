# Surface The CSS Temp File Path Under --keep-intermediate

## Purpose and scope

Closes followup `OUbU`. Unlike the Pandoc log (`pandoc-log.log`, written into the current working directory) and the PDF header/footer overlay (`<title>-overlay.pdf`, written into `--output-path`) — both of which land somewhere inside the user's own working/output tree and are therefore discoverable by normal directory listing when `--keep-intermediate` retains them — the CSS temp file lives in the system `TMPDIR` (created via `mktemp "${TMPDIR:-/tmp}/md2x-css.XXXXXX"` in `src/cli/md2x.sh`) and its path is never printed anywhere. So `--keep-intermediate` currently leaves it effectively undiscoverable/orphaned outside the user's working tree — a user who asks to keep intermediates has no way to find this one without inspecting the script source.

Read the current (already-hoisted, trap-cleaned) CSS temp-file handling in `src/cli/md2x.sh` (lines ~197-235: `CSS_TMP_FILE` is created once, up front, outside the per-file loop, and its cleanup is registered via a conditional `trap ... EXIT` that only fires when `--keep-intermediate` is *not* given) before planning the exact hook point — this is materially different from, and simpler than, the pre-hoisting version described in the original followup text (which predates the trap-based cleanup refactor).

## Requirements

- In `src/cli/md2x.sh`, immediately after `CSS_TMP_FILE` is created (and the conditional `trap` decision made — see lines ~216-235), add a message printed to stderr, gated on `[[ -n "${KEEP_INTERMEDIATE}" ]]`, naming the retained CSS temp file's path. Print it once per invocation (the file is created once, hoisted above the per-file loop — do not print it once per converted file). Model the wording on the existing `--keep-intermediate` behavior's spirit (the Pandoc log and overlay are simply left in place with no explicit announcement, because their location is already the user's own working/output directory; this file needs an explicit announcement precisely because its location — `TMPDIR` — is not) — something in the vein of:
  ```bash
  [[ -z "${KEEP_INTERMEDIATE}" ]] || echo "md2x: kept intermediate CSS file: '${CSS_TMP_FILE}'" >&2
  ```
  (exact wording is yours; keep it consistent with this script's other stderr messages — e.g. `ensure-weasyprint.sh`'s `"md2x: ..."` prefix convention — and print to stderr, not stdout, since stdout is the parsed data channel for `--list-files`/`--to-stdout`, same rationale `ensure-weasyprint.sh`'s own header comment already documents for its own messages).
  - Confirm this placement runs regardless of which conversion path executes afterward (per-file loop, `--single-page`, or stdin) — it should, since `CSS_TMP_FILE` creation happens once, before all three branches, but verify by reading the surrounding control flow rather than assuming.
- `--quiet` should **not** suppress this message: `--quiet` only controls the "Created `<file>`" status line (per `docs/md2x-spec.md`'s existing description of `--quiet`), and `--keep-intermediate` is an explicit opt-in to retaining and presumably wanting to locate these files — don't gate this new message on `QUIET`.
- Update `README.md`'s CLI reference table and `docs/md2x-spec.md`'s `--keep-intermediate` flag description (both currently say only "Retain the Pandoc log and PDF overlay file..." / "...the PDF header/footer overlay) instead of deleting them...", omitting the CSS temp file and the body-open/body-close temp files entirely) to mention that the CSS temp file's path is printed to stderr when retained. You do not need to enumerate the body-open/body-close temp files in the same edit (they're not in this followup's scope) unless you judge it trivial to do accurately alongside the CSS-file mention — use your judgment, but don't let scope creep here block the task.
- Add or extend a bats case in `src/cli/test/bats/pandoc-args.bats` — the existing `"--keep-intermediate retains the css temp file handed to pandoc after conversion"` case (around line 149) already locates the CSS temp file path via `md2x_stub_last_call_args pandoc | grep '\.css$'`; extend it (or add a sibling case) to also assert the new stderr message contains that same path. `md2x_run` (in `src/cli/test/helpers/common.bash`) already captures `$stderr` separately from `$output`/`$stdout` — use that.

## Validation

- `make test` passes, including the updated/added `pandoc-args.bats` coverage.
- Manually confirm: running `md2x --keep-intermediate --output-format pdf report.md` prints a stderr line naming the CSS temp file's actual path, and that the same run with `--quiet --keep-intermediate` still prints it (only the "Created ..." line is suppressed).
- `README.md` and `docs/md2x-spec.md`'s `--keep-intermediate` descriptions mention the CSS temp file path being surfaced.
- `grep -rn "OUbU" plan/followups.yaml` — confirm the id no longer appears after this task's report is applied (report the resolved id; removal is the manager's step via `followups_remove`).

## References

- `src/cli/md2x.sh` lines ~197-235 — `CSS_TMP_FILE` creation and the conditional `trap ... EXIT` registration; the message belongs right after this block.
- `src/cli/lib/ensure-weasyprint.sh` — model for this script's existing `"md2x: ..."` stderr-message convention and the stdout-purity rationale (`--list-files`/`--to-stdout` are parsed data channels).
- `src/cli/test/bats/pandoc-args.bats` — the existing `--keep-intermediate`/CSS-temp-file case to extend.
- `src/cli/test/helpers/common.bash` — `md2x_run`'s `$stderr` capture.
- `README.md`'s CLI reference table and `docs/md2x-spec.md`'s API definition table — the `--keep-intermediate` row/entry to update.
- `plan/followups.yaml` item `OUbU` — full original followup text.

# WeasyPrint Bootstrap Design Notes

## Purpose and scope

Design decisions and environment findings backing the `pdf-engine-weasyprint` plan. Captures the resolutions the planner applied to the three open questions the change request left to planner judgment, plus the local environment facts the plan assumes. Task documents reference this note rather than restating the rationale.

## Environment findings (verified locally, 2026-07-29)

| Fact | Value |
| --- | --- |
| `pandoc` | 3.10.1 at `/opt/homebrew/bin/pandoc` — past the 3.4 default-engine change (wkhtmltopdf → weasyprint) |
| `python3` | 3.14.6 at `/opt/homebrew/bin/python3`; `import ensurepip, venv` both succeed |
| `weasyprint` | not on `PATH` |
| `~/.md2x` | does not exist — a clean cold-start state is available for validation right now |
| `gs`, `pdftk`, `jq` | present on `PATH` |

The cold-start state (`~/.md2x` absent) is a one-shot resource: the first agent that runs a PDF conversion consumes it. Re-creating it is just `rm -rf ~/.md2x`, which the validation steps call for explicitly.

## Resolved open questions

### 1. Bootstrap failure messaging and exit code

**Decision: exit `2`, matching the existing missing-binary preflight contract.**

`src/cli/md2x.sh`'s preflight loop already exits `2` and names the missing binary; the spec and README both document exit `2` as "a required external dependency is not usable". A weasyprint bootstrap failure (venv creation failed, `pip install` failed, no network) is the same class of condition, so reusing exit `2` keeps one documented failure code rather than inventing a second. The message must name the failing step and give the manual remediation command so an operator behind a proxy or air gap can fix it by hand.

No retry, no fallback to a system `weasyprint`, no degradation to a broken PDF — consistent with the fail-fast posture `docs/architecture.md` documents for the whole pipeline.

### 2. Suppressing the one-time install notice under `--quiet`

**Decision: no. The notice is not `--quiet`-suppressible; it goes to stderr instead.**

Two reasons, the second load-bearing:

1. `--quiet` is documented narrowly — in the spec, the README table, and the `--help` text — as suppressing the `Created <file>` status message. Widening it to "suppress all informational output" changes a documented flag's meaning for no benefit.
2. **stdout is a parsed data channel.** `--list-files` prints file paths that `src/node/md2x.js` reads back out of `shell.exec(...)`'s stdout, and `--to-stdout` writes raw converted document bytes (including PDF binary) to stdout. Any bootstrap chatter on stdout corrupts both. So the install notice — *and every byte of subprocess output from `python3 -m venv`, `ensurepip`, and `pip install`* — must be redirected to stderr.

This makes the notice visible in an interactive terminal (its whole purpose: explaining a multi-second stall) while leaving both machine-readable stdout contracts untouched, under `--quiet` or not.

### 3. Version / staleness checking of `~/.md2x/venv`

**Decision: none for now. A one-time install is sufficient.**

The gate stays the cheap `[[ -x "${HOME}/.md2x/venv/bin/weasyprint" ]]` test — no version file, no pip-index round trip, no upgrade check. Rationale: any staleness mechanism either costs a network call on every PDF conversion (defeating the "cheap check" requirement) or needs a pinned-version manifest and an upgrade path, which is real machinery for a dependency that has been stable for the pipeline's needs. The escape hatch is documentation, not code: README notes that `rm -rf ~/.md2x/venv` forces a clean reinstall on the next PDF conversion.

If weasyprint pinning or auto-upgrade later proves necessary, it is an additive change to this one script and does not disturb anything else. Recorded as a candidate follow-up rather than in-scope work.

## Other decisions the task docs depend on

- **The bootstrap runs only for `--output-format pdf`.** The change request asks for a cheap check on every invocation *and* describes the install as happening "on first PDF conversion". Both hold if the `ensure-weasyprint` call site is gated on `OUTPUT_FORMAT == 'pdf'`: HTML/DOCX-only users never trigger a pip install for an engine they will never invoke. The gate lives at the call site in `src/cli/md2x.sh` (after `OUTPUT_FORMAT` is defaulted), not inside the function.
- **`python3` is checked unconditionally, for every output format.** This matches the change request and is consistent with existing behavior: `gs` and `pdftk` are already hard-required for HTML and DOCX conversions even though only the PDF path uses them.
- **Absolute engine path, never `PATH`.** `--pdf-engine="${HOME}/.md2x/venv/bin/weasyprint"` — the venv is deliberately never activated and never prepended to `PATH`, so a system weasyprint (if one exists) can neither shadow nor be shadowed by the managed one.
- **Concurrency is not addressed.** Two md2x processes racing a cold `~/.md2x` bootstrap could interleave writes into the same venv directory. Not defended against (no staging directory, no lockfile) — the simple in-place build with cleanup-on-failure matches the repository's existing plain-bash style, and a failed/partial venv self-heals because the `-x weasyprint` gate simply fails again and rebuilds. Flagged as a known limitation, not a planned fix.
- **Existing repo bash caveats are inherited, not fixed here.** A `${HOME}` containing spaces would word-split when the `--pdf-engine` flag is expanded unquoted in the pandoc argument list — the same class as tracked followup `95ND`. Out of scope for this plan; do not expand scope to fix it, and do not introduce *new* unquoted expansions beyond the one the flag mechanically requires.

## Validation constraint the plan must work around

`src/cli/test/test.sh` (built to `test-out/test.sh` and run by `make test`) is **interactive**: it calls `open -Fn` on each generated file and then blocks on `read -r THROW_AWAY` waiting for the operator to press Enter. It cannot be run unattended by an agent. Every task in this plan therefore validates by invoking the built `./bin/md2x` directly and inspecting the produced artifacts, rather than by running `make test` / `npm test`.

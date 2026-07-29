# Bootstrap WeasyPrint And Pin PDF Engine

## Purpose and scope

Make PDF conversion work on Pandoc >= 3.4 by pinning Pandoc's `--pdf-engine` to a WeasyPrint binary that md2x installs and manages itself in a per-user virtual environment at `~/.md2x/venv`.

Today `src/cli/lib/generate-page.sh` runs `pandoc --to html5 -o <file>.pdf` with no `--pdf-engine` flag, so it silently inherits Pandoc's default HTML-to-PDF engine. Pandoc 3.4 changed that default from `wkhtmltopdf` to `weasyprint`, and WeasyPrint has never been a documented md2x prerequisite — so every PDF conversion on a current Pandoc fails with `'weasyprint' not found`.

Files this task changes:

| File | Change |
| --- | --- |
| `src/cli/lib/ensure-weasyprint.sh` | **new** — the bootstrap module |
| `src/cli/lib/index.sh` | source the new module |
| `src/cli/md2x.sh` | add `python3` to the preflight loop; call the bootstrap, gated on PDF output |
| `src/cli/lib/generate-page.sh` | pass `--pdf-engine=<absolute path>` for PDF output only |

No standard skill covers this; follow the [Procedure](#procedure) below. This task is source-only — it changes no documentation. `README.md`, `AGENTS.md`, and `docs/project-structure.md` are task 002's; `docs/architecture.md` and `docs/md2x-spec.md` are Phase 02's. Do not edit them here.

## Requirements

### 1. New bootstrap module: `src/cli/lib/ensure-weasyprint.sh`

Defines a function (suggested name `ensure-weasyprint`, matching the existing `generate-page` naming style) plus the two path variables the rest of the CLI needs. It must:

- Derive its paths from `${HOME}`: the venv directory is `${HOME}/.md2x/venv` and the engine binary is `${HOME}/.md2x/venv/bin/weasyprint`. Define these once, as variables, and reference them everywhere rather than repeating literals — `generate-page.sh` consumes the binary path variable too. This is a **per-user cache directory, not project-relative**: a globally-installed `md2x` has no stable project root at runtime. Do not use XDG directories.
- **Return immediately** when `[[ -x "${WEASYPRINT_BIN}" ]]` holds. This is the warm path taken on essentially every invocation and must do no filesystem work beyond that one test, no network access, and produce no output.
- On the cold path, emit a single clearly-labeled one-time notice **to stderr** before doing any work — something like `md2x: installing weasyprint (one-time setup) into '<dir>'; this may take a minute...` — so a multi-second pip install is not a silent stall.
- Create the venv with `python3 -m venv "${VENV_DIR}"`, bootstrap pip inside it with the venv's own interpreter (`"${VENV_DIR}/bin/python3" -m ensurepip --upgrade`), then install with `"${VENV_DIR}/bin/python3" -m pip install weasyprint`. Both `venv` and `ensurepip` are Python stdlib — a separate `pip` binary is not required and must not be checked for. Always drive pip through the **venv's** interpreter, never the system `python3`.
- **Redirect every byte of subprocess output to stderr** (`>&2` on each of the three commands). This is load-bearing, not cosmetic: `src/node/md2x.js` parses generated file paths out of the CLI's stdout, and `--to-stdout` writes raw document bytes (including PDF binary) to stdout. Anything the bootstrap prints on stdout corrupts both.
- Confirm success by re-testing `[[ -x "${WEASYPRINT_BIN}" ]]` after the install, and emit a short completion notice to stderr.
- **On any failure** (venv creation, ensurepip, pip install, or the post-install existence check): print an error to stderr that names the step that failed, remove the incomplete `${VENV_DIR}` so the next invocation retries from clean rather than resuming a half-built venv, state the likely causes (no network, proxy, missing platform build tooling), give the manual remediation command, and `exit 2`.

  Exit `2` is deliberate: it is the code `src/cli/md2x.sh`'s existing preflight loop already uses for "a required external dependency is not usable", and the spec and README both document it that way. Do not invent a new exit code. Note that `set -o errexit` is active, so guard each step explicitly (e.g. `|| bootstrap_fail "..."`) rather than relying on the shell's default abort, which would produce no useful message.

- The notice is **not** suppressible via `--quiet`. `--quiet` is documented — in `docs/md2x-spec.md`, the `README.md` flag table, and the `--help` text in `src/cli/md2x.sh` — as suppressing only the `Created <file>` message; do not widen it. Sending the notice to stderr already keeps both machine-readable stdout contracts clean.
- No version or staleness check. The `-x` test is the entire gate: no version file, no pip index lookup, no upgrade path. Rationale in the [design notes](../notes/weasyprint-bootstrap-design.md).
- The venv is never activated and `${VENV_DIR}/bin` is never prepended to `PATH`. The engine is reached only by absolute path.

### 2. Register the module: `src/cli/lib/index.sh`

Add a `source ./ensure-weasyprint.sh` line alongside the existing `generate-page.sh` and `parameters.sh` sources, so `bash-rollup` inlines it into `bin/md2x`. The `Makefile`'s `CLI_LIB_SRC` uses `find src/cli/lib -type f`, so no `Makefile` change is needed.

### 3. Preflight and call site: `src/cli/md2x.sh`

- Add `python3` to the existing preflight loop (currently `for EXEC in gs pandoc pdftk; do`), keeping the identical `type ... || { echo "Required executable ... " >&2; exit 2; }` shape. `python3` is checked **unconditionally**, for every output format — consistent with `gs` and `pdftk`, which are already required even for HTML and DOCX conversions. Do **not** add a `pip` check and do **not** add a `weasyprint`-on-`PATH` check; WeasyPrint is no longer expected on `PATH` at all.
- Call the bootstrap **only when the output format is PDF**: gate the call on `[[ "${OUTPUT_FORMAT}" == 'pdf' ]]` at the call site, not inside the function. Place it after `OUTPUT_FORMAT` has been defaulted and validated (after the `test_formats` block, around the `OUTPUT_PATH` defaulting) and before the conversion loop begins. HTML- and DOCX-only users must never trigger a WeasyPrint install for an engine they will never invoke.

### 4. Pin the engine: `src/cli/lib/generate-page.sh`

Both `pandoc` invocations (the file branch and the `${INPUT}` stdin branch) must pass `--pdf-engine="${HOME}/.md2x/venv/bin/weasyprint"` — via the path variable from the bootstrap module — **for PDF output only**, never for `html` or `docx`. Follow the existing conditional-argument idiom already used for `--toc` in the same invocation, or set the flag into a variable above the invocations; either is acceptable, but both branches must stay in sync.

Use the absolute path. Do not rely on WeasyPrint being on `PATH`, and do not activate the venv.

Known inherited caveat, explicitly out of scope: a `${HOME}` containing a space would word-split when the flag expands unquoted in the argument list — the same class of pre-existing issue tracked as followup `95ND`. Do not fix it here and do not restructure the invocation to chase it; just do not introduce any *additional* unquoted expansions beyond the one flag.

## Validation

Run from the task worktree root. `npm install` first — task worktrees have no `node_modules`, and the build shells out to `npm exec bash-rollup`.

**Do not use `make test` / `npm test`.** `src/cli/test/test.sh` calls `open -Fn` on each output and then blocks on `read` waiting for a keypress; it cannot complete unattended. Validate by invoking the built CLI directly.

1. **Build.** `npm install && npm run build` succeeds and regenerates `bin/md2x`. Confirm `bash-rollup` actually inlined the new module: `grep -c 'ensure-weasyprint\|md2x/venv' bin/md2x` returns a non-zero count, and `bash -n bin/md2x` reports no syntax error.
2. **Cold-start PDF conversion.** `rm -rf ~/.md2x`, then run `./bin/md2x --output-path ./test-out src/cli/test/tiny-doc.md`. Expect: the one-time install notice appears **on stderr**, the install completes, `~/.md2x/venv/bin/weasyprint` exists and is executable, and `./test-out/tiny-doc.pdf` is produced. Verify the PDF is real and stamped — `pdftk ./test-out/tiny-doc.pdf dump_data | grep NumberOfPages` reports at least one page, and the file opens as a valid PDF (`file ./test-out/tiny-doc.pdf` reports PDF).
3. **Warm re-run.** Re-run the same command **without** clearing `~/.md2x`. Expect: no install notice, no reinstall, no network activity, visibly faster, and a valid PDF again.
4. **stdout purity on a cold start.** `rm -rf ~/.md2x`, then run `./bin/md2x --list-files --output-path ./test-out src/cli/test/tiny-doc.md 2>/dev/null` and confirm stdout contains **only** the output file path — no install notice, no pip/venv chatter. Repeat the spirit of this check for `--to-stdout` (redirect stdout to a file and confirm the file is a valid PDF, not PDF bytes with a text notice prepended). This check is the reason the bootstrap redirects to stderr; do not skip it.
5. **HTML and DOCX regression, and no spurious install.** `rm -rf ~/.md2x`, then run the same fixture with `--output-format html` and with `--output-format docx`. Both must succeed, and **`~/.md2x` must not be created** by either — proving the bootstrap is gated on PDF output.
6. **`python3` preflight failure.** Confirm a missing `python3` produces the standard message naming `python3` and exit code `2`. A `PATH`-shadowing invocation is sufficient, e.g. run the CLI with a `PATH` that excludes `python3` (keeping `gs`/`pandoc`/`pdftk` reachable) and check `echo $?` is `2`.
7. **Bootstrap failure handling.** Confirm the failure path produces a named-step error on stderr and exit `2`, and leaves no partial `~/.md2x/venv` behind. Simulate however is cleanest — e.g. point `HOME` at a temporary directory and make the venv creation or pip install fail (an unwritable target directory, or a `pip` install of a deliberately nonexistent package in a scratch copy of the function). Restore the real `~/.md2x` state afterward by re-running a normal PDF conversion.
8. **Scope check.** `git diff --stat` shows exactly the four source files named in [Purpose and scope](#purpose-and-scope) (one new, three modified). No documentation file, no `src/node/*` file, and no build output (`bin/`, `dist/`, `test-out/` are gitignored) appears in the diff.

## Metadata

architectural_impact: true

## Assumptions

- The task worktree starts without `node_modules`; `npm install` is a required first step.
- `python3` (>= 3.9, locally 3.14.6) is on `PATH` with `venv` and `ensurepip` importable — verified locally; `python3 -c "import ensurepip, venv"` succeeds.
- Pandoc is >= 3.4 (locally 3.10.1), so its default HTML-to-PDF engine is WeasyPrint and the pre-change PDF path is expected to be **broken before this task starts**. A PDF conversion failing with `'weasyprint' not found` at task start is the bug being fixed, not a new regression.
- `~/.md2x` may or may not exist when the task starts; every validation step that depends on cold state creates it explicitly with `rm -rf ~/.md2x`.
- The first `pip install weasyprint` downloads from PyPI and may take tens of seconds; a network connection is required for the cold-start validation steps.
- `make test` / `npm test` are interactive and unusable for unattended validation.

## References

- [WeasyPrint bootstrap design notes](../notes/weasyprint-bootstrap-design.md) — resolved open questions (exit code, stderr vs `--quiet`, no staleness check), the verified local environment, and the concurrency limitation this task deliberately does not address.
- [Plan overview](../overview.md) — full change scope, success criteria, and the documentation-principle shift Phase 02 completes.
- `src/cli/md2x.sh` — the preflight loop is around line 91; `OUTPUT_FORMAT` defaulting and validation around lines 99-109.
- `src/cli/lib/generate-page.sh` — the two `pandoc` invocations and the existing `--toc` conditional-argument idiom.
- `src/node/md2x.js` — shows why stdout purity matters: it reads generated paths back out of the CLI's stdout via `shelljs`.
- `Makefile` — `CLI_LIB_SRC` globs `src/cli/lib`, so a new module needs no `Makefile` edit; `$(CLI_BIN)` is produced by `bash-rollup`.

## Procedure

1. `npm install`, then `npm run build`, and confirm a PDF conversion currently fails with `'weasyprint' not found` — establishing the baseline.
2. Write `src/cli/lib/ensure-weasyprint.sh` and add its `source` line to `src/cli/lib/index.sh`.
3. Update `src/cli/md2x.sh`: `python3` in the preflight loop, plus the PDF-gated bootstrap call.
4. Update `src/cli/lib/generate-page.sh`: `--pdf-engine` on both `pandoc` invocations, PDF output only.
5. Rebuild and work through [Validation](#validation) in order.

## Checkpoint hints

- After creating `src/cli/lib/ensure-weasyprint.sh` and wiring it into `src/cli/lib/index.sh`.
- After updating `src/cli/md2x.sh` (preflight entry plus the gated call site).
- After updating `src/cli/lib/generate-page.sh` and confirming a cold-start PDF conversion succeeds end to end.

# Design Decisions

## Purpose and scope

Records the design decisions this plan makes for each audit finding, so the phase-decomposition and implementing agents do not re-derive them. Each item is labeled with its basis:

- **user decision**: binding, from the request.
- **planner decision**: implementation choice, low risk.
- **user answer**: a semver-locking question put to the user during planning. Each answer is recorded in its own note and linked from the section it settles.

Audit references use these IDs: `B`/`S`/`N` items from the interface audit, `D` items from the docs audit, and `R` items from the release audit. All three audits are itemized in the [audit coverage matrix](./audit-coverage.md).

## Exit-code contract

**User answer: the recommended contract is accepted** ([exit-code answer](./exit-code-contract-answer.md)). Covers user decision 5, S8, and D5.

| Code | Meaning | Examples |
| --- | --- | --- |
| `0` | Success | |
| `1` | Runtime or conversion failure | pandoc, gs, or pdftk failure; unreadable search root; input that is not valid UTF-8 or contains NUL bytes |
| `2` | Usage error | unknown option or missing option argument (with a "see `md2x --help`" hint); `--toc` with `--no-toc`; unsupported format; no arguments; empty stdin; directory arguments that yield no Markdown; a title unusable as a filename; output-name collisions; `-o`/`--to-stdout` with more than one output; `-` mixed with other inputs |
| `3` | Missing or unusable dependency | required binary absent; GNU getopt not found; bash too old or not bash; pandoc below the floor version; WeasyPrint bootstrap failure or lock timeout |

This changes the documented missing-dependency code from `2` to `3`. That is acceptable before 1.0, but it must be called out in `CHANGELOG.md`.

The Node wrapper surfaces the code on the thrown `Error`, as `error.exitCode`, and in its message.

## Error output

**Planner decision.** Covers S8 and user decision 5.

- A project-owned error helper replaces the bash-toolkit `echoerrandexit`/`echofmt`. Those toolkit functions emit unconditional ANSI color, call `tput cols`, and fold lines.
- Message prefix: `md2x: `.
- Color only when stderr is a TTY and `NO_COLOR` is unset. Never color when stderr is not a TTY.
- Raw tool errors must not leak:
  - `getopt:` messages are re-worded and followed by the usage hint.
  - The `type` output in preflight is replaced by quiet `command -v`.
  - `basename`/`dirname` calls use `--` or parameter expansion, so `-weird.md` works.
  - `mkdir` failures, such as an output path that is an existing file, are checked first and reported as md2x errors.
  - The `cat: package.json` noise is removed by making version inference lazy (see [Version inference](#version-inference-and-footer)).

## Short flags

**User answer: the recommended set is accepted** ([short-flag answer](./short-flag-set-answer.md)). Covers B5, user decision 2, and the "assign all shorts explicitly" instruction.

Shorts are defined in an explicit table. Nothing derives a short from a variable name any more.

- **With a short:** `-D --flatten-dirs`, `-F --output-format`, `-h --help`, `-o --output` (new), `-p --output-path`, `-s --to-stdout` (now matches the docs), `-t --title`.
- **Long only:** `--infer-title`, `--infer-version`, `--keep-intermediate`, `--list-files`, `--no-toc`, `--quiet`, `--single-page`, `--toc`, `--version` (new).
- The undocumented auto-shorts `-q`, `-l`, `-n`, and `-i` are removed. Using one becomes a usage error. The old `-s`=`--single-page` meaning is gone.

GNU getopt stays the parser, so these are kept as-is and documented:

- unambiguous long-option prefixes (`--single` works; `--no` currently resolves to `--no-toc`)
- `--opt=value`
- the attached short value form (`-p=x` means the value `=x`)

This follows user decision 6. It is a **LOW-RISK ASSUMPTION** and is flagged in the overview. Adding `--output` makes `--out` ambiguous, which is acceptable.

## Option parsing and GNU getopt

**Planner decision.** Covers S9 and user decision 8.

Covered in full in [brew and getopt resolution](./brew-and-getopt-resolution.md). In short: a project-owned parser in `src/cli/lib/`, getopt probing that does not need `brew`, help that works without getopt, and no `perl`.

## Bash version support

**Planner decision. Flagged as an assumption.** Covers B4.

md2x will **support bash 3.2**, the macOS `/bin/bash`, rather than require bash 4 or later. Most macOS users never install a newer bash, and the Node wrapper's child resolves `env bash` against whatever `PATH` it is given.

A live experiment on 2026-10-04 ran the built CLI under `/bin/bash` 3.2.57 after removing full-line comments inside the `< <( … )` file-discovery process substitution:

- `--help` and an HTML conversion worked.
- DOCX failed with `INCLUDE_BODY_ARGS[@]: unbound variable`, because bash before 4.4 treats an empty array as unset under `nounset`. **It still exited 0.**

The work this requires:

1. Remove the parse hazard: the apostrophes in comments inside `<( … )`, or restructure so no comment sits inside it.
2. Make empty-array expansions safe under `nounset` (`${ARR[@]+"${ARR[@]}"}`).
3. Make sure any failure inside the main conversion loop (`{ … } < <( … )`) exits non-zero under every supported bash. The experiment shows a silent exit 0 is possible today.
4. Add a POSIX-sh guard at the very top of `src/cli/md2x.sh`, ahead of all imports, that rejects a non-bash shell or bash older than 3.2 with exit 3. Bash parses and runs top-level commands one at a time, so the guard runs before any later parse error.
5. Give the bats harness an interpreter override (for example `MD2X_TEST_BASH=/bin/bash`), so the whole suite can run under 3.2. CI's macOS job runs it that way.

All later tasks must keep the code 3.2-compatible. Each task's validation runs the suite under the override wherever `/bin/bash` is 3.x.

## Per-run work directory

**Planner decision.** Covers B1, S13, N6, and part of R2.

- One `mktemp -d` work directory per invocation. Use a trailing-`X` template, because BSD `mktemp` only randomizes trailing `X`s.
- It holds every intermediate:
  - CSS file and body-open/body-close files
  - TOC-preprocessed Markdown
  - the `--single-page` concatenation, under a **fixed name** never derived from `--title`
  - captured stdin
  - pandoc log
  - PDF overlay
  - the pdftk multistamp output, which today is `${TITLE}-combined.pdf` in the cwd
- Nothing is written to the cwd except the requested outputs.
- The single `EXIT` trap removes the directory. With `--keep-intermediate`, it is kept instead and its path is printed once to stderr, replacing today's per-file CSS and combined-file notices.
- The pre-existing-file `rm` of `${TITLE:-input}.md` in the cwd is deleted outright.

## stdin

**Planner decision.** Covers B2 and part of S2.

- Copy stdin byte-for-byte into the work directory with `cat > "$WORK/stdin.md"`. The `while read LINE` loop goes away.
- Leading whitespace, backslashes, and a final line without a newline are all preserved.
- Empty stdin (a zero-byte file) is a usage error, exit 2.
- `generate-page` then always reads from a file path, and the `INPUT` variable is retired.

## HTML styling

**Planner decision.** Covers B3.

- HTML output must not reference anything under `TMPDIR`. Embed the bundled CSS inline as a `<style>` block, for example through `--include-in-header` with a work-dir file that wraps the CSS in `<style>…</style>`.
- Images are not embedded. A self-contained HTML option is out of scope and filed as a followup.
- PDF may keep `--css <workdir file>.css`, since WeasyPrint reads it during the run. The implementer may move PDF to the same inline approach if WeasyPrint output stays identical; check with the real-toolchain e2e.
- Regression checks:
  - Stub suite: the html pandoc invocation carries no `--css` pointing into `TMPDIR`, and the inline header file contains the CSS.
  - Real-toolchain e2e: the HTML contains `<style>` and no `href` into `TMPDIR`.

## Title handling

**Planner decision.** Covers S7 and user decision 6 (must-fix 6).

- **Filename sink.** When `--title` determines an output filename (no `-o`), the CLI rejects with exit 2 a title that is empty, `.`, `..`, or contains `/`, NUL, or control characters. The message suggests `-o`. When `-o` is given, the title is display-only and any printable text is allowed.
- **Metadata sink.** Pass the title with `pandoc -M "title=${TITLE}"`. A spike on 2026-10-04 with pandoc 3.10.1 confirmed this is a literal string: `O'Brien: *x* (a)b \\ "q"` came through verbatim. The YAML `--metadata-file` string building in `generate-page.sh` goes away. A JSON metadata file is not equivalent, because it parses the value as Markdown and applies smart quotes.
- **PostScript sink.** Escape `\`, `(`, and `)` and strip control characters before interpolating into the Ghostscript program. The same applies to the version string. Non-ASCII titles must not crash `gs`. This N8 robustness part stays in scope by user answer. Regression tests cover a title containing `\`, `(`, `)`, a control character, and non-ASCII text, and confirm `gs` exits 0 and the PDF is produced. Helvetica glyph coverage for non-Latin text is a documented limitation (N8).
- **Node sink.** Never derive a filesystem path from `title` (`src/node/md2x.js:91` today).
  - Phase 1 minimal fix: `fs.mkdtempSync` and a fixed staging name `input.md`.
  - Phase 2: the wrapper rewrite removes staging entirely by feeding `markdown` to `md2x -` on stdin.

## Output options

**Planner decision.** Covers user decision 2, S14, and S10.

- **`-o, --output <file|->`.** Explicit output file. It is valid only when exactly one output results: one file, stdin, or `--single-page`. Otherwise it is a usage error.
  - Format is inferred from a recognized extension (`.pdf`/`.html`/`.docx`) when `-F` is absent. A conflicting `-F` is an error.
  - `-o -` is the same as `--to-stdout`.
  - The parent directory is created as needed.
  - With `-o`, `--output-path` is a usage conflict.
- **`--to-stdout`.** Writes only to stdout, building the output inside the work directory. It needs exactly one output, and combining it with `--list-files` is a usage error. It still implies quiet.
- **`-p`.** Normalize a trailing `/`, so output is no longer printed as `o3//a.html`. An existing non-directory is a usage error.

## Input discovery

**Planner decision. Flagged as an assumption.** Covers S2, S15, N1, N3, and N7.

- **No arguments:** usage summary to stderr, exit 2.
- **Directories:** search case-insensitively for `*.md` and `*.markdown`. The output basename strips either extension. If the directory arguments yield zero files overall, exit 2 with "no Markdown files found". A single empty directory among others that do yield files gets a stderr warning.
- **Arguments:** duplicate arguments and files are converted once. Mixing `-` with other arguments is a usage error with a clear message.
- **Format:** `--output-format` is case-insensitive. An unsupported value lists `pdf|html|docx`.
- **Encoding:** input that is not valid UTF-8, or that contains NUL bytes, fails with exit 1 naming the file. The check can live in the Python preprocessor, which already reads every document.

## Output collision protection

**Planner decision.** Covers S4.

Before any conversion, compute every target path. Two inputs that map to the same target fail with exit 2, naming both sources and the target. This covers batch, `--flatten-dirs`, and directly named `d1/x.md d2/x.md`. Overwriting a pre-existing file from an earlier run stays allowed; that is today's behavior, and `--force`/no-clobber is a feature gap outside the audit items.

## Links and images

**Planner decision.** Covers user decision 4, S5, S6, and R7.

Replace the eval-built `perl` `LINK_CONVERTER` with a **Pandoc Lua filter** (`src/cli/lib/*.lua`), inlined by `bash-rollup` like `github.css`, written to the work directory, and passed with `--lua-filter`. Pandoc parses the destinations itself, so code spans and fences are skipped correctly. A spike on 2026-10-04 with pandoc 3.10.1 confirmed the filter correctly handles:

- multiple links on one line
- a link followed by more text
- `#fragment`s (`c.md#sec` becomes `c.html#sec`)
- reference-style definitions (`[ref]: g.md`)
- links inside code spans and fences, which it leaves alone
- absolute and URL-scheme links, which it leaves alone

The filter's rules:

- **Links.** A relative `*.md` (and `*.markdown`) target becomes `.<format>`, with any fragment kept.
- **Images.** These resolve against the **directory of the source file** that contains them. The filter needs per-source context:
  - In `--single-page` mode, the concatenation inserts a one-line marker before each source's content: `<!-- md2x:source-dir=<abs dir> -->`, surrounded by blank lines. The spike confirmed it survives `gfm` as a `RawBlock`. The filter tracks the current base directory from these markers and strips them.
  - For a single file, the base comes from the file's directory, passed with `-M` or an env var.
  - For stdin, the base is the cwd.
  - Rewrite targets by format. PDF and DOCX get an absolute path, which pandoc and WeasyPrint embed. HTML gets a path relative from the output file's directory to the image, so the HTML works in place.
- **Missing resources.** Surface missing-resource warnings instead of hiding them behind pandoc `--quiet`. Read pandoc's JSON `--log` from the work directory and print one `md2x: warning: could not find image '<path>' (referenced from <source>)` line per missing resource.
- **Dependencies.** `perl` stops being a dependency once the option parser is also replaced. The minimum pandoc version for the features used (Lua filter API, `pandoc.path`) is recorded for the N9 version-floor check.
- **Known limitations, to document:**
  - With `--flatten-dirs`, relative links across directories may not resolve.
  - In `--single-page` mode, links between combined files still point at sibling output files rather than becoming internal anchors.
  - A file converted with `--title` or `-o` is not renamed in other documents' links.
- **Stub harness.** `src/cli/test/stubs/pandoc` must learn the new arguments (`--lua-filter`, `-M`, `--include-in-header`). Filter behavior is tested with real pandoc in a gated bats file, which skips when pandoc is absent, like `real-toolchain-e2e.bats`.

## Version inference and footer

**Planner decision.** Covers S3 and user decision 5.

- Compute the version **only** when `--infer-version` is given.
- Resolve it relative to the first input's directory, or the cwd for stdin: `git -C <dir> rev-parse --show-toplevel`, then `package.json` at that top level. Read it with `jq -r`.
- Footer text: `Version: 2.3.4` unquoted, or `Version: working` when the tree is dirty.
- When not in a git work tree or there is no `package.json`, print one clear stderr warning and omit the version from the footer.
- `git` and `jq` become **conditional** dependencies, needed only with `--infer-version`. The check is lazy and exits 3. `jq` leaves the always-required preflight list.

## Dependency set and version floor

**Planner decision.** Covers user decision 8, N9, D1, and S16.

After this plan, the expected dependency set is as follows. The Phase 3 docs task must confirm it by grepping the final code.

| Dependency | When required | Notes |
| --- | --- | --- |
| bash 3.2 or later | always | |
| pandoc | always | at or above a floor version, checked in preflight with exit 3; the floor is set from the features used |
| Ghostscript (`gs`) | always | |
| `pdftk` | always | pdftk-java on modern macOS and Linux |
| `python3` | always | runs the TOC preprocessor and hosts WeasyPrint |
| GNU getopt | macOS | Linux util-linux provides it |
| standard POSIX utilities | always | `find`, `sort`, `mktemp`, and similar |
| WeasyPrint | PDF output | auto-managed in `~/.md2x/venv`; network needed on the first PDF run |
| `git`, `jq` | `--infer-version` only | |
| `perl` | not required | after Phase 2 |
| `brew` | not required | optional, only to locate gnu-getopt |

Windows is unsupported. WSL is untested.

## WeasyPrint warning flood

**Planner decision.** Covers S12 and user decision 5.

Prune or neutralize the rules in `src/cli/lib/github.css` that WeasyPrint reports as `WARNING: Ignored …`, so a normal PDF run produces no WeasyPrint warnings. A residual filter that drops only that exact warning class may be added if a rule cannot be pruned without visual change. Real errors must still reach stderr. Verify with the real toolchain and the visual smoke test.

## Node wrapper

**Planner decision. Flagged as an assumption: it supersedes "bump shelljs 0.10 if safe".** Covers user decision 7, S11, R2, R4, R9, and R12.

- **Process execution.** Replace `shelljs` with `node:child_process`: `execFileSync` and `execFile` with argv arrays. This removes the shell-quoting layer, the `shell: '/bin/bash'` requirement, and the runtime dependency.
- **`markdown`.** Feed it to the CLI on stdin as `md2x -` with the `input` option. No staging file, so no title-derived path.
- **`sources`.** `sources: ['-']` throws a clear `TypeError` telling the caller to use `markdown`; this is the fix for the hang. `sources: []` without `markdown` throws.
- **Option validation.** An unknown option key, `markdown` together with `sources`, or a wrong type throws `TypeError` before spawning.
- **Defaults.** The default title aligns with the CLI default (`output`); the current wrapper default is `Report`. This change is called out in the changelog.
- **New surface.** Add `md2xAsync()`, which returns a Promise. Add `output` (maps to `-o`) and `quiet` (suppresses forwarding CLI stderr to `console.error`).
- **Errors.** The thrown `Error` carries `exitCode` and `stderr`. Fix the "Could not covert" typo.
- **Packaging.**
  - Dual build: ESM and CJS bundles.
  - `package.json` `exports` with `import`/`require`/`types` conditions, plus `main` and `types`.
  - A hand-written `index.d.ts`.
  - Replace `__dirname` use in the ESM build with `import.meta.url`, or confirm the bundler shims it.
- **Validation.**
  - `npm pack`, then install the tarball into a temp project.
  - Run both `import { md2x } from '@liquid-labs/md2x'` under native Node ESM and `require()`.
  - Run `tsc --noEmit` against a consumer snippet if TypeScript is available via `bunx`/`npx`; otherwise validate the `.d.ts` syntactically.
- **Documented limitation.** A returned path that contains a newline mis-splits.
- **Coverage.** Close the Node coverage gaps from R12.

## Flag table single source

**Planner decision.** Covers D20 and the request to "generate or single-source the CLI flag table".

- `README.md`'s CLI reference table is the single human-readable source of flag descriptions.
- `docs/md2x-spec.md` keeps only normative behavior that is not in the README (the exit-code contract, conflict rules) and links to the README table instead of duplicating it.
- A bats drift test fails when the set of `(short, long)` flag pairs differs between the parser's definition table, `md2x --help`, and the README table.

## CI

**Planner decision.** Covers R1 and R6.

- GitHub Actions workflow with an `ubuntu-latest` and `macos-latest` matrix.
- Steps: `bun install --frozen-lockfile`, then `make qa`.
- System packages:
  - Ubuntu: `pandoc ghostscript pdftk-java jq python3`
  - macOS: `pandoc ghostscript pdftk-java jq gnu-getopt` (python3 is preinstalled)
- The macOS job also runs the bats suite under `/bin/bash` 3.2 with the harness override.
- The real-toolchain e2e cases run where the toolchain installs, and skip otherwise. They are not required to pass on both platforms if a package is unavailable; that limitation is documented.
- **CI cannot be proven green until the branch is pushed.** Pushing `main`, 117+ commits ahead of `origin`, is a user action.

## Release

**Planner decision.** Covers D11, R5, and R11.

- The registry shows `1.0.0-alpha.11` was published on 2026-10-04. That release ran `scripts/release.sh` at commit `a21f731`, which still used `npm publish`.
- **The `bun publish` path has never been exercised live.** The "unverified" sentence in `RELEASING.md` and in the `scripts/release.sh` header is therefore still literally true. It must be reworded accurately, not deleted on the false premise that alpha.11 verified it.
- The plan recommends a user-run throwaway prerelease (for example `1.0.0-rc.1` under the `rc` dist-tag) before `1.0.0`. It also documents the dry-run procedure, including the bun path and the `1.0.0` to `latest` path.
- Add `prepack: make all` (N10), after verifying `bun publish` runs lifecycle scripts.
- Org casing is normalized to lowercase `liquid-labs`, matching the `origin` remote and the npm scope. The repository URL becomes `git+https`.

## Deferred by user decision

**User answer: defer** ([N4/N8 scope answer](./n4-n8-scope-answer.md)).

- N4 (`--jobs` parallelism and progress output) and the feature parts of N8 (configurable header and footer, first-page header, font choice) are new feature surface rather than defects. They are deferred to followup `1wy6`. No task in this plan implements them.
- N8's robustness part stays in scope. Non-ASCII and PostScript-special titles must not crash `gs` or corrupt the overlay, as set out in [Title handling](#title-handling). It lands in Phase 1's title task.
- The README's known-limitations section (Phase 3) mentions that the header and footer are fixed and that non-Latin glyph coverage depends on the overlay font.

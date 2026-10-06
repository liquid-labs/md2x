# md2x Specification

## Purpose and scope

This document is the canonical statement of what md2x must do: its supported use cases, cross-cutting behavioral requirements, and external (CLI and Node library) surface. The intended readers are developers and AI agents implementing or modifying md2x, and reviewers checking proposed changes against what has been committed to. It assumes the reader has already oriented via [`README.md`](../README.md); this document does not repeat the project pitch or installation instructions found there.

This spec covers both of md2x's external surfaces — the `md2x` CLI and the thin Node.js library wrapper (`@liquid-labs/md2x`) — since the library is a pass-through to the CLI rather than an independent implementation. The flag-by-flag reference lives in the [README CLI reference](../README.md#cli-reference), the single human-readable flag table; this spec keeps only the normative behavior the table does not carry. It does not cover *how* the system is built (the PostScript/Ghostscript overlay-generation mechanism, the WeasyPrint bootstrap, the bash-rollup build process, internal module layout); that design-level material belongs in [`docs/architecture.md`](./architecture.md). Working conventions (build, test, lint) live in [`AGENTS.md`](../AGENTS.md). File and directory layout live in [`docs/project-structure.md`](./project-structure.md).

## Table of contents

1. [Key use cases](#key-use-cases)
2. [General features](#general-features)
3. [API definition](#api-definition)
4. [Constraints and assumptions](#constraints-and-assumptions)
5. [Non-goals](#non-goals)
6. [Pointers to deeper docs](#pointers-to-deeper-docs)

## Key use cases

### UC1: Convert a single Markdown file to PDF

- **Actor:** A developer with a Markdown document.
- **Action:** Runs `md2x report.md` (or the Node `md2x({ sources: ['report.md'] })` equivalent) with no `--output-format` given.
- **Outcome:** A `report.pdf` is written to the output path (current directory by default), styled with the built-in GitHub-style CSS, with an automatic page footer and header. The tool prints `Created ./report.pdf` (or the file path only, if `--list-files` is given).

### UC2: Convert a Markdown file to HTML or DOCX

- **Actor:** A developer who wants a non-PDF output.
- **Action:** Runs `md2x --output-format html report.md` or `md2x --output-format docx report.md`.
- **Outcome:** The file is converted with Pandoc to the requested format. Output is written as `report.html` or `report.docx` — same `<title>.<format>` naming convention as the PDF case in UC1. HTML output carries the same GitHub-style CSS; DOCX output never receives the header/footer overlay, though it does receive the same automatically generated table of contents as HTML and PDF output (see [General features](#general-features)). An unrecognized `--output-format` value is rejected with a fatal error before any conversion is attempted.

### UC3: Batch-convert a directory of Markdown files

- **Actor:** A developer with a directory tree of `*.md` files (for example, a documentation set).
- **Action:** Runs `md2x --output-path ./out ./docs`, optionally adding `--flatten-dirs`.
- **Outcome:** Every `*.md` file found recursively under `./docs` is converted individually. Without `--flatten-dirs`, each output file is written under `./out` at the path the input file occupies *relative to the search root it was found under* — the directory argument given on the command line (`./docs` here), so `./docs/guide/b.md` becomes `./out/guide/b.pdf`. A file named directly on the command line is rooted at its own directory and is written straight into `./out`. With `--flatten-dirs`, every output file is written directly into `./out`, discarding the input directory structure.

### UC4: Concatenate multiple Markdown files into one document

- **Actor:** A developer who wants several related Markdown files delivered as one output document.
- **Action:** Runs `md2x --single-page --title "Combined Report" chapter1.md chapter2.md chapter3.md`.
- **Outcome:** The input files are concatenated (in the order given) into one intermediate Markdown document before Pandoc conversion, producing a single output file named from `--title` (default `output`).

### UC5: Convert Markdown supplied on stdin

- **Actor:** A developer or another program piping Markdown text into md2x.
- **Action:** Runs `cat report.md | md2x -` (a lone `-` argument).
- **Outcome:** md2x reads the full input stream as the document to convert and produces one output file, using `--title` (default `output`) as the base filename.

### UC6: Embed md2x as a Node.js library dependency

- **Actor:** A Node.js application developer who has installed `@liquid-labs/md2x`.
- **Action:** Imports `{ md2x }` (or the Promise-returning `md2xAsync`) from `@liquid-labs/md2x` and calls it with either `sources` (file/directory paths) or a `markdown` string, plus any of the supported options (see [API definition](#api-definition)).
- **Outcome:** md2x performs the equivalent CLI conversion and returns an array of the generated output file paths. If the underlying conversion fails (non-zero exit from the CLI), the call throws an `Error` carrying the CLI's `exitCode` and `stderr`, both included in its message.

## General features

These requirements apply across every use case above, for both the CLI and the Node library:

- **Dependency preflight check.** Every conversion invocation verifies, before doing any conversion work, that `gs` (Ghostscript), `pandoc`, `pdftk`, and `python3` are present on `PATH` and that `pandoc` is at or above the floor version (2.0), and that GNU `getopt` is available (see [Constraints and assumptions](#constraints-and-assumptions)). `git` and `jq` are checked only when `--infer-version` is given. A missing or unusable dependency exits with code `3` (see [Exit behavior](#cli)) and names the first problem found. `--help` and `--version` run without the preflight and without GNU `getopt`.
- **Automatic WeasyPrint bootstrap (PDF output only).** On the first PDF conversion in a given environment, md2x installs [WeasyPrint](https://weasyprint.org/) — the engine Pandoc uses to render PDF output — into an isolated per-user virtual environment (`~/.md2x/venv`) if it is not already present, printing a one-time notice to stderr while it does so. WeasyPrint is not a manual prerequisite; `python3` (already required by the binary preflight check above) is what makes this possible. A failed bootstrap, or a timeout waiting for another process's bootstrap lock, exits with code `3` and names the failing step (see [Exit behavior](#cli)). Stdout stays clean throughout — the `--list-files` and `--to-stdout` contracts are unaffected — and `--quiet` does not suppress the notice, since the notice is a stderr message, not the `Created <file>` status line `--quiet` controls.
- **Consistent styling.** Every HTML or PDF output is rendered with a single, built-in GitHub-flavored CSS stylesheet. There is no per-invocation styling configuration.
- **Automatic PDF header/footer.** Every PDF output carries a footer showing the current page and total page count ("Page X of Y") and, on every page after the first, a running header showing the document title (from `--title`, or otherwise the source filename). The header and footer are fixed: their content, position, and font are not configurable, and there is no first-page header. When `--infer-version` is set, the footer also shows `Version: <version>`: the `package.json` version when `git status --porcelain` reports a clean working tree, or the literal string `working` otherwise; when no version can be determined the footer omits it, after one warning on stderr (see [Constraints and assumptions](#constraints-and-assumptions)). (The mechanism that produces this overlay is a design-level concern documented in [`docs/architecture.md`](./architecture.md), not this spec.)
- **Table of contents.** md2x generates its own table of contents as literal Markdown content — a nested list of links to the document's headings — rather than relying on Pandoc's native `--toc` machinery, and applies it uniformly to PDF, HTML, and DOCX output alike. Placement is controlled by a `<!-- md2x:toc -->` marker: place it on its own line anywhere in the source and md2x replaces that line with the generated list; without a marker, the TOC is inserted immediately after the document's title heading, or at the very top of the document if it has none. With neither `--toc` nor `--no-toc` given, a TOC is added only to documents estimated at more than about two rendered pages that also have four or more top-level sections — shorter or simpler documents get none by default, unless a `<!-- md2x:toc -->` marker is present, which always forces the TOC on regardless of size. `--toc` forces the TOC on regardless of document size; `--no-toc` forces it off, overriding both the default heuristic and an explicit marker. Passing both `--toc` and `--no-toc` together is a fatal error (see [Exit behavior](#cli)).
- **Cross-document link rewriting.** A relative link to a sibling `*.md` or `*.markdown` file (e.g. `[Foo](./bar.md#sec)`) is rewritten, by a Pandoc Lua filter, to point at that sibling's converted filename in the current output format (e.g. `./bar.pdf#sec`), keeping any fragment, so that a batch- or single-page-converted set of cross-linked documents remains navigable after conversion. Absolute paths, URL-scheme links (`https:`, `mailto:`), bare `#fragment` links, and links inside code spans and fenced code are left unchanged. Known limitations: with `--flatten-dirs`, relative links between files in different directories may not resolve; under `--single-page`, links between the combined files still point at the sibling output files rather than becoming internal anchors; a file converted with `--title` or `-o` is not renamed in other documents' links.
- **Image resolution.** A relative image path resolves against the directory of the source file that contains it (the current directory for stdin), not the directory md2x runs in. PDF and DOCX output embed the image; HTML output keeps a path from the output file to the image and is not self-contained. A relative image whose file does not exist produces one `md2x: warning: could not find image '<path>' (referenced from <source>)` line on stderr and does not change the exit code. Under `--single-page`, md2x inserts a `<!-- md2x:source-dir=... -->` marker before each source's content to track the base directory; known limitation: an unterminated code fence or raw HTML block in one source swallows the next source's marker, so that next source's images then resolve against the wrong directory.
- **Intermediate artifact cleanup.** Every intermediate artifact (including captured stdin and the `--single-page` concatenation) lives in one per-run work directory (created under `TMPDIR`), so nothing but the requested outputs is written to the working or output directory. The work directory is deleted when the run ends, success or failure, unless `--keep-intermediate` is given.

## API definition

md2x has two external surfaces: the CLI (`md2x`) and the Node library function (`md2x()`). The library is a thin wrapper that shells out to the built CLI, so its options are a subset of the CLI's flags — see the note at the end of this section. The CLI's flags, their short forms, and their one-line descriptions are in the [README CLI reference](../README.md#cli-reference); this section does not repeat them.

### CLI

**Input.** md2x accepts, as trailing arguments: one or more file paths, one or more directory paths (searched recursively for `*.md` and `*.markdown` files, matched case-insensitively), or a single `-` to read Markdown from stdin. Mixing files and directories in one invocation is supported; `-` must be the sole argument when used, and mixing it with any other input is a usage error. Duplicate inputs are converted once. File or directory names containing control characters are rejected.

**No arguments and empty input.** Invoking md2x with no input arguments prints a usage error and exits `2`. Empty stdin (a zero-byte document) is a usage error (exit `2`). Directory arguments that together yield no Markdown file are a usage error (exit `2`); an empty directory among others that do yield files is only a warning. Input that is not valid UTF-8 or contains NUL bytes fails with exit `1`, naming the file.

A symlinked `*.md` or `*.markdown` file found in a searched directory is followed (its target is read). Search roots are taken literally, whatever their names (for example `!`, `(` or `-x`), and are listed as the user typed them.

**Output delivery.** Each output is written to a temporary file in the target's directory and renamed over the target; a temporary file left by an interrupted run is removed on exit. A target that is a directory, or a symlink to one, is refused. Replacing an existing target creates a new file with a umask-derived mode, so the previous file's mode and ownership are not kept. The output directory and its parent directories must not be writable by an untrusted party: a parent directory swapped for a symlink during the run redirects delivery.

**Flags.** The authoritative list is the [README CLI reference](../README.md#cli-reference). The only short flags are `-D` (`--flatten-dirs`), `-F` (`--output-format`), `-h` (`--help`), `-o` (`--output`), `-p` (`--output-path`), `-s` (`--to-stdout`), and `-t` (`--title`); every other flag, including `--version`, is long-only, and any other short flag is a usage error. Option parsing uses GNU `getopt`, so long options may be abbreviated to any unambiguous prefix and values may be attached with `=`.

**Output and conflict rules.**

- `-o`/`--output <file>` and `--to-stdout` (`-s`, same as `-o -`) are valid only when exactly one output results: one input file, stdin, or `--single-page`. With more than one output they are a usage error.
- `-o <file>` conflicts with `-p`/`--output-path` and with `--to-stdout`; `--to-stdout` conflicts with `--list-files`. Each conflict is a usage error, checked before any conversion work.
- `-o <file>` infers the format from a `.pdf`, `.html`, or `.docx` extension when `-F` is absent; a contradicting `-F` is a usage error, and an unrecognized extension writes the default format (PDF) to the file exactly as named. The file's directory is created as needed; a path ending in `/` is a usage error.
- `-p` normalizes a trailing `/`; an existing non-directory is a usage error.
- `--toc` together with `--no-toc` is a usage error.
- Two inputs that would write the same output file (compared case-insensitively), or an output that would overwrite one of its own inputs, are a usage error naming the sources and the target, checked before any conversion starts.

**Title rules.** `--title` applies only when exactly one file is converted outside `--single-page` (a lone directly-named file, or a directory search resolving to exactly one file), and to the `--single-page` and stdin outputs; with more than one file on that path it is a usage error. The default title is `output` for `--single-page` and stdin; otherwise the output is named after its input. When `--title` determines the output filename (no `-o`, no `--to-stdout`), a title that is empty, `.`, `..`, or contains `/`, NUL, or control characters is a usage error; with `-o` or `--to-stdout` the title is display-only and any printable text is accepted. The title is passed to Pandoc as a literal metadata string and escaped for the PDF header, so quotes, backslashes, parentheses, and non-ASCII text cannot corrupt the output (glyph coverage for non-Latin scripts depends on the overlay's built-in font).

**Stdout contracts.** On success md2x prints `Created <file>` on stdout for each generated file, or only the file path with `--list-files`; `--quiet` suppresses the `Created` line. `--to-stdout` writes only the converted bytes to stdout (nothing to disk, implies `--quiet`); all diagnostics, including the first-run WeasyPrint notice, go to stderr, so stdout stays clean in every mode. Every error is one line on stderr prefixed `md2x: ` (warnings `md2x: warning: `), colored only when stderr is a terminal and `NO_COLOR` is unset.

**Exit behavior.** Exit codes are a contract:

| Code | Meaning | Examples |
| --- | --- | --- |
| `0` | Success | Warnings (missing image, omitted version) do not change the code. |
| `1` | Runtime or conversion failure | A `pandoc`, `gs`, or `pdftk` failure; an unreadable search root; input that is not valid UTF-8 or contains NUL bytes. |
| `2` | Usage error | An unknown option or missing option value; any conflict listed above; an unsupported `--output-format`; no arguments; empty stdin; directories with no Markdown; a path that is neither a file nor a directory; an unusable title; an output-name collision. |
| `3` | Missing or unusable dependency | A required binary absent; GNU `getopt` not found; bash too old or not bash; `pandoc` below the floor; a WeasyPrint bootstrap failure or lock timeout; `git` or `jq` absent with `--infer-version`. |

A missing dependency exits `3`; the alpha releases used a different code for it. Usage errors are reported before any conversion work begins and before a WeasyPrint bootstrap can start.

### Node library

```javascript
import { md2x } from '@liquid-labs/md2x'

const outputFiles = md2x({
  sources, // string[] — non-empty file and/or directory paths, never '-'; mutually exclusive with `markdown`
  markdown, // string — literal Markdown content, fed to the CLI on stdin; mutually exclusive with `sources`
  format, // 'pdf' (default) | 'html' | 'docx'
  flattenDirs, // boolean
  inferTitle, // boolean
  inferVersion, // boolean
  noToc, // boolean; mutually exclusive with `toc`
  toc, // boolean
  outputPath, // string; mutually exclusive with `output`
  output, // string — an output file (-o); never '-'
  title, // string
  singlePage, // boolean, default false
  quiet // boolean — do not forward the CLI's stderr to console.error
})
// md2xAsync(options) takes the same options and returns a Promise of the same array.
```

- **Returns:** `string[]` — the paths of the files generated by the conversion, equivalent to what the CLI would print with `--list-files`.
- **Throws:** a `TypeError`, before anything is spawned, for an unknown option key, a wrong type, `markdown` together with `sources`, an empty `sources`, or `-` in `sources` (`md2xAsync` rejects instead); otherwise an `Error` when the underlying CLI exits non-zero, carrying `exitCode` (the CLI's [exit code](#cli)) and `stderr`, with both in its message.
- **Requires** the same external dependencies (see [Constraints and assumptions](#constraints-and-assumptions)) as the CLI, since it shells out to the built CLI rather than reimplementing conversion. The automatic WeasyPrint bootstrap (see [General features](#general-features)) applies equally through the wrapper, since the CLI performs it regardless of caller.
- **Local-file and SSRF caveat:** image references, including absolute and parent-relative paths, are read from the local filesystem and embedded, as for the CLI (see [Constraints and assumptions](#constraints-and-assumptions)). WeasyPrint, the PDF rendering engine reached through the CLI this library shells out to, fetches external resources referenced in the converted HTML/CSS — image `src`, CSS `url()`/`@import`, including `file://` URLs — with no built-in allowlist. A consuming application that embeds `md2x()` to render externally-authored or otherwise untrusted Markdown should treat this the same as any other SSRF-capable rendering path: apply network egress restrictions around the process, or supply a WeasyPrint URL-fetcher override, rather than assuming the library sandboxes resource fetches on the caller's behalf.

**Surface asymmetry.** The Node library does not expose every CLI flag. `--list-files` is always applied internally (the function always returns generated paths rather than printing "Created …" messages); `--to-stdout` and `--keep-intermediate` have no corresponding library option and are reachable only via the CLI, and `--help` and `--version` are likewise CLI-only. The library's `quiet` option is not the CLI's `--quiet`: it suppresses forwarding of the CLI's stderr (warnings, the first-run notice) to `console.error`. A returned path that contains a newline is mis-split into several entries.

## Constraints and assumptions

- **Dependency set.** md2x requires, for both the CLI and the Node library:
  - bash 3.2 or later (the macOS system `/bin/bash` works); under an older bash or a non-bash shell md2x exits `3`;
  - `pandoc` at or above the floor version 2.0 (checked at startup, exit `3` below it; the floor comes from the Pandoc changelog, and only pandoc 3.10.1 has been exercised by hand), Ghostscript (`gs`), `pdftk` (pdftk-java is fine), and `python3`, all on `PATH`;
  - GNU `getopt` on macOS (Linux util-linux provides it). md2x finds it by probing `MD2X_GETOPT`, the Homebrew (Apple Silicon and Intel) and MacPorts locations, then `PATH`, accepting a candidate only when `getopt --test` reports GNU; Homebrew is optional and md2x never runs `brew` to install anything (it consults `brew --prefix` only as a last-resort probe, and only when `brew` is on `PATH`). `--help` and `--version` work without GNU `getopt`;
  - `git` and `jq`, only when `--infer-version` is given (checked lazily, exit `3` when absent);
  - the standard POSIX utilities (`find`, `sort`, `mktemp`, and so on).

  `perl` and `brew` are **not** required, and the Node wrapper has no `shelljs` or other runtime dependency. Windows is unsupported and WSL is untested. These tools remain the operator's responsibility to install, with one exception: WeasyPrint, the PDF rendering engine Pandoc uses, which md2x installs and manages itself in a per-user virtual environment at `~/.md2x/venv` (not project-relative, not an XDG directory) on the first PDF conversion. A first PDF conversion therefore requires network access to fetch WeasyPrint from PyPI; subsequent conversions reuse the installed environment.
- PDF output is rendered through an HTML5 intermediate rather than a LaTeX engine, so no `pdflatex` installation is required.
- `--infer-version` requires the invocation to run inside a git working tree with a readable `package.json`; it uses `git status --porcelain` to decide whether to report the `package.json` version or the literal string `working`. Version inference trusts the input repository only as far as its local git config is plainly harmless: git runs only in a repository whose own config (and per-worktree config, when `extensions.worktreeConfig` is set) holds nothing but an allowlist of keys: `core.repositoryformatversion`, `core.filemode`, `core.bare`, `core.logallrefupdates`, `core.ignorecase`, `core.precomposeunicode`, `core.symlinks`, `extensions.worktreeConfig`, `user.*`, `branch.*`, and the `url`, `pushurl`, and `fetch` variables of a remote (matched case-insensitively). Any other key (`remote.<name>.uploadpack`, `protocol.*`, `url.*`, `filter.*`, `include.*`, `submodule.*`, any other `extensions.*`, and so on) makes md2x warn once on stderr, naming the key, and omit the version from the footer without running `git status`; so does a config that cannot be read, as with git older than 2.22. The `git status` call itself is also hardened: it ignores system and global config, hooks, and fsmonitor, ignores submodules (a submodule's own config is never consulted), skips rename detection, forbids every transport (`protocol.allow=never`), and disables lazy fetching. Trade-offs of that hardening: dropping global and system git config can yield a false `working` version (for a global `core.excludesFile`, `core.autocrlf`/`core.eol`, or LFS filters configured globally, files that are clean under the user's normal git look modified), and dropping a global `safe.directory` means a repository owned by another user (a CI container, for example) is reported as `not inside a git work tree` and the version is omitted. Real partial clones, sparse checkouts, and submodule inputs fall outside the config allowlist and so also omit the version. The [README](../README.md#version-inference) summarizes the behavior for users.
- **Trust model.** md2x is not a sandbox, and converting untrusted Markdown is not safe by default (see [`SECURITY.md`](../SECURITY.md)). Image references, including absolute and parent-relative (`..`) paths, are read from the local filesystem and embedded in PDF and DOCX output, and the `could not find image` warning reveals whether a file exists. WeasyPrint fetches remote and `file://` resources with no allowlist (see the [SSRF caveat](#node-library)). A symlinked source found in a search is followed. Output directories must not be writable by an untrusted party (see Output delivery above).
- The Node library wrapper requires the CLI to already be built (`bin/md2x`, produced by `make all` / `bun run build`) — it is not usable straight from source without a build step.
- md2x is distributed as an Apache-2.0 licensed npm package (`@liquid-labs/md2x`).

## Non-goals

- md2x converts to PDF, HTML, and DOCX only; no other output format is supported.
- md2x does not expose arbitrary Pandoc CLI options as pass-through flags; only the flags in the [README CLI reference](../README.md#cli-reference) are supported.
- Deferred, not supported: parallel conversion (`--jobs`) and progress output, and configurable PDF header and footer content, a first-page header, and font choice. They are tracked as future work.
- md2x does not manage or install `pandoc`, `gs`, `pdftk`, or `python3` — it verifies their presence and fails fast (exit `3`) if one is missing, but installation of these four remains the operator's responsibility. The one deliberate exception is WeasyPrint: because it is a Pandoc implementation detail the user never invokes directly, md2x installs and manages it itself (see [Constraints and assumptions](#constraints-and-assumptions) and [General features](#general-features)).
- The Node library API is not a full superset of the CLI's flags — the [Node library](#node-library) surface omits `--to-stdout`, `--list-files`, and `--keep-intermediate`, which are reachable only via the CLI.

## Pointers to deeper docs

- [`docs/architecture.md`](./architecture.md) — design-level material not covered here: the PDF header/footer overlay mechanism (Ghostscript-rendered PostScript merged onto the Pandoc output via `pdftk multistamp`), the WeasyPrint bootstrap, and the bash-rollup build pipeline.
- [`AGENTS.md`](../AGENTS.md) — build, test, and contribution conventions for working on md2x itself.
- [`docs/project-structure.md`](./project-structure.md) — the project's file and directory layout.

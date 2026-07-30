# md2x Specification

## Purpose and scope

This document is the canonical statement of what md2x must do: its supported use cases, cross-cutting behavioral requirements, and external (CLI and Node library) surface. The intended readers are developers and AI agents implementing or modifying md2x, and reviewers checking proposed changes against what has been committed to. It assumes the reader has already oriented via [`README.md`](../README.md); this document does not repeat the project pitch or installation instructions found there.

This spec covers both of md2x's external surfaces — the `md2x` CLI and the thin Node.js library wrapper (`@liquid-labs/md2x`) — since the library is a pass-through to the CLI rather than an independent implementation. It does not cover *how* the system is built (the PostScript/Ghostscript overlay-generation mechanism, the WeasyPrint bootstrap, the bash-rollup build process, internal module layout); that design-level material belongs in [`docs/architecture.md`](./architecture.md). Working conventions (build, test, lint) live in [`AGENTS.md`](../AGENTS.md). File and directory layout live in [`docs/project-structure.md`](./project-structure.md).

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
- **Outcome:** The file is converted with Pandoc to the requested format. HTML output carries the same GitHub-style CSS; DOCX output never receives the header/footer overlay or an automatic table of contents (regardless of `--no-toc`). An unrecognized `--output-format` value is rejected with a fatal error before any conversion is attempted.

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
- **Action:** Imports `{ md2x }` from `@liquid-labs/md2x` and calls it with either `sources` (file/directory paths) or a `markdown` string, plus any of the supported options (see [API definition](#api-definition)).
- **Outcome:** md2x performs the equivalent CLI conversion and returns an array of the generated output file paths. If the underlying conversion fails (non-zero exit from the CLI), the call throws an `Error` whose message includes the exit code and the CLI's stderr output.

## General features

These requirements apply across every use case above, for both the CLI and the Node library:

- **Binary preflight check.** Every invocation verifies that `pandoc`, `gs` (Ghostscript), `pdftk`, and `python3` are present on `PATH` before doing any conversion work. If any is missing, the invocation exits with code `2` and names the first missing binary.
- **Automatic WeasyPrint bootstrap (PDF output only).** On the first PDF conversion in a given environment, md2x installs [WeasyPrint](https://weasyprint.org/) — the engine Pandoc uses to render PDF output — into an isolated per-user virtual environment (`~/.md2x/venv`) if it is not already present, printing a one-time notice to stderr while it does so. WeasyPrint is not a manual prerequisite; `python3` (already required by the binary preflight check above) is what makes this possible. A failed bootstrap exits with code `2` and names the failing step (see [Exit behavior](#cli)). Stdout stays clean throughout — the `--list-files` and `--to-stdout` contracts are unaffected — and `--quiet` does not suppress the notice, since the notice is a stderr message, not the `Created <file>` status line `--quiet` controls.
- **Consistent styling.** Every HTML or PDF output is rendered with a single, built-in GitHub-flavored CSS stylesheet. There is no per-invocation styling configuration.
- **Automatic PDF header/footer.** Every PDF output carries a footer showing the current page and total page count ("Page X of Y") and, on every page after the first, a running header showing the document title (from `--title`, or otherwise the source filename). When `--infer-version` is set, the footer also shows a version string: the `package.json` version when `git status --porcelain` reports a clean working tree, or the literal string `working` otherwise. (The mechanism that produces this overlay is a design-level concern documented in [`docs/architecture.md`](./architecture.md), not this spec.)
- **Table of contents.** PDF and HTML output receive an automatic table of contents from Pandoc unless `--no-toc` is given. DOCX output never receives an automatic table of contents.
- **Cross-document link rewriting.** A relative Markdown link to a sibling `.md` file (e.g. `[Foo](./bar.md)`) is rewritten in the converted output to point at that sibling's converted filename in the current output format (e.g. `./bar.pdf`), so that a batch- or single-page-converted set of cross-linked documents remains navigable after conversion. Absolute paths and `http(s)://` links are left unchanged.
- **Intermediate artifact cleanup.** Build-time intermediate artifacts (the Pandoc log, and, for PDF output, the header/footer overlay file) are deleted after a successful conversion unless `--keep-intermediate` is given.

## API definition

md2x has two external surfaces: the CLI (`md2x`) and the Node library function (`md2x()`). The library is a thin wrapper that shells out to the built CLI, so its options are a subset of the CLI's flags — see the note at the end of this section.

### CLI

**Input.** md2x accepts, as trailing arguments: one or more file paths, one or more directory paths (searched recursively for `*.md` files), or a single `-` to read Markdown from stdin. Mixing files and directories in one invocation is supported; `-` must be the sole argument when used.

**Flags.**

| Flag | Required behavior |
| --- | --- |
| `-D`, `--flatten-dirs` | Write every output file directly into `--output-path`, discarding input directory structure, instead of mirroring each input file's path relative to the search root it was found under. |
| `--infer-title` | Embed the title (`--title`, or otherwise the filename) as document metadata via Pandoc (e.g. the HTML `<title>` element). |
| `--infer-version` | Add the inferred version string (see [General features](#general-features)) to the PDF footer. |
| `--keep-intermediate` | Retain the Pandoc log and PDF overlay file instead of deleting them after conversion. Also retains the CSS temp file, printing its path to stderr (not suppressed by `--quiet`) since — unlike the log and overlay — it lives outside the working/output tree, in `TMPDIR`. |
| `-p`, `--output-path <path>` | Directory to write output files into. Defaults to `.`. |
| `-F`, `--output-format <format>` | Output format: `pdf` (default), `html`, or `docx`. Any other value is a fatal error. |
| `-t`, `--title <title>` | Document title, used for the output filename and the PDF header text. |
| `--single-page` | Concatenate all input Markdown files into a single document before conversion. |
| `--quiet` | Suppress the "Created `<file>`" status message. |
| `--list-files` | Print only the generated file path(s) instead of "Created `<file>`". |
| `-s`, `--to-stdout` | Write the converted output to stdout instead of (only) a file. Implies `--quiet`. |
| `--no-toc` | Suppress the automatic table of contents for `pdf`/`html` output. Has no effect on `docx` output, which never receives one. |
| `-h`, `--help` | Print usage text and exit `0`, without performing the binary preflight check or any conversion. |

**Exit behavior.** Exits `0` on success. Exits `2` and names the missing binary when a required external binary is absent, or names the failing step when the automatic WeasyPrint bootstrap fails (see [General features](#general-features)). Exits non-zero with a descriptive message for any input path that is neither a file nor a directory, or for an unrecognized `--output-format`.

### Node library

```javascript
import { md2x } from '@liquid-labs/md2x'

const outputFiles = md2x({
  sources, // string[] — file and/or directory paths; mutually exclusive with `markdown`
  markdown, // string — literal Markdown content to convert, in place of `sources`
  format, // 'pdf' (default) | 'html' | 'docx'
  flattenDirs, // boolean
  inferTitle, // boolean
  inferVersion, // boolean
  noToc, // boolean
  outputPath, // string
  title, // string
  singlePage // boolean, default false
})
```

- **Returns:** `string[]` — the paths of the files generated by the conversion, equivalent to what the CLI would print with `--list-files`.
- **Throws:** an `Error` when the underlying CLI invocation exits non-zero; the message includes the exit code and the CLI's stderr.
- **Requires** the same external binaries (`pandoc`, `gs`, `pdftk`, `python3`) on `PATH` as the CLI, since it shells out to the built CLI rather than reimplementing conversion. The automatic WeasyPrint bootstrap (see [General features](#general-features)) applies equally through the wrapper, since the CLI performs it regardless of caller.

**Surface asymmetry.** The Node library does not expose every CLI flag. `--list-files` is always applied internally (the function always returns generated paths rather than printing "Created …" messages); `--quiet`, `--to-stdout`, and `--keep-intermediate` have no corresponding library option and are reachable only via the CLI.

## Constraints and assumptions

- md2x requires `pandoc`, Ghostscript (`gs`), `pdftk`, and `python3` to be installed and present on `PATH` at runtime, for both the CLI and the Node library; these four remain the operator's responsibility to install. The one exception is WeasyPrint, the PDF rendering engine Pandoc uses: md2x installs and manages it itself, in a per-user virtual environment at `~/.md2x/venv` (not project-relative, not an XDG directory), on the first PDF conversion. A first PDF conversion therefore requires network access to fetch WeasyPrint from PyPI; subsequent conversions reuse the installed environment.
- PDF output is rendered through an HTML5 intermediate rather than a LaTeX engine, so no `pdflatex` installation is required.
- `--infer-version` requires the invocation to run inside a git working tree with a readable `package.json`; it uses `git status --porcelain` to decide whether to report the `package.json` version or the literal string `working`.
- The Node library wrapper requires the CLI to already be built (`bin/md2x`, produced by `make build` / `npm run build`) — it is not usable straight from source without a build step.
- md2x is distributed as an internal, `UNLICENSED` npm package (`@liquid-labs/md2x`) and is not intended for external or public distribution.

## Non-goals

- md2x does not expose arbitrary Pandoc CLI options as pass-through flags; only the flags listed in [API definition](#api-definition) are supported.
- md2x does not manage or install `pandoc`, `gs`, `pdftk`, or `python3` — it verifies their presence and fails fast if one is missing, but installation of these four remains the operator's responsibility. The one deliberate exception is WeasyPrint: because it is a Pandoc implementation detail the user never invokes directly, md2x installs and manages it itself (see [Constraints and assumptions](#constraints-and-assumptions) and [General features](#general-features)).
- The Node library API is not a full superset of the CLI's flags — the [Node library](#node-library) surface omits `--to-stdout`, `--quiet`, and `--keep-intermediate`, which are reachable only via the CLI.

## Pointers to deeper docs

- [`docs/architecture.md`](./architecture.md) — design-level material not covered here: the PDF header/footer overlay mechanism (Ghostscript-rendered PostScript merged onto the Pandoc output via `pdftk multistamp`), the WeasyPrint bootstrap, and the bash-rollup build pipeline.
- [`AGENTS.md`](../AGENTS.md) — build, test, and contribution conventions for working on md2x itself.
- [`docs/project-structure.md`](./project-structure.md) — the project's file and directory layout.

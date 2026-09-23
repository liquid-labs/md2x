# md2x

md2x is a command-line utility (with a thin Node.js wrapper) that converts Markdown documents into PDF, HTML, DOCX, and other [Pandoc](https://pandoc.org/)-supported formats. It builds on Pandoc with features Pandoc doesn't provide out of the box: consistent GitHub-style styling, automatic page headers/footers, batch directory processing, and single-page concatenation of multiple Markdown files.

## Installation

md2x requires the following external binaries on `PATH`:

- [`pandoc`](https://pandoc.org/installing.html)
- [Ghostscript](https://www.ghostscript.com/) (`gs`)
- [`pdftk`](https://www.pdflabs.com/tools/pdftk-the-pdf-toolkit/)
- [`python3`](https://www.python.org/)
- [`jq`](https://jqlang.org/)

md2x checks for these at startup and exits (code `2`) naming the first missing binary.

[WeasyPrint](https://weasyprint.org/) — the engine Pandoc uses to render PDF output — is **not** a manual prerequisite: md2x installs it automatically into an isolated per-user virtual environment at `~/.md2x/venv` the first time a PDF conversion runs, printing a one-time notice while it does so. `python3` is what makes this possible, which is why it's on the list above. That first PDF conversion therefore takes noticeably longer and needs network access; `rm -rf ~/.md2x/venv` forces a clean reinstall on the next PDF conversion.

On macOS, [Homebrew](https://brew.sh/) must also be installed: md2x's option parser resolves GNU getopt via `brew --prefix gnu-getopt` on every invocation, on macOS only.

Install md2x itself as an npm dependency, or globally for the standalone CLI:

```bash
npm install @liquid-labs/md2x
# or, for the standalone 'md2x' command
npm install -g @liquid-labs/md2x
```

## Usage

### As a CLI

```bash
# Convert a single Markdown file to PDF (the default format)
md2x report.md

# Convert every *.md file in a directory to HTML, with an inferred title and version footer
md2x --output-format html --infer-title --infer-version --output-path ./out ./docs

# Concatenate several files into one PDF
md2x --single-page --title "Combined Report" chapter1.md chapter2.md chapter3.md

# Read Markdown from stdin
cat report.md | md2x -
```

### As a Node library

```javascript
import { md2x } from '@liquid-labs/md2x'

const outputFiles = md2x({
  sources     : ['report.md'],
  format      : 'pdf',
  inferTitle  : true,
  inferVersion: true
})
```

`md2x()` shells out to the built CLI (`bin/md2x`) under the hood via `shelljs` and returns the list of generated file paths. Applications embedding `md2x()` against externally-authored Markdown should review the [WeasyPrint SSRF/local-file caveat](docs/md2x-spec.md#node-library) before doing so.

## Features

- Converts Markdown to PDF, HTML, or DOCX via Pandoc, rendering PDF through an HTML5 intermediate with WeasyPrint so no `pdflatex` install is required.
- Consistent GitHub-style CSS applied to every HTML/PDF page.
- Automatic PDF page footers ("Page X of Y") and a running header with the document title, with an optional inferred version string.
- Batch conversion of whole directories, recursing to find every `*.md` file.
- `--single-page` concatenates multiple Markdown files into one output document.
- Rewrites relative Markdown links (`./bar.md`) to point at the sibling document's converted extension (`./bar.pdf`) in cross-linked document sets.
- Generates the table of contents itself, as Markdown content, so PDF, HTML, and DOCX output all get the same TOC, placed wherever the author asks for it.

## CLI reference

md2x accepts one or more file paths, one or more directory paths (searched recursively for `*.md` files), or a single `-` argument to read Markdown from stdin.

| Flag | Description |
| --- | --- |
| `-D`, `--flatten-dirs` | Write all output files directly into `--output-path` instead of mirroring the input directory structure. Without this flag, each output file is written under `--output-path` at the path its input occupies *relative to the directory argument it was found under*; a file named directly on the command line goes straight into `--output-path`. |
| `--infer-title` | Embed the title (from `--title`, or otherwise the filename) as document metadata via Pandoc (e.g. the HTML `<title>` element). |
| `--infer-version` | Add an inferred version string to the PDF footer: the `package.json` version when `git status --porcelain` is clean, or `working` when the tree is dirty. |
| `--keep-intermediate` | Keep intermediate build artifacts (the Pandoc log and the PDF header/footer overlay) instead of deleting them after conversion. The CSS temp file is also retained, and its path is printed to stderr (not suppressed by `--quiet`), since it lives outside the working/output tree in `TMPDIR`. |
| `-p`, `--output-path <path>` | Directory to write output files into. Default: `.`. |
| `-F`, `--output-format <format>` | Output format: `pdf` (default), `html`, or `docx`. |
| `-t`, `--title <title>` | Document title; used for the output filename and the PDF header text. Only applies when exactly one file is converted outside `--single-page`; combining with multiple source files is a fatal error. |
| `--single-page` | Concatenate all input Markdown files into a single document before conversion. |
| `--quiet` | Suppress the "Created `<file>`" status message. |
| `--list-files` | Print only the generated file path(s), instead of "Created `<file>`". |
| `-s`, `--to-stdout` | Write the converted output to stdout (implies `--quiet`). |
| `--toc` | Force a table of contents on, regardless of document size. |
| `--no-toc` | Force the table of contents off, overriding both the default size heuristic and a `<!-- md2x:toc -->` marker in the source. Passing `--toc` and `--no-toc` together is a fatal error. |

### The PDF header/footer overlay

Every PDF md2x generates gets a footer with page numbers ("Page X of Y"), and, on every page after the first, a header with the document title (from `--title`, or inferred from the filename). With `--infer-version`, the footer also shows the version string described above. This overlay is produced by rendering a standalone PostScript document with Ghostscript (`gs`) and merging it onto the Pandoc-generated PDF with `pdftk ... multistamp`.

### The table of contents

md2x can generate a table of contents as ordinary Markdown content, rather than relying on Pandoc's own `--toc` machinery. Because the TOC is real document content instead of a renderer-specific navigation block, it renders identically across PDF, HTML, and DOCX output — including as clickable bookmarks in DOCX, which previously received no TOC at all.

To control where the TOC lands, place a `<!-- md2x:toc -->` marker on its own line anywhere in the source; md2x replaces that line with the generated list. The marker is an ordinary HTML comment, so it's invisible when the document is viewed on GitHub, in an editor, or in any other Markdown renderer. Without a marker, the TOC is inserted immediately after the document's title heading, or at the very top of the document if it has no title heading.

With neither `--toc` nor `--no-toc` given, md2x adds a TOC only to documents estimated at more than about two rendered pages that also have four or more top-level sections; shorter or simpler documents get none by default. `--toc` and `--no-toc` override that default in either direction (and passing both together is a fatal error, as noted above).

Two limitations carry over from the underlying heading-identifier algorithm: a heading containing an emoji character gets a TOC entry whose link may not resolve, and headings nested inside blockquotes or list items are not included in the TOC at all.

## Additional documentation

- Working on this project (build, test, conventions): [AGENTS.md](./AGENTS.md)
- Full specification: [docs/md2x-spec.md](./docs/md2x-spec.md)
- Architecture and conversion pipeline: [docs/architecture.md](./docs/architecture.md)
- Project structure and file layout: [docs/project-structure.md](./docs/project-structure.md)
- Release history: [CHANGELOG.md](./CHANGELOG.md)

## License

This package is marked `"license": "UNLICENSED"` in `package.json`. It is Liquid-Labs internal tooling and is not published for external or open-source use.

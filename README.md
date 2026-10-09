# md2x

md2x is a command-line utility (with a thin Node.js wrapper) that converts Markdown documents into PDF, HTML, and DOCX. It builds on [Pandoc](https://pandoc.org/) with features Pandoc doesn't provide out of the box: consistent GitHub-style styling, automatic page headers and footers, batch directory processing, and single-page concatenation of multiple Markdown files.

## Features

- Converts Markdown to PDF, HTML, or DOCX (those three formats only) via Pandoc, rendering PDF through an HTML5 intermediate with WeasyPrint so no `pdflatex` install is required.
- Reads files, whole directories (recursively), or standard input (`-`); writes to a directory (`-p`/`--output-path`), to one named file (`-o`/`--output`), or to standard output (`-s`/`--to-stdout`).
- Consistent GitHub-style CSS applied to every HTML/PDF page.
- Automatic PDF page footers ("Page X of Y") and a running header with the document title, with an optional inferred version string.
- Batch conversion of whole directories, finding every `*.md` and `*.markdown` file.
- `--single-page` concatenates multiple Markdown files into one output document.
- Rewrites relative Markdown links (`./bar.md`) to point at the sibling document's converted extension (`./bar.pdf`) in cross-linked document sets, and resolves images against the directory of the file that references them.
- Generates the [table of contents](#the-table-of-contents) itself, as Markdown content, so PDF, HTML, and DOCX output all get the same TOC, placed wherever the author asks for it.
- A [Node.js API](#as-a-nodejs-library) with synchronous and asynchronous calls and TypeScript types.

## Installation

### Install md2x

```bash
npm install -g @liquid-labs/md2x
# or
bun add -g @liquid-labs/md2x
```

That installs the `md2x` command. To use the [Node API](#as-a-nodejs-library) in a project instead, install it as a dependency with `npm install @liquid-labs/md2x` or `bun add @liquid-labs/md2x`. The package requires Node.js 20 or later.

### Install the prerequisites

md2x does not install its external tools (other than WeasyPrint, below). On macOS with [Homebrew](https://brew.sh/):

```bash
brew install pandoc ghostscript pdftk-java gnu-getopt
```

On Debian or Ubuntu:

```bash
sudo apt install pandoc ghostscript pdftk-java python3 python3-venv
```

`pdftk-java` is the maintained [pdftk-java](https://gitlab.com/pdftk-java/pdftk) port of `pdftk`; md2x needs a `pdftk` executable on `PATH`, and the `pdftk-java` package provides one. `python3` ships with macOS developer tools and most Linux distributions. On Debian-family systems the `venv` module is a separate package (`python3-venv`), which the WeasyPrint bootstrap needs.

### Dependencies

| Dependency | When required | Notes |
| --- | --- | --- |
| bash 3.2 or later | Always | The macOS system `/bin/bash` (3.2) works. md2x exits `3` under an older bash or a non-bash shell. |
| [`pandoc`](https://pandoc.org/installing.html) 2.0 or later | Always | md2x checks the version at startup and exits `3` for an older one. Only pandoc 3.10.1 has been exercised by hand; the floor is derived from the Pandoc changelogs. The CI workflow has a legacy-pandoc job intended to run the suite against a 2.x release, but it is unproven until the workflow has run. |
| [Ghostscript](https://www.ghostscript.com/) (`gs`) | Always | Renders the PDF header/footer overlay. |
| `pdftk` ([pdftk-java](https://gitlab.com/pdftk-java/pdftk)) | Always | Merges the overlay onto the PDF. |
| [`python3`](https://www.python.org/) | Always | Runs the table-of-contents preprocessor and hosts WeasyPrint. |
| GNU `getopt` | macOS | The BSD `getopt` that ships with macOS is not enough. Linux's util-linux `getopt` is GNU. |
| [WeasyPrint](https://weasyprint.org/) | PDF output | Managed by md2x; see [first run](#first-run). |
| `git` and [`jq`](https://jqlang.org/) | `--infer-version` only | Checked only when the flag is given. |
| `perl`, `brew` | Not required | |

Standard POSIX utilities (`find`, `sort`, `mktemp`, and the like) are assumed.

On macOS, GNU `getopt` is required, and Homebrew is only the usual way to install it: md2x finds it by probing the Homebrew (Apple Silicon and Intel) and MacPorts locations and then `PATH`, never needs `brew` to run, and never calls `brew` to install anything. Set `MD2X_GETOPT` to the path of a GNU `getopt` to use a specific one. `md2x --help` and `md2x --version` work without it.

### Platform support

| Platform | Status |
| --- | --- |
| macOS | Supported; needs GNU `getopt` (`brew install gnu-getopt`). |
| Linux | Supported. The CI workflow in `.github/workflows/ci.yml` is intended to prove this on every push and pull request, but its first run has not happened yet; treat Linux as expected to work, not as CI-proven. |
| Windows | Unsupported. |
| WSL | Untested. |

### First run

[WeasyPrint](https://weasyprint.org/), the engine Pandoc uses to render PDF output, is not a manual prerequisite. The first time a PDF conversion runs, md2x installs it into an isolated per-user virtual environment at `~/.md2x/venv`, using `python3` and PyPI. That first PDF conversion needs network access and takes noticeably longer (about a minute on a typical connection); md2x prints a notice to stderr while it works:

```text
md2x: installing weasyprint (one-time setup) into '/home/you/.md2x/venv'; this may take a minute...
md2x: weasyprint installed.
```

Later conversions reuse the environment. Delete `~/.md2x/venv` to force a clean reinstall on the next PDF conversion. HTML and DOCX output never trigger the bootstrap.

## Quickstart

Create a small document and convert it:

```bash
printf '# Quickstart\n\nHello from **md2x**.\n' > report.md
md2x report.md
```

```text
Created ./report.pdf
```

`report.pdf` is now in the current directory. Other common conversions:

```bash
# HTML instead of PDF, written to ./out/report.html
md2x --output-format html --output-path out report.md
# Created out/report.html

# One named output file; the .html extension chooses the format
md2x -o site/index.html report.md
# Created site/index.html

# Print only the path, for scripts
md2x --list-files report.md
# ./report.pdf

# Pipe the converted HTML to another program
cat report.md | md2x -F html --to-stdout - | head -n 3
```

## Usage

### As a CLI

```bash
# Convert a single Markdown file to PDF (the default format)
md2x report.md

# Convert every *.md and *.markdown file in a directory to HTML, with an inferred title and version footer
md2x --output-format html --infer-title --infer-version --output-path ./out ./docs

# Concatenate several files into one PDF
md2x --single-page --title "Combined Report" chapter1.md chapter2.md chapter3.md

# Read Markdown from stdin
cat report.md | md2x -
```

md2x accepts one or more file paths, one or more directory paths (searched recursively), or a single `-` argument to read Markdown from stdin; `-` cannot be mixed with other inputs, and empty stdin is a usage error.

Input discovery rules:

- Directory searches find `*.md` and `*.markdown` files, matched case-insensitively.
- Symlinked source files found in a search are followed, so their targets are read.
- Search roots are taken literally, whatever their names (a directory called `-d` or `!` works).
- File or directory names containing control characters are rejected.
- A directory search that finds nothing is an error, unless other inputs did produce files, in which case it is a warning.
- Duplicate inputs are converted once.

Output rules:

- Without `-o` or `--to-stdout`, each output is named after its input (or after `--title`) with the output format's extension, and written under `--output-path` (default `.`).
- `-o <file>` writes the single output to that file, creating its directory. It works only when exactly one output results (one input file, stdin, or `--single-page`) and conflicts with `-p`. A path ending in `/` is rejected. The extension (`.pdf`, `.html`, `.docx`) decides the format unless `-F` is given; an `-F` that contradicts the extension is an error, and an unrecognized extension writes the default format (PDF) to the file exactly as named.
- `--to-stdout` (`-s`, same as `-o -`) writes the single output to stdout and nothing to disk. It needs exactly one output and conflicts with `--list-files` and `-o <file>`.
- Two inputs that would write the same output file, or an output that would overwrite one of its own inputs, are refused before any conversion starts.
- Replacing an existing output file creates a new file, so its mode comes from your `umask`; the old file's mode and ownership are not kept. Write outputs only to directories untrusted users cannot modify (see [SECURITY.md](./SECURITY.md)).

### As a Node.js library

The package ships ESM, CommonJS, and TypeScript types, and requires Node.js 20 or later. Like the CLI, it needs the [external tools](#dependencies) installed.

```javascript
import { md2x, md2xAsync } from '@liquid-labs/md2x'

// Synchronous: returns the generated file paths
const files = md2x({ sources : ['report.md'], format : 'html', outputPath : 'out' })

// Asynchronous: same options, returns a Promise
const more = await md2xAsync({ markdown : '# Hello\n', format : 'html', outputPath : 'out' })
console.log(files, more) // [ 'out/report.html' ] [ 'out/output.html' ]
```

CommonJS works the same way:

```javascript
const { md2x, md2xAsync } = require('@liquid-labs/md2x')
```

And in TypeScript, the options and error types are exported:

```typescript
import { md2x, type Md2xError, type Md2xOptions } from '@liquid-labs/md2x'

const options: Md2xOptions = { sources : ['report.md'], format : 'html' }
try {
  md2x(options)
}
catch (error) {
  console.error((error as Md2xError).exitCode)
}
```

Exactly one input option is required:

- `sources`: a non-empty array of file and directory paths. It cannot contain `-`; pass the content as `markdown` instead. Sources are passed to the CLI after `--`, so a name such as `-weird.md` is a file, not an option.
- `markdown`: a string of Markdown, fed to the CLI on stdin. With no `title`, the output is named `output`.

All other options are optional:

| Option | Type | Description |
| --- | --- | --- |
| `format` | `'pdf'` \| `'html'` \| `'docx'` | Output format. Default `'pdf'`. |
| `outputPath` | `string` | Output directory (`--output-path`). Conflicts with `output`. |
| `output` | `string` | Output file (`-o`). Conflicts with `outputPath`; `'-'` is rejected, because the wrapper returns paths, not bytes. |
| `title` | `string` | Document title (`--title`). No title is injected when omitted, so output names follow the inputs. |
| `flattenDirs` | `boolean` | `--flatten-dirs`. |
| `inferTitle` | `boolean` | `--infer-title`. |
| `inferVersion` | `boolean` | `--infer-version`; needs `git` and `jq`. |
| `toc` / `noToc` | `boolean` | `--toc` / `--no-toc`; mutually exclusive. |
| `singlePage` | `boolean` | `--single-page`. |
| `quiet` | `boolean` | Do not forward the CLI's stderr (warnings, the first-run notice) to `console.error`. |

The call returns the generated file paths as `string[]`. Unknown option keys, wrong types, `markdown` together with `sources`, and an empty `sources` array throw a `TypeError` before anything runs (`md2xAsync()` rejects instead). When the CLI fails, the thrown `Error` carries `exitCode` (the CLI's [exit code](#exit-codes)) and `stderr`, and its message includes both:

```javascript
try {
  md2x({ sources : ['missing.md'], quiet : true })
}
catch (error) {
  console.log(error.exitCode, error.stderr)
  // 2 md2x: 'missing.md' is neither a file nor a directory. Bailing out. ...
}
```

The wrapper does not expose `--list-files`, `--to-stdout`, or `--keep-intermediate` (it always lists files). A returned path that contains a newline is mis-split into several entries.

## CLI reference

| Flag | Description |
| --- | --- |
| `-D`, `--flatten-dirs` | Write all output files directly into `--output-path` instead of mirroring the input directory structure. Without this flag, each output file is written under `--output-path` at the path its input occupies *relative to the directory argument it was found under*; a file named directly on the command line goes straight into `--output-path`. |
| `--infer-title` | Embed the title (from `--title`, or otherwise the filename) as document metadata via Pandoc (e.g. the HTML `<title>` element). |
| `--infer-version` | Add an inferred version string to the PDF footer: the `package.json` version of the git repository containing the first input (the current directory for stdin), or `working` when its tree is dirty. Needs `git` and `jq`, only for this flag. See [version inference](#version-inference). |
| `--keep-intermediate` | Keep the per-run work directory (under `TMPDIR`) holding the intermediate build artifacts (CSS, Pandoc log, PDF overlay, and so on) instead of deleting it after conversion. Its path is printed once to stderr (not suppressed by `--quiet`). |
| `-o`, `--output <file>` | Write the single output to `<file>`, creating its directory as needed; `-` means `--to-stdout`. Valid only when exactly one output results (one input file, stdin, or `--single-page`); conflicts with `-p`. The format is inferred from a `.pdf`, `.html`, or `.docx` extension when `-F` is absent. |
| `-p`, `--output-path <path>` | Directory to write output files into. Default: `.`. Conflicts with `-o`. |
| `-F`, `--output-format <format>` | Output format: `pdf` (default), `html`, or `docx` (case-insensitive). |
| `-t`, `--title <title>` | Document title; used for the output filename (unless `-o` is given) and the PDF header text. Only applies when exactly one file is converted outside `--single-page`; combining with multiple source files is a usage error. A title that cannot be a file name (empty, `.`, `..`, or containing `/` or control characters) is rejected unless `-o` is given. |
| `--single-page` | Concatenate all input Markdown files into a single document before conversion. |
| `--quiet` | Suppress the "Created `<file>`" status message. |
| `--list-files` | Print only the generated file path(s), instead of "Created `<file>`". |
| `-s`, `--to-stdout` | Write the single converted output to stdout and nothing to disk (implies `--quiet`). Needs exactly one output; conflicts with `--list-files` and `-o <file>`. |
| `--toc` | Force a [table of contents](#the-table-of-contents) on, regardless of document size. |
| `--no-toc` | Force the [table of contents](#the-table-of-contents) off, overriding both the default size heuristic and a `<!-- md2x:toc -->` marker in the source. Passing `--toc` and `--no-toc` together is a usage error. |
| `-h`, `--help` | Print the help text and exit; works without the dependencies installed. |
| `--version` | Print the md2x version and exit. |

Notes on the flags:

- The only short flags are `-D -F -h -o -p -s -t`. `-s` is `--to-stdout`. The auto-generated shorts of earlier alpha releases (`-q`, `-l`, `-n`, `-i`) are not accepted and are a usage error; use `--quiet`, `--list-files`, `--no-toc`, and `--infer-title`.
- `-o`, `--to-stdout`, and `--output-path` conflict as described above: `-o <file>` with `-p` is an error, `-o <file>` with `--to-stdout` is an error, and `--to-stdout` with `--list-files` is an error. `-o -` is the same as `--to-stdout`.
- Option parsing is done by GNU `getopt`, so long options may be abbreviated to any unambiguous prefix (`--single` works for `--single-page`; `--no` currently resolves to `--no-toc`, and abbreviations may become ambiguous as options are added, so prefer full names in scripts), a value may be attached with `=` (`--title=Report`), and a short option's value may be attached directly (`-pout`). Note that `-p=out` means the value `=out`, not `out`.

### Exit codes

| Code | Meaning | Examples |
| --- | --- | --- |
| `0` | Success | Image warnings alone do not change the exit code. |
| `1` | Runtime or conversion failure | A `pandoc`, `gs`, or `pdftk` failure; an unreadable search root; input that is not valid UTF-8 or contains NUL bytes. |
| `2` | Usage error | An unknown option or a missing option value; `--toc` with `--no-toc`; an unsupported format; no arguments; empty stdin; a directory with no Markdown files; a title unusable as a file name; two inputs writing the same output; `-o` or `--to-stdout` with more than one output; `-` mixed with other inputs. |
| `3` | Missing or unusable dependency | A required binary absent; GNU `getopt` not found; bash too old or not bash; pandoc below 2.0; a WeasyPrint bootstrap failure or lock timeout. |

Every error is one line on stderr prefixed `md2x: ` (warnings are prefixed `md2x: warning: `), colored only when stderr is a terminal and `NO_COLOR` is unset.

### Troubleshooting

| Message (abridged) | Exit | Cause and fix |
| --- | --- | --- |
| `Required executable 'gs' not found for 'md2x'. Add to 'PATH' or install.` | 3 | One of `gs`, `pandoc`, `pdftk`, or `python3` is missing from `PATH`. Install it as described in [Installation](#install-the-prerequisites). |
| `pandoc 1.19.2 is too old; md2x requires pandoc >= 2.0` | 3 | Upgrade pandoc. |
| `GNU getopt is required but was not found ...` | 3 | On macOS, `brew install gnu-getopt` (or `port install getopt`), or set `MD2X_GETOPT` to a GNU `getopt`. On Linux, install util-linux. |
| `MD2X_GETOPT is set to '...', which is not GNU getopt` | 3 | Unset `MD2X_GETOPT` or point it at a GNU `getopt`. |
| `requires bash 3.2 or later` | 3 | Run md2x with bash 3.2 or newer, not `sh`. |
| `failed to install weasyprint (step: ...)` | 3 | No network, a proxy blocking PyPI, or missing build tooling. Run the retry command the message prints. |
| `timed out ... waiting for another 'md2x' process's weasyprint install` | 3 | Another md2x is still bootstrapping, or a killed one left a stale lock. The message prints the command that clears it. |
| `Required executable 'git' not found; it is needed only for '--infer-version'` | 3 | Install `git` and `jq`, or drop `--infer-version`. |
| `unrecognized option '-q'` | 2 | Not an md2x option; see the [short flags](#cli-reference) note. |
| `'x.md' is neither a file nor a directory.` | 2 | Check the path. |
| `no Markdown files found in 'dir'` | 2 | The directory holds no `*.md` or `*.markdown` file. |
| `Cannot specify both '--toc' and '--no-toc'.` | 2 | Pass only one. |
| `'-o'/'--output' cannot be combined with '-p'/'--output-path'.` | 2 | Use one or the other. |
| `no input on stdin.` | 2 | Standard input was empty. |
| `unsupported output format 'txt' (expected pdf\|html\|docx)` | 2 | Use `pdf`, `html`, or `docx`. |
| `would both be written to '...'` | 2 | Two inputs map to one output name (the check ignores case); rename one, drop `--flatten-dirs`, or convert them separately. |
| `could not find image '...' (referenced from ...)` | 0 (warning) | The image file does not exist; the document is still produced. |
| `md2x: warning: --infer-version: ... no version in the footer.` | 0 (warning) | The input is not in a git work tree, has no `package.json`, or the repository was refused; see [version inference](#version-inference). |

## Behavior notes

### Links and images

- **Links.** A relative link to a `*.md` or `*.markdown` file is rewritten to the output format's extension, keeping any fragment (`./bar.md#intro` becomes `./bar.pdf#intro`). Absolute paths, URL-scheme links (`https:`, `mailto:`), and bare `#fragment` links are untouched, as are links inside code spans and fenced code. The rewrite applies to the target's extension in the document being converted, not to whatever name you gave the target's own output.
- **Images.** A relative image resolves against the directory of the source file that contains it (the current directory for stdin), not against the directory you run md2x from. For PDF and DOCX the image is embedded. HTML output is not self-contained: it keeps a path from the output file to the image, so keep the images next to the HTML. A relative image whose file does not exist produces a `could not find image` warning on stderr and exit code `0`.
- **`--single-page`.** Links and images are resolved per source file using markers md2x inserts between the files. Known limitation: an unterminated code fence or raw HTML block in one source swallows the next source's marker, so that source's images then resolve against the wrong directory.
- **Known limitations.** With `--flatten-dirs`, relative links between files in different directories may not resolve. Under `--single-page`, links between the combined files still point at the sibling output files rather than becoming internal anchors. A file converted with `--title` or `-o` is not renamed in other documents' links.

### Security

md2x is not a sandbox, and converting untrusted Markdown is not safe by default. See [SECURITY.md](./SECURITY.md) for the full notes; the essentials:

- Image references, including absolute and parent-relative (`..`) paths, are read from the local filesystem and embedded in PDF and DOCX output, and the `could not find image` warning reveals whether a file exists. Do not convert untrusted Markdown on a host that holds sensitive files.
- WeasyPrint fetches remote resources referenced from the document during PDF conversion (image URLs, CSS `url()` and `@import`, and `file://` URLs), with no allowlist, which makes it a server-side request forgery (SSRF) vector. Do not convert untrusted Markdown with remote references on a sensitive network, and restrict network egress around any application that does.

### Version inference

`--infer-version` adds `Version: <version>` to the PDF footer: the `version` in the `package.json` at the top of the git repository containing the **first** input (the current directory for stdin), or `Version: working` when that repository's work tree has uncommitted changes. `git` and `jq` are needed only for this flag; global git configuration is ignored.

Because the repository's own configuration is untrusted, md2x runs `git` only in a repository whose local config holds nothing but a short allowlist of harmless keys. A repository whose config has any other key (filters, includes, non-URL remote settings, and so on), real partial clones, sparse checkouts, and submodule inputs all make md2x print one warning and omit the version from the footer. A missing git work tree or `package.json` does the same, as does a repository whose git directory, found from the input, differs from that of its work-tree top (for example a `core.worktree` redirect to another repository). See the [specification](./docs/md2x-spec.md#constraints-and-assumptions) for the exact allowlist.

### The PDF header/footer overlay

Every PDF md2x generates gets a footer with page numbers ("Page X of Y"), and, on every page after the first, a header with the document title (from `--title`, or inferred from the filename). With `--infer-version`, the footer also shows the version string described above. This overlay is produced by rendering a standalone PostScript document with Ghostscript (`gs`) and merging it onto the Pandoc-generated PDF with `pdftk ... multistamp`.

### The table of contents

md2x can generate a table of contents as ordinary Markdown content, rather than relying on Pandoc's own `--toc` machinery. Because the TOC is real document content instead of a renderer-specific navigation block, it renders identically across PDF, HTML, and DOCX output, including as clickable bookmarks in DOCX.

To control where the TOC lands, place a `<!-- md2x:toc -->` marker on its own line anywhere in the source; md2x replaces that line with the generated list. The marker is an ordinary HTML comment, so it's invisible when the document is viewed on GitHub, in an editor, or in any other Markdown renderer. Without a marker, the TOC is inserted immediately after the document's title heading, or at the very top of the document if it has no title heading.

With neither `--toc` nor `--no-toc` given, md2x adds a TOC only to documents estimated at more than about two rendered pages that also have four or more top-level sections; shorter or simpler documents get none by default. `--toc` and `--no-toc` override that default in either direction (and passing both together is a usage error).

Two limitations carry over from the underlying heading-identifier algorithm: a heading containing an emoji character gets a TOC entry whose link may not resolve, and headings nested inside blockquotes or list items are not included in the TOC at all.

## Known limitations

- The PDF header and footer are fixed: their content, position, and font are not configurable, and there is no first-page header.
- The overlay uses a built-in PostScript font with limited non-Latin glyph coverage, so titles in non-Latin scripts may render incompletely in the PDF header (they do not break the conversion).
- There is no parallel conversion (`--jobs`) or progress output; files are converted one at a time.
- The Node wrapper mis-splits a returned path that contains a newline.
- The link and image caveats above: `--flatten-dirs`, `--single-page` links, renamed outputs, and the marker limitation under `--single-page`.
- Windows is unsupported and WSL is untested.

## Additional documentation

- Working on this project (build, test, conventions): [AGENTS.md](./AGENTS.md) and [CONTRIBUTING.md](./CONTRIBUTING.md)
- Full specification: [docs/md2x-spec.md](./docs/md2x-spec.md)
- Architecture and conversion pipeline: [docs/architecture.md](./docs/architecture.md)
- Project structure and file layout: [docs/project-structure.md](./docs/project-structure.md)
- Security policy and trust notes: [SECURITY.md](./SECURITY.md)
- Release history: [CHANGELOG.md](./CHANGELOG.md) and [GitHub releases](https://github.com/liquid-labs/md2x/releases)
- Cutting a release: [RELEASING.md](./RELEASING.md)

## License

md2x is licensed under the Apache License 2.0; see [LICENSE.txt](./LICENSE.txt).

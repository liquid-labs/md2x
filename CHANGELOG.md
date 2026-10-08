# Changelog

All notable changes to md2x are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and md2x adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

Targets `1.0.0`. Changes are relative to `1.0.0-alpha.11`.

### Breaking changes

- **Exit codes.** A missing or unusable dependency (for example `pandoc` or GNU `getopt`) now exits `3` instead of `2`. The contract is now: `0` success, `1` runtime or conversion failure, `2` usage error, `3` missing or unusable dependency. Scripts that treated `2` as "dependency missing" must check for `3`.
- **`-s` is `--to-stdout`.** In `1.0.0-alpha.11` the `-s` short flag was silently bound to `--single-page`, contrary to the documentation. It now means `--to-stdout`, as documented. Use the long `--single-page` for concatenation.
- **Short flags are exactly `-D -F -h -o -p -s -t`.** The undocumented auto-generated shorts `-q`, `-l`, `-n`, and `-i` are removed and are now usage errors (exit `2`). Use `--quiet`, `--list-files`, `--no-toc`, and `--infer-title`.
- **`--version` is long-only.** There is no `-v` short flag.
- **`--to-stdout` writes nothing to disk.** It needs exactly one output and conflicts with `--list-files` and with `-o <file>`.
- **Node wrapper.**
  - The default title is no longer `Report`; no title is injected unless one is given, so the output name follows the input.
  - Unknown option keys, `sources: ['-']`, an empty `sources` array, and `markdown` combined with `sources` now throw a `TypeError` before anything is spawned.
  - The `shelljs` dependency is removed; the wrapper uses `node:child_process`.
  - Errors carry `exitCode` and `stderr` properties.
  - The package now exposes an `exports` map with ESM (`dist/md2x.mjs`), CJS (`dist/md2x.cjs`), and TypeScript types (`dist/index.d.ts`).
- **Links and images resolve per source file.** Relative links and images are now resolved against the directory of the source file that contains them, by a Pandoc Lua filter. The previous `perl`/`eval`-based rewrite is gone, and `perl` is no longer needed.
- **HTML output inlines its CSS.** HTML output is now styled by an inlined stylesheet rather than shipping unstyled.
- **Empty stdin is a usage error.** `md2x -` with no input exits `2` with a message instead of exiting silently.
- **Output collisions are errors.** Two inputs that would write the same output file (compared case-insensitively), and an output target that is the same file as an input, are refused instead of one result silently overwriting another or the source.
- **`--infer-version` trust model.** Version inference runs `git` only in a repository whose own config holds just an allowlist of harmless keys. A repository with any other key (for example one that can run commands, such as `remote.<name>.uploadpack` or `filter.*`) makes md2x warn on stderr, naming the key, and omit the version from the footer.
- **Dependencies.** GNU `getopt` is required (discovered without Homebrew; `MD2X_GETOPT` can point at it), `pandoc` 2.0 or later is required, and `jq` and `git` are needed only for `--infer-version`.

### Added

- `-o, --output <file|->` writes the single output to a named file, creating its directory, and infers the format from a `.pdf`, `.html`, or `.docx` extension.
- `--version` prints the md2x version.
- `md2xAsync` in the Node wrapper, plus `output` and `quiet` options.
- TypeScript type declarations and a dual ESM/CJS build, verified from a packed tarball by `make test-pack`.
- `*.markdown` files, as well as `*.md`, are discovered in directory searches, matched case-insensitively.
- A project-owned option parser: long options may be abbreviated to any unambiguous prefix, and values may be attached with `=`.
- Bash 3.2 support (the macOS system shell), with an interpreter guard and a `MD2X_TEST_BASH` override for the test harness.
- A GitHub Actions workflow that runs the suite under macOS, Linux, bash 3.2, and a legacy Pandoc.
- Bats coverage for the exit-code contract, options, title sinks, stdin handling, output collisions, links and images, and the Node and packaging surfaces.

### Changed

- Every intermediate artifact lives in one per-run work directory under `TMPDIR`, deleted when the run ends unless `--keep-intermediate` is given. Nothing but the requested outputs lands in the working or output directory.
- Stdin is captured byte-exact.
- Output is delivered by writing a temporary file next to the target and renaming it into place.
- Directory search roots are taken literally, whatever their names; a symlinked `*.md` file found in a searched directory is followed.
- `--infer-version` is evaluated lazily, so `git` and `jq` are not required otherwise, and its `git` calls are hardened against repository-supplied configuration.
- Error messages go through one helper and follow the exit-code contract on every path.
- `github.css` no longer carries rules WeasyPrint does not support.

### Fixed

- Single-page conversion no longer deletes the source Markdown files.
- Stdin input is no longer corrupted, and empty stdin no longer exits silently.
- HTML output is no longer unstyled.
- Running under bash 3.2 no longer exits `0` silently without converting.
- `-s` now means `--to-stdout` as documented, and the hidden auto-generated short flags are removed.
- `--title` is sanitized in every sink: titles with non-ASCII characters or PostScript-special characters no longer break the PDF header overlay, and filenames and document metadata are made safe.
- A spurious Pandoc `user-select` warning is filtered from PDF stderr.

### Removed

- The `shelljs` dependency of the Node wrapper.
- The `perl` requirement and the `eval`-based link rewrite.
- The `-q`, `-l`, `-n`, and `-i` short flags.

# Security policy

## Purpose and scope

This document says which md2x versions receive security fixes, how to report a vulnerability privately, and what md2x does and does not protect against.

## Supported versions

md2x is pre-1.0 until `1.0.0` is released. Security fixes are made against the latest published release only.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's [private security advisory flow](https://github.com/liquid-labs/md2x/security/advisories/new) for `liquid-labs/md2x`. Alternatively, email the maintainer, Zane Rockenbaugh, at `zane@liquid-labs.com`. Please do not open a public issue for a suspected vulnerability.

Include the md2x version, your platform, the input and command line that trigger the problem, and the impact you observed.

## Expected response

This is a volunteer-maintained project, so there is no formal service level. Expect an acknowledgement of your report within a few days, and a status update once the report has been assessed. Fixes ship in a new release, and reporters are credited unless they ask otherwise.

## Scope and trust notes

md2x runs local tools (`pandoc`, `gs`, `pdftk`, `python3`, and for PDF output a WeasyPrint installed under `~/.md2x/venv`) on the machine where it runs. It is not a sandbox, and **converting untrusted Markdown is not safe by default**.

- **Local files are read and embedded.** Image references in Markdown, including absolute and parent-relative (`..`) paths, are read from the local filesystem and embedded in the output. The `could not find image` warning reveals whether a given file exists. Do not convert untrusted Markdown on a host that holds sensitive files.
- **Remote resources and SSRF.** For PDF output, WeasyPrint fetches external resources referenced from the document, such as image URLs, CSS `url()` and `@import`, including `file://` URLs, with no built-in allowlist. An application that converts untrusted Markdown, including through the Node wrapper, should restrict network egress around the process or supply a WeasyPrint URL fetcher override.
- **Symlinks.** A symlinked `*.md` source found while searching a directory is followed, and its target is read.
- **`--infer-version` and repository config.** Version inference runs `git` only in a repository whose own config holds nothing but an allowlist of harmless keys. A repository with command-bearing config, such as `remote.<name>.uploadpack` or `filter.*`, makes md2x warn and omit the version without running `git status`. Still, run `--infer-version` only on repositories you trust.
- **Output location.** Write outputs only to directories that untrusted parties cannot modify; a parent directory swapped for a symlink during a run can redirect delivery.

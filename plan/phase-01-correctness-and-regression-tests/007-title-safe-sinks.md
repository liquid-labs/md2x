# Title-Safe Sinks

## Purpose and scope

Fix S7, user must-fix 6: `--title` is used unsanitized in the CLI's filename, YAML metadata, and PostScript sinks. Also fix the robustness part of N8: non-ASCII and PostScript-special titles must not crash Ghostscript or corrupt the PDF header and footer overlay. No standard skill covers this; follow the role doc and the requirements below.

In scope:

- `src/cli/md2x.sh`
- `src/cli/lib/generate-page.sh`
- a small helper lib file, if one is useful
- the pandoc stub's argument parsing
- bats and gated real-toolchain cases

Out of scope:

- The Node staging path, the fourth sink. Task 008 fixes it in parallel.
- `-o/--output`, which Phase 2 adds. After it lands, a display-only title may contain any printable text.
- N8's deferred features: a configurable header and footer, a first-page header, and font choice. These belong to followup `1wy6`.
- Version inference changes such as `jq -r` and laziness (Phase 2). Only escaping the version string for PostScript is in scope here.

## Requirements

- `role_doc: plugins/flow/roles/developer-bash.md`
- **Filename sink.** In Phase 1, an explicit `--title` always determines the output filename in the modes that honor it: a single file, `--single-page`, and stdin.
  - Validate an explicitly given title (`TITLE_SET`) before any conversion work, and before `ensure-weasyprint`.
  - Reject with a usage error (exit 2, through the task 001 helper) a title that is empty, `.`, or `..`, or that contains `/` or a control character (0x01 to 0x1F, or 0x7F). NUL cannot occur in an argv string, so it needs no check, but note that in a comment.
  - The message names the problem, for example `--title '<shown safely>' cannot be used as a file name`. Do not mention `-o` yet: it does not exist until Phase 2, and the Phase 2 `-o` task will extend the message.
  - Printable non-ASCII titles, such as `Ünïcødé 日本`, and titles containing `\`, `(`, `)`, `'`, `"`, `:`, `*`, or spaces are accepted. They must work under both `LC_ALL=C` and a UTF-8 locale. Bracket-class behavior differs between them, so test both.
- **Metadata sink.** Remove the YAML string building and the `--metadata-file <(…)` argument from `generate-page()`.
  - With `--infer-title`, pass `-M "title=${TITLE}"` as one argv element. Without `--infer-title`, pass no title metadata, as today.
  - A spike with pandoc 3.10.1 confirmed `-M` keeps the value as a literal string. Do not use a JSON metadata file: it parses the value as Markdown.
  - Teach `src/cli/test/stubs/pandoc` that `-M`/`--metadata` take a value. Today the catch-all `-*` arm would misread `title=…` as the input file.
  - Drop the stub's metadata-file capture, or leave it harmless, and update its header comment. Update the harness-smoke and `title-precedence.bats` cases that read the `metadata` capture so they assert on the `-M` argument in the stub log instead.
- **PostScript sink.** Before interpolating the title and the version string into the Ghostscript program in `generate-page()`:
  - escape `\` as `\\`, `(` as `\(`, and `)` as `\)`
  - strip control characters (0x00 to 0x1F, and 0x7F)
  - pass non-ASCII bytes through unchanged

  Emitting the strings as PostScript hex strings (`<…> show`) instead of escaped literals is an acceptable alternative.

  Put the escaping in a small standalone function, for example `md2x-ps-string` in its own `src/cli/lib/` file. A bats case can then `source` that lib file directly and unit-test it. In Phase 1, a control-character title is rejected by the filename sink before it reaches the PostScript sink, so the unit test is the only way to cover stripping.
- **Regression tests.** Each must fail on the pre-change code where the old behavior was broken.
  - Filename: `-t ''`, `-t .`, `-t ..`, `-t a/b`, and `-t "$(printf 'a\tb')"` each exit 2 with the usage hint and create no output and no stray file. Run them with `--single-page`, with stdin, and with a single file.
  - Filename: `-t 'O(x)\y'` and `-t 'Ünïcødé 日本'` create `O(x)\y.html` and `Ünïcødé 日本.html` respectively.
  - Metadata: `--infer-title -t "O'Brien: *x* (a)b \\ \"q\""` passes exactly one `-M` argument whose value is `title=` followed by the literal title. No `--metadata-file` argument is passed.
  - PostScript, unit: the escape function turns `a\b(c)d`, plus a control character, plus `é` into the expected escaped output, with the control character gone and the bytes of `é` intact.
  - PostScript, stub: the `gs -c` argument recorded for `-t 'a)b'` contains `a\)b`.
  - Real toolchain, gated like the existing e2e cases: PDF conversions with `-t 'a)b'`, `-t 'x\y(z'`, and `-t 'Ünïcødé 日本'` each exit 0, and each produces a PDF that `pdftk … dump_data` reads.
    - Before the fix, `a)b` crashes `gs` (`Unrecoverable error`, rc 1).
    - If the non-ASCII case already passed before the fix, say so in the report. It then serves as a guard, not a regression test.
- Keep the code bash 3.2-compatible. Run the suite under `MD2X_TEST_BASH=/bin/bash`.

## Validation

- `make qa` passes, and the bats suite also passes under `MD2X_TEST_BASH=/bin/bash`.
- Real-toolchain e2e passes locally, including the new title cases.
- `grep -n "metadata-file\|SETTINGS" src/cli/lib/generate-page.sh` returns nothing.
- `grep -n '( "\${TITLE}" )\|Version: \${VERSION}' src/cli/lib/generate-page.sh` returns nothing, because both now go through the escape function.
- The new regression cases fail against the pre-change build where the old behavior was broken. Confirm this and report it.
- The report notes that Helvetica glyph coverage for non-Latin titles is a known limitation. Phase 3 documents it.

## Assumptions

- Tasks 001 to 006 are complete. The overlay, the combined file, and the single-page concatenation already use fixed, title-independent names in the work directory (task 004), so the output file is the only filename sink left.
- After this task, a Node caller passing `title: '../esc'` gets exit 2 from the CLI. That is intended. Task 008 separately stops the Node wrapper from building a staging path from the title.

## References

- [Design decisions: title handling](../notes/design-decisions.md#title-handling): the per-sink rules and the `-M` spike result.
- [N4/N8 scope answer](../notes/n4-n8-scope-answer.md): the robustness part stays in scope, and the features are deferred.
- `.flow/audit-interface.md` S7 and N8, under the project root: the reproductions.
- `src/cli/test/stubs/gs`: it records the `-c` PostScript string in the stub log.

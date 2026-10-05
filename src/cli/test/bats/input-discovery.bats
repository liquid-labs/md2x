#!/usr/bin/env bats
#
# Input discovery and argument validation: no-argument and empty-directory usage errors,
# case-insensitive '*.md'/'*.markdown' discovery, deduplication, '-' mixing, case-
# insensitive '--output-format', input encoding checks, and control characters in file
# names found by a search. Every case runs the built CLI against the stub toolchain.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

@test "no arguments exits 2 with a usage hint on stderr" {
  md2x_run

  assert_failure 2
  assert_stderr_contains 'no input given'
  assert_stderr_contains 'Usage: md2x'
  refute_stub_called pandoc
}

@test "an empty directory alone exits 2 naming the directory" {
  mkdir -p empty

  md2x_run empty

  assert_failure 2
  assert_stderr_contains "no Markdown files found in 'empty'"
  refute_stub_called pandoc
}

@test "an empty directory next to a non-empty one warns and succeeds" {
  mkdir -p empty
  md2x_write_doc 'full/a.md'

  md2x_run --output-format html --output-path out empty full

  assert_success
  assert_stderr_contains "warning: no Markdown files found in 'empty'"
  assert_file_exists 'out/a.html'
  assert_stub_call_count pandoc 1
}

@test "an empty directory next to a directly named file warns and succeeds" {
  mkdir -p empty
  md2x_write_doc 'a.md'

  md2x_run --output-format html --output-path out a.md empty

  assert_success
  assert_stderr_contains "warning: no Markdown files found in 'empty'"
  assert_file_exists 'out/a.html'
}

@test "X.MD, y.markdown and z.Markdown are discovered with the right output names" {
  md2x_write_doc 'docs/X.MD'
  md2x_write_doc 'docs/y.markdown'
  md2x_write_doc 'docs/sub/z.Markdown'
  md2x_write_doc 'docs/skip.txt'

  md2x_run --output-format html --output-path out docs

  assert_success
  assert_file_exists 'out/X.html'
  assert_file_exists 'out/y.html'
  assert_file_exists 'out/sub/z.html'
  assert_stub_call_count pandoc 3
}

@test "a directly named Notes.MARKDOWN strips its extension case-insensitively" {
  md2x_write_doc 'Notes.MARKDOWN'

  md2x_run --output-format html --output-path out Notes.MARKDOWN

  assert_success
  assert_file_exists 'out/Notes.html'
}

@test "a file named twice converts once" {
  md2x_write_doc 'a.md'

  md2x_run --output-format html --output-path out a.md a.md

  assert_success
  assert_stub_call_count pandoc 1
}

@test "a file named as a.md and ./a.md converts once" {
  md2x_write_doc 'a.md'

  md2x_run --output-format html --output-path out ./a.md a.md

  assert_success
  assert_stub_call_count pandoc 1
}

@test "a directory named twice converts each file once" {
  md2x_write_doc 'd1/a.md'
  md2x_write_doc 'd1/b.md'

  md2x_run --output-format html --output-path out d1 d1

  assert_success
  assert_stub_call_count pandoc 2
  refute_stderr_contains 'warning'
}

@test "a directory named as d1 and ./d1/ converts each file once" {
  md2x_write_doc 'd1/a.md'

  md2x_run --output-format html --output-path out d1 ./d1/

  assert_success
  assert_stub_call_count pandoc 1
}

@test "a file named directly and found under a directory argument converts once, as a direct file" {
  md2x_write_doc 'd1/sub/a.md'

  md2x_run --output-format html --output-path out d1/sub/a.md d1

  assert_success
  assert_stub_call_count pandoc 1
  # The direct occurrence wins, so the output is not mirrored under 'sub/'.
  assert_file_exists 'out/a.html'
  assert_file_not_exists 'out/sub/a.html'
}

@test "'-' combined with a file is a usage error" {
  md2x_write_doc 'a.md'

  md2x_run - a.md <<< '# x'

  assert_failure 2
  assert_stderr_contains "'-' (stdin) cannot be combined with other inputs"
  refute_stub_called pandoc
}

@test "'- -' is a usage error" {
  md2x_run - - <<< '# x'

  assert_failure 2
  assert_stderr_contains "'-' (stdin) cannot be combined with other inputs"
}

@test "-F HTML is accepted case-insensitively and writes .html" {
  md2x_write_doc 'a.md'

  md2x_run -F HTML --output-path out a.md

  assert_success
  assert_file_exists 'out/a.html'
}

@test "an unsupported --output-format exits 2 and lists the valid formats" {
  md2x_write_doc 'a.md'

  md2x_run -F txt a.md

  assert_failure 2
  assert_stderr_contains "unsupported output format 'txt' (expected pdf|html|docx)"
}

@test "a file with a NUL byte exits 1 naming the file" {
  printf '# Title\n\nbad\0byte\n' > nul.md

  md2x_run --output-format html --output-path out nul.md

  assert_failure 1
  assert_stderr_contains "'nul.md' is not valid UTF-8 text"
  refute_stderr_contains 'Traceback'
  assert_file_not_exists 'out/nul.html'
}

@test "a file that is not valid UTF-8 exits 1 naming the file" {
  printf '# Title\n\nbad \377\376 bytes\n' > bad.md

  md2x_run --output-format html --output-path out bad.md

  assert_failure 1
  assert_stderr_contains "'bad.md' is not valid UTF-8 text"
  refute_stderr_contains 'Traceback'
}

@test "invalid UTF-8 on stdin exits 1 naming stdin" {
  printf '# Title\n\nbad \377 bytes\n' > bad-input

  md2x_run - < bad-input

  assert_failure 1
  assert_stderr_contains "'stdin' is not valid UTF-8 text"
}

@test "an invalid UTF-8 source in --single-page mode exits 1 naming that file" {
  md2x_write_doc 'good.md'
  printf '# Title\n\nbad \377 bytes\n' > bad.md

  md2x_run --single-page --output-format html good.md bad.md

  assert_failure 1
  assert_stderr_contains "'bad.md' is not valid UTF-8 text"
}

@test "a file starting with a UTF-8 BOM converts" {
  printf '\357\273\277# Title\n\nBody\n' > bom.md

  md2x_run --output-format html --output-path out bom.md

  assert_success
  assert_file_exists 'out/bom.html'
}

@test "a file named -weird.md converts" {
  md2x_write_doc './-weird.md'

  md2x_run --output-format html --output-path out -- -weird.md

  assert_success
  assert_file_exists 'out/-weird.html'
}

@test "the --title gate counts .markdown and uppercase files" {
  md2x_write_doc 'd/a.markdown'
  md2x_write_doc 'd/B.MD'

  md2x_run --title Foo --output-format html --output-path out d

  assert_failure 2
  assert_stderr_contains '2 files would be converted'
  refute_stub_called pandoc
}

@test "the --title gate does not double-count a file named twice" {
  md2x_write_doc 'a.md'

  md2x_run --title Foo --output-format html --output-path out a.md ./a.md

  assert_success
  assert_file_exists 'out/Foo.html'
}

@test "a discovered file name with a control character is rejected and shown control-free" {
  md2x_write_doc 'd/ok.md'
  printf '# x\n' > "$(printf 'd/bad\033[31m.md')"

  md2x_run --output-format html --output-path out d

  assert_failure 2
  assert_stderr_contains 'contains control characters'
  assert_stderr_contains 'bad?[31m.md'
  [[ "${stderr}" != *$'\033'* ]] || md2x_fail 'stderr carries a raw ESC byte'
  refute_stub_called pandoc
}

@test "a discovered file name with an embedded newline is rejected" {
  mkdir -p d
  printf '# x\n' > "$(printf 'd/a\nb.md')"

  md2x_run --output-format html --output-path out d

  assert_failure 2
  assert_stderr_contains 'contains control characters'
}

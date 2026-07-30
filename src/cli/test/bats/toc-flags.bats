#!/usr/bin/env bats
#
# Behavioural coverage for the '--toc' / '--no-toc' option pair: the fatal conflict
# when both are given, that each still converts successfully alone, that '-t' still
# sets the title after 'TOC:' was added to the 'setSimpleOptions' spec (task doc's
# flagged risk: a bare 'TOC' would otherwise derive the short option '-t', which
# 'TITLE:t=' already owns), and that '--help' documents '--toc' and no longer carries
# the retired docx caveat. See plan/phase-01-markdown-toc-generation/
# 003-add-toc-flag-and-conflict-check.md and
# plan/notes/toc-defaults-and-page-heuristic.md.
#
# Every conversion case uses '--flatten-dirs' with an input file in the case's own
# working directory, so output-path derivation is invariant regardless of task 002's
# mirrored-output-path fix.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- conflict: both flags together ---------------------------------------------------

@test "--toc --no-toc together exits non-zero, names both flags, and never calls pandoc" {
  md2x_write_doc 'report.md'

  md2x_run --toc --no-toc --flatten-dirs --output-path . report.md

  assert_failure
  assert_stderr_contains "Cannot specify both '--toc' and '--no-toc'"
  refute_stub_called pandoc
  assert_file_not_exists './report.pdf'
}

@test "--no-toc --toc in the opposite order behaves identically" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --toc --flatten-dirs --output-path . report.md

  assert_failure
  assert_stderr_contains "Cannot specify both '--toc' and '--no-toc'"
  refute_stub_called pandoc
  assert_file_not_exists './report.pdf'
}

# --- each flag alone still converts ---------------------------------------------------

@test "--toc alone still exits 0 and converts" {
  md2x_write_doc 'report.md'

  md2x_run --toc --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.pdf'
}

@test "--no-toc alone still exits 0 and converts" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.pdf'
}

# --- '-t' was not stolen by the new 'TOC:' spec ---------------------------------------

@test "-t Foo still sets the title after the TOC: option-spec change" {
  # The main per-file conversion loop in src/cli/md2x.sh always derives each output's
  # title from its own filename (a pre-existing behavior unrelated to this task -- see
  # the task document's Status section), so '-t'/'--title' has no observable effect on
  # a directly-named, non-'--single-page' conversion regardless of this task's change.
  # '--single-page' is the code path that genuinely honors '--title', so it is what
  # actually proves '-t' still parses correctly and was not stolen by the new 'TOC:'
  # entry claiming '-t' via setSimpleOptions' short-option derivation.
  md2x_write_doc 'report.md'

  md2x_run -t Foo --single-page --output-path . report.md

  assert_success
  assert_file_exists './Foo.pdf'
}

# --- help text --------------------------------------------------------------------

@test "--help mentions --toc and no longer contains the retired docx caveat" {
  md2x_run --help

  assert_success
  assert_output_contains '--toc'
  refute_output_contains 'docx output never receives'
}

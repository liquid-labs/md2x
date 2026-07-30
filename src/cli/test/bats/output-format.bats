#!/usr/bin/env bats
#
# Behavioural coverage for '--output-format' / '-F': format selection, the implicit
# default, and rejection of an unrecognized value before any conversion is attempted.
# See docs/md2x-spec.md's 'API definition' flag table, 'Exit behavior', and UC2.
#
# Every case uses '--flatten-dirs' with an input file that already sits in the case's
# own working directory, so output-path derivation is invariant regardless of task
# 002's mirrored-output-path fix (see plan/notes/test-tooling-survey.md).

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

@test "--output-format pdf converts to <title>.pdf" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.pdf'
  assert_output_contains 'Created ./report.pdf'
}

@test "--output-format html converts to <title>.html" {
  # The spec (docs/md2x-spec.md, UC2 and the API definition table) documents the base
  # name getting '.html' directly ('report.html'), exactly parallel to '<title>.pdf'
  # and '<title>.docx' for the other formats.
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.html'
}

@test "--output-format docx converts to <title>.docx" {
  md2x_write_doc 'report.md'

  md2x_run --output-format docx --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.docx'
  assert_output_contains 'Created ./report.docx'
}

@test "absent --output-format defaults to pdf" {
  md2x_write_doc 'report.md'

  md2x_run --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.pdf'
  refute_output_contains '.html'
  refute_output_contains '.docx'
}

@test "an unrecognized --output-format exits non-zero, names the format, and never calls pandoc" {
  md2x_write_doc 'report.md'

  md2x_run --output-format bogus --flatten-dirs --output-path . report.md

  assert_failure
  assert_stderr_contains "Unsupported output format 'bogus'"
  refute_stub_called pandoc
  assert_file_not_exists './report.pdf'
}

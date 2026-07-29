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

@test "--output-format html converts to <title>-base.html" {
  # The spec (docs/md2x-spec.md, UC2 and the API definition table) says nothing about
  # a '-base' suffix on HTML output -- it implies the base name gets '.html' directly
  # ('report.html'). 'src/cli/md2x.sh's per-file conversion loop appends '-base' to
  # the base output name whenever OUTPUT_FORMAT is 'html', before the extension is
  # appended. This case documents the actual behaviour rather than silently encoding
  # it as correct -- flagged as a candidate followup for the manager.
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report-base.html'
  assert_file_not_exists './report.html'
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

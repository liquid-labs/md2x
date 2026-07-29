#!/usr/bin/env bats
#
# Behavioural coverage for the flags that shape what the CLI prints, and how much:
# '--quiet' (suppress the "Created ..." line), '--list-files' (print only the path),
# '--to-stdout' (write the converted content to stdout, implying '--quiet'), and
# '--help' / '-h' (usage text, exit 0, no binary preflight -- docs/md2x-spec.md's
# API definition table and 'General features').

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

@test "--quiet suppresses the 'Created' line but still writes the output" {
  md2x_write_doc 'report.md'

  md2x_run --quiet --flatten-dirs --output-path . report.md

  assert_success
  refute_output_contains 'Created'
  assert_file_exists './report.pdf'
}

@test "--list-files prints only the generated path, with no 'Created ' prefix" {
  md2x_write_doc 'report.md'

  md2x_run --list-files --flatten-dirs --output-path . report.md

  assert_success
  assert_output_equals './report.pdf'
  refute_output_contains 'Created'
  assert_file_exists './report.pdf'
}

@test "--to-stdout writes the converted content to stdout and implies --quiet" {
  # Use 'html' rather than the default 'pdf': for pdf output the CLI overwrites the
  # base output with the pdftk-merged (header/footer overlay) content before it 'cat's
  # the file, so only a non-pdf format's stdout still carries the pandoc stub's own
  # placeholder verbatim.
  md2x_write_doc 'report.md' 'Piped Report'

  md2x_run --to-stdout --output-format html --flatten-dirs --output-path . report.md

  assert_success
  # The stub 'pandoc' writes a recognizable placeholder into its '-o' target; the CLI
  # then 'cat's that file to stdout when '--to-stdout' is given.
  assert_output_contains 'md2x-test-stub: pandoc output'
  refute_output_contains 'Created'
}

@test "--help exits 0 with usage text on stdout" {
  md2x_run --help

  assert_success
  assert_output_contains 'Usage:'
  assert_output_contains 'md2x [OPTIONS] <file>...'
}

@test "-h is a short alias for --help" {
  md2x_run -h

  assert_success
  assert_output_contains 'Usage:'
}

@test "--help exits 0 even with every required binary absent from PATH" {
  # Per the spec, '--help' skips the binary preflight entirely -- prove it by removing
  # all three stubs and still getting a clean, successful usage printout.
  md2x_path_without pandoc gs pdftk

  md2x_run --help

  assert_success
  assert_output_contains 'Usage:'
  refute_stub_called pandoc
  refute_stub_called gs
  refute_stub_called pdftk
}

#!/usr/bin/env bats
#
# Behavioural coverage for '--title'/'-t' precedence in the non-'--single-page',
# non-stdin ("per-file") conversion path: fixing followup CwaE, where the per-file
# loop unconditionally overwrote 'TITLE' from each input's own basename, so '--title'
# had zero effect on a directly-named or directory-search conversion's output filename
# or '--infer-title' metadata. '--single-page' and stdin ('-') conversions already
# honor '--title' correctly (they always produce exactly one output file) and are
# untouched by this fix -- see 'single-page-and-stdin.bats' for their coverage, which
# must keep passing unmodified. See
# plan/phase-01-title-precedence/001-fix-title-precedence-for-batch-conversions.md.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- (a) a single directly-named file honors --title ---------------------------------

@test "--title with one directly-named file is honored in the output filename" {
  md2x_write_doc 'report.md'

  md2x_run --title Foo --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './Foo.pdf'
  assert_file_not_exists './report.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'
}

@test "--title with one directly-named file and --infer-title carries the title into pandoc metadata" {
  md2x_write_doc 'report.md'

  md2x_run --title Foo --infer-title --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './Foo.pdf'
  local run_metadata
  run_metadata="$(md2x_pandoc_capture metadata)"
  [[ "${run_metadata}" == *"title: 'Foo'"* ]] \
    || md2x_fail "expected captured metadata to carry the explicit title, got: ${run_metadata}"
}

# --- (b) a directory search resolving to exactly one file honors --title -------------

@test "--title with a directory search resolving to exactly one file is honored" {
  md2x_write_doc 'single-dir/report.md'

  md2x_run --title Foo --output-path . single-dir

  assert_success
  assert_file_exists './Foo.pdf'
  assert_file_not_exists './report.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'
}

# --- (c) multiple directly-named files with --title is a fatal error -----------------

@test "--title with multiple directly-named files is a fatal error" {
  md2x_write_doc 'report.md'
  md2x_write_doc 'notes.md'

  md2x_run --title Foo --flatten-dirs --output-path . report.md notes.md

  assert_failure
  assert_stderr_contains "--title"
  assert_stderr_contains "-t"
  refute_stub_called pandoc
  assert_file_not_exists './Foo.pdf'
  assert_file_not_exists './report.pdf'
  assert_file_not_exists './notes.pdf'
}

# --- (d) a directory search yielding multiple files with --title is a fatal error ----

@test "--title with a directory search yielding multiple files is a fatal error" {
  md2x_write_doc 'multi-dir/report.md'
  md2x_write_doc 'multi-dir/notes.md'

  md2x_run --title Foo --output-path . multi-dir

  assert_failure
  assert_stderr_contains "--title"
  assert_stderr_contains "-t"
  refute_stub_called pandoc
  assert_file_not_exists './Foo.pdf'
  assert_file_not_exists './report.pdf'
  assert_file_not_exists './notes.pdf'
}

# --- (e) regression control: no --title with multiple files is unchanged -------------

@test "no --title with multiple directly-named files still names each output from its own basename" {
  md2x_write_doc 'report.md'
  md2x_write_doc 'notes.md'

  md2x_run --flatten-dirs --output-path . report.md notes.md

  assert_success
  assert_file_exists './report.pdf'
  assert_file_exists './notes.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '2' 'pandoc invocation count'
}

@test "no --title with a multi-file directory search still names each output from its own basename" {
  md2x_write_doc 'multi-dir/report.md'
  md2x_write_doc 'multi-dir/notes.md'

  md2x_run --output-path . multi-dir

  assert_success
  assert_file_exists './report.pdf'
  assert_file_exists './notes.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '2' 'pandoc invocation count'
}

# --- mixed-source case: requirement 2's file-count summing across both sources -------

@test "--title with a directly-named file plus a directory search totalling more than one file is a fatal error" {
  md2x_write_doc 'report.md'
  md2x_write_doc 'single-dir/notes.md'

  md2x_run --title Foo --output-path . report.md single-dir

  assert_failure
  assert_stderr_contains "--title"
  assert_stderr_contains "-t"
  refute_stub_called pandoc
  assert_file_not_exists './Foo.pdf'
  assert_file_not_exists './report.pdf'
  assert_file_not_exists './notes.pdf'
}

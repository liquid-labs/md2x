#!/usr/bin/env bats
#
# Behavioural coverage for the flags that change what md2x hands to 'pandoc' and 'gs':
# '--infer-title' (title metadata), '--no-toc' (table-of-contents suppression, format-
# dependent), '--infer-version' (the Ghostscript footer's version string), and
# '--keep-intermediate' (retaining the Pandoc log, PDF overlay, and CSS temp file). See
# docs/md2x-spec.md's 'General features' and API definition table.
#
# Every case uses '--flatten-dirs' with an input file in the case's own working
# directory, so output-path derivation is invariant regardless of task 002's mirrored-
# output-path fix.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- --infer-title ------------------------------------------------------------------

@test "--infer-title embeds the title in the metadata file pandoc receives" {
  md2x_write_doc 'report.md'

  md2x_run --infer-title --flatten-dirs --output-path . report.md

  assert_success
  local run_metadata
  run_metadata="$(md2x_pandoc_capture metadata)"
  [[ "${run_metadata}" == *"title: 'report'"* ]] \
    || md2x_fail "expected captured metadata to carry the title, got: ${run_metadata}"
}

@test "without --infer-title, the metadata file carries no title" {
  md2x_write_doc 'report.md'

  md2x_run --flatten-dirs --output-path . report.md

  assert_success
  local run_metadata
  run_metadata="$(md2x_pandoc_capture metadata)"
  [[ "${run_metadata}" != *'title:'* ]] \
    || md2x_fail "expected captured metadata NOT to carry a title, got: ${run_metadata}"
}

# --- --no-toc ------------------------------------------------------------------------

@test "--no-toc removes --toc from the pandoc invocation for pdf output" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "without --no-toc, pdf output includes --toc" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_last_call_has_arg pandoc '--toc'
}

@test "--no-toc removes --toc from the pandoc invocation for html output" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --output-format html --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "without --no-toc, html output includes --toc" {
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  assert_last_call_has_arg pandoc '--toc'
}

@test "docx output never includes --toc, with --no-toc given" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --output-format docx --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "docx output never includes --toc, without --no-toc given" {
  md2x_write_doc 'report.md'

  md2x_run --output-format docx --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

# --- --infer-version -----------------------------------------------------------------

@test "--infer-version adds a Version: string to the Ghostscript overlay invocation" {
  md2x_write_doc 'report.md'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  # Outside a git work tree (every case's temp cwd) the version probe falls back to
  # the literal 'working' -- see plan/notes/test-tooling-survey.md.
  assert_any_call_contains gs 'Version: working'
}

@test "without --infer-version, no Version: string appears in the Ghostscript invocation" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  refute_any_call_contains gs 'Version:'
}

# --- --keep-intermediate ---------------------------------------------------------------

@test "--keep-intermediate retains the pandoc log and pdf overlay after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists 'pandoc-log.log'
  assert_file_exists './report-overlay.pdf'
}

@test "without --keep-intermediate, the pandoc log and pdf overlay are removed after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_file_not_exists 'pandoc-log.log'
  assert_file_not_exists './report-overlay.pdf'
}

@test "--keep-intermediate retains the css temp file handed to pandoc after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local css_tmp_file
  css_tmp_file="$(md2x_stub_last_call_args pandoc | grep '\.css$' || true)"
  [[ -n "${css_tmp_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --css argument ending in .css'
  assert_file_exists "${css_tmp_file}"
}

@test "without --keep-intermediate, the css temp file handed to pandoc is removed after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local css_tmp_file
  css_tmp_file="$(md2x_stub_last_call_args pandoc | grep '\.css$' || true)"
  [[ -n "${css_tmp_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --css argument ending in .css'
  assert_file_not_exists "${css_tmp_file}"
}

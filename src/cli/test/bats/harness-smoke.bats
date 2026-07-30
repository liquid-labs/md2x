#!/usr/bin/env bats
#
# Self-verification for the CLI test harness itself: the temp working directory, the
# stubbed PATH, the stub side effects, the invocation log, the pandoc capture
# directory and the fixture builders. These are the pieces the behavioural suites
# build on, so if this file goes red, treat it as harness breakage rather than a
# regression in md2x's option handling.
#
# Behavioural coverage of the CLI's options lives in the sibling '*.bats' files.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

@test "harness: runs the built CLI and captures its stdout" {
  md2x_run --help

  assert_success
  assert_output_contains 'Usage:'
  assert_output_contains 'md2x [OPTIONS] <file>...'
}

@test "harness: each case gets its own working directory outside the repository" {
  [[ "${PWD}" == "${MD2X_TEST_WORK_DIR}" ]] \
    || md2x_fail "expected cwd '${MD2X_TEST_WORK_DIR}', got '${PWD}'"
  [[ "${PWD}" != "${MD2X_REPO_ROOT}"* ]] \
    || md2x_fail "cwd is inside the repository: ${PWD}"

  md2x_write_doc 'report.md'
  assert_file_exists 'report.md'
}

@test "harness: a pdf conversion drives all three stubs and yields the output file" {
  md2x_write_doc 'report.md'

  md2x_run --flatten-dirs --output-path . report.md

  assert_success
  assert_output_contains 'Created ./report.pdf'
  assert_file_exists './report.pdf'

  assert_stub_called pandoc
  assert_stub_called gs
  assert_stub_called pdftk
  assert_last_call_has_arg pandoc '--toc'

  # The CLI removes both intermediates under 'set -o errexit'; their absence here means
  # the stubs really did create them.
  assert_file_not_exists 'pandoc-log.log'
  assert_file_not_exists './report-overlay.pdf'
}

@test "harness: an html conversion leaves the pdf-only tools untouched" {
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.html'
  assert_stub_called pandoc
  refute_stub_called gs
  refute_stub_called pdftk
}

@test "harness: the temp cwd makes the inferred version deterministic" {
  md2x_write_doc 'report.md'

  md2x_run --infer-version --flatten-dirs --output-path . report.md

  assert_success
  # Outside a git work tree the version probe falls back to the literal 'working',
  # which the CLI bakes into the Ghostscript overlay's PostScript string.
  assert_any_call_contains gs 'Version: working'
}

@test "harness: pandoc's process-substitution arguments are captured" {
  md2x_write_doc 'report.md' 'Report Heading'

  md2x_run --infer-title --flatten-dirs --output-path . report.md

  assert_success
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'
  run_metadata="$(md2x_pandoc_capture metadata)"
  [[ "${run_metadata}" == *"title: 'report'"* ]] \
    || md2x_fail "expected captured metadata to carry the title, got: ${run_metadata}"

  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'Report Heading'* ]] \
    || md2x_fail "expected captured input to carry the document body, got: ${run_input}"
}

@test "harness: the fixture tree builder produces a walkable source tree" {
  local root
  root="$(md2x_make_fixture_tree)"
  mkdir -p out

  md2x_run --flatten-dirs --output-path out "${root}"

  assert_success
  assert_file_exists 'out/alpha.pdf'
  assert_file_exists 'out/beta.pdf'
  assert_stub_call_count pandoc 2
}

@test "harness: the checked-in tiny-doc fixture can be copied into the case" {
  md2x_copy_fixture 'tiny-doc.md'
  assert_file_exists 'tiny-doc.md'

  md2x_run --output-format docx --flatten-dirs --output-path . tiny-doc.md

  assert_success
  assert_file_exists './tiny-doc.docx'
  # docx never gets an automatic table of contents.
  refute_last_call_has_arg pandoc '--toc'
}

@test "harness: md2x_run can drive the CLI's stdin mode" {
  md2x_run --output-format html --output-path . - <<< '# Piped Heading'

  assert_success
  assert_file_exists './output.html'
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'Piped Heading'* ]] \
    || md2x_fail "expected the piped markdown to reach pandoc, got: ${run_input}"
}

@test "harness: a pdf conversion under the default setup never triggers the real weasyprint bootstrap" {
  assert_file_exists "${HOME}/.md2x/venv/bin/weasyprint"

  md2x_write_doc 'report.md'
  md2x_run --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './report.pdf'
  # Absent the fake binary's '-x' gate short-circuiting it, 'ensure-weasyprint()' would
  # print this notice before falling into the real, network-dependent bootstrap.
  [[ "${stderr}" != *'md2x: installing weasyprint'* ]] \
    || md2x_fail "cold weasyprint bootstrap ran under the default md2x_setup: ${stderr}"
}

@test "harness: md2x_path_without genuinely removes a binary from PATH" {
  md2x_write_doc 'report.md'
  md2x_path_without pandoc

  md2x_run report.md

  assert_failure 2
  assert_stderr_contains "Required executable 'pandoc' not found"
  refute_stub_called pandoc
}

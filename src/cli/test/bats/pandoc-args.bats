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
  assert_stderr_contains "${css_tmp_file}"
}

@test "--quiet --keep-intermediate still prints the retained css temp file path to stderr" {
  md2x_write_doc 'report.md'

  md2x_run --quiet --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local css_tmp_file
  css_tmp_file="$(md2x_stub_last_call_args pandoc | grep '\.css$' || true)"
  [[ -n "${css_tmp_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --css argument ending in .css'
  assert_stderr_contains "${css_tmp_file}"
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

@test "--keep-intermediate retains the body-open/body-close temp files handed to pandoc after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local body_open_tmp_file body_close_tmp_file
  body_open_tmp_file="$(md2x_stub_last_call_args pandoc | grep 'md2x-body-open\.' || true)"
  body_close_tmp_file="$(md2x_stub_last_call_args pandoc | grep 'md2x-body-close\.' || true)"
  [[ -n "${body_open_tmp_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --include-before-body argument naming a md2x-body-open temp file'
  [[ -n "${body_close_tmp_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --include-after-body argument naming a md2x-body-close temp file'
  assert_file_exists "${body_open_tmp_file}"
  assert_file_exists "${body_close_tmp_file}"
}

@test "without --keep-intermediate, the body-open/body-close temp files handed to pandoc are removed after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local body_open_tmp_file body_close_tmp_file
  body_open_tmp_file="$(md2x_stub_last_call_args pandoc | grep 'md2x-body-open\.' || true)"
  body_close_tmp_file="$(md2x_stub_last_call_args pandoc | grep 'md2x-body-close\.' || true)"
  [[ -n "${body_open_tmp_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --include-before-body argument naming a md2x-body-open temp file'
  [[ -n "${body_close_tmp_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --include-after-body argument naming a md2x-body-close temp file'
  assert_file_not_exists "${body_open_tmp_file}"
  assert_file_not_exists "${body_close_tmp_file}"
}

# --- '--include-before-body'/'--include-after-body' markdown-body wrapper -----------
#
# followup TNLq / task 004: 'github.css' scopes every rule under a bare
# '.markdown-body' class selector, and nothing in the generated document otherwise
# carries that class. 'generate-page()' wraps the whole rendered body in
# '<div class="markdown-body">...</div>' via these two flags for pdf/html output, and
# must never do so for docx (the div would be invalid raw content inside '<w:body>').

@test "pdf output wraps the body in a markdown-body div via --include-before-body/--include-after-body" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_last_call_has_arg pandoc '--include-before-body'
  assert_last_call_has_arg pandoc '--include-after-body'
  [[ "$(md2x_pandoc_capture body-open)" == '<div class="markdown-body">' ]] \
    || md2x_fail "expected captured --include-before-body content to be the markdown-body div, got: $(md2x_pandoc_capture body-open)"
  [[ "$(md2x_pandoc_capture body-close)" == '</div>' ]] \
    || md2x_fail "expected captured --include-after-body content to be a closing div, got: $(md2x_pandoc_capture body-close)"
}

@test "html output wraps the body in a markdown-body div via --include-before-body/--include-after-body" {
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  assert_last_call_has_arg pandoc '--include-before-body'
  assert_last_call_has_arg pandoc '--include-after-body'
  [[ "$(md2x_pandoc_capture body-open)" == '<div class="markdown-body">' ]] \
    || md2x_fail "expected captured --include-before-body content to be the markdown-body div, got: $(md2x_pandoc_capture body-open)"
  [[ "$(md2x_pandoc_capture body-close)" == '</div>' ]] \
    || md2x_fail "expected captured --include-after-body content to be a closing div, got: $(md2x_pandoc_capture body-close)"
}

@test "docx output never includes --include-before-body/--include-after-body" {
  md2x_write_doc 'report.md'

  md2x_run --output-format docx --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--include-before-body'
  refute_last_call_has_arg pandoc '--include-after-body'
}

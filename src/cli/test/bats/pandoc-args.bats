#!/usr/bin/env bats
#
# Behavioural coverage for the flags that change what md2x hands to 'pandoc' and 'gs':
# '--infer-title' (title metadata), '--infer-version' (the Ghostscript footer's
# version string), and '--keep-intermediate' (retaining the per-run work directory with the
# Pandoc log, PDF overlay, CSS file, and so on). Pandoc's own '--toc' is retired for every format -- md2x
# generates the table of contents itself, ahead of Pandoc, as ordinary Markdown
# content; this file only asserts that Pandoc's '--toc' argument never reappears.
# The behavioural TOC coverage (placement, content, the '--toc'/'--no-toc' resolution)
# lives in 'toc-flags.bats' (flag parsing/conflict) and 'toc-generation.bats'
# (generated content). See docs/md2x-spec.md's 'General features' and API definition
# table.
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

@test "--infer-title passes the title to pandoc as one -M argument" {
  md2x_write_doc 'report.md'

  md2x_run --infer-title --flatten-dirs --output-path . report.md

  assert_success
  assert_last_call_has_arg pandoc 'title=report'
  refute_last_call_contains pandoc '--metadata-file'
}

@test "without --infer-title, pandoc receives no title metadata" {
  md2x_write_doc 'report.md'

  md2x_run --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_contains pandoc 'title='
  refute_last_call_contains pandoc '--metadata-file'
}

# --- Pandoc's native --toc is retired -------------------------------------------------
#
# md2x generates the table of contents itself, ahead of Pandoc, as ordinary Markdown
# content -- Pandoc's own '--toc' flag is never passed, in any format, regardless of
# '--toc'/'--no-toc'. See 'toc-generation.bats' for the generated-content coverage.

@test "pdf output never includes --toc, without --no-toc/--toc given" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "pdf output never includes --toc, with --no-toc given" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "pdf output never includes --toc, with --toc given" {
  md2x_write_doc 'report.md'

  md2x_run --toc --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "html output never includes --toc, without --no-toc/--toc given" {
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "html output never includes --toc, with --no-toc given" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --output-format html --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "html output never includes --toc, with --toc given" {
  md2x_write_doc 'report.md'

  md2x_run --toc --output-format html --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "docx output never includes --toc, without --no-toc/--toc given" {
  md2x_write_doc 'report.md'

  md2x_run --output-format docx --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "docx output never includes --toc, with --no-toc given" {
  md2x_write_doc 'report.md'

  md2x_run --no-toc --output-format docx --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--toc'
}

@test "docx output never includes --toc, with --toc given" {
  md2x_write_doc 'report.md'

  md2x_run --toc --output-format docx --flatten-dirs --output-path . report.md

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

@test "--keep-intermediate retains the pandoc log and pdf overlay in the work directory" {
  md2x_write_doc 'report.md'

  md2x_run --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local kept
  kept="$(md2x_kept_work_dir)"
  [[ -n "${kept}" ]] || md2x_fail 'expected a kept-intermediate notice on stderr' "got: ${stderr}"
  assert_file_exists "${kept}/pandoc.log"
  assert_file_exists "${kept}/overlay.pdf"
  assert_file_not_exists 'pandoc-log.log'
  assert_file_not_exists './report-overlay.pdf'
}

@test "without --keep-intermediate, no pandoc log or pdf overlay is left anywhere" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_file_not_exists 'pandoc-log.log'
  assert_file_not_exists './report-overlay.pdf'
  refute_stderr_contains 'kept intermediate'
  [[ -z "$(ls -A "${TMPDIR}")" ]] || md2x_fail 'expected TMPDIR to be empty' "$(ls -A "${TMPDIR}")"
}

@test "--keep-intermediate retains the css file handed to pandoc after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local css_file kept
  css_file="$(md2x_stub_last_call_args pandoc | grep '\.css$' || true)"
  [[ -n "${css_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --css argument ending in .css'
  assert_file_exists "${css_file}"
  kept="$(md2x_kept_work_dir)"
  [[ "${css_file}" == "${kept}/"* ]] || md2x_fail "expected the css file inside '${kept}', got '${css_file}'"
}

@test "--quiet --keep-intermediate still prints the kept work directory to stderr" {
  md2x_write_doc 'report.md'

  md2x_run --quiet --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  [[ -n "$(md2x_kept_work_dir)" ]] || md2x_fail 'expected a kept-intermediate notice on stderr' "got: ${stderr}"
  assert_output_equals ''
}

@test "without --keep-intermediate, the css file handed to pandoc is removed after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local css_file
  css_file="$(md2x_stub_last_call_args pandoc | grep '\.css$' || true)"
  [[ -n "${css_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a --css argument ending in .css'
  assert_file_not_exists "${css_file}"
}

@test "--keep-intermediate retains the body-open/body-close files handed to pandoc after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local kept
  kept="$(md2x_kept_work_dir)"
  assert_file_exists "${kept}/body-open.html"
  assert_file_exists "${kept}/body-close.html"
  assert_last_call_has_arg pandoc "${kept}/body-open.html"
  assert_last_call_has_arg pandoc "${kept}/body-close.html"
}

@test "without --keep-intermediate, the body-open/body-close files handed to pandoc are removed after conversion" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local body_open_file
  body_open_file="$(md2x_stub_last_call_args pandoc | grep 'body-open\.html$' || true)"
  [[ -n "${body_open_file}" ]] || md2x_fail 'expected the last pandoc invocation to carry a body-open include file'
  assert_file_not_exists "${body_open_file}"
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

# --- HTML styling is inline, never a '--css' link ------------------------------------
#
# A '--css' link in HTML output points at a work-directory file deleted at exit. HTML
# embeds the bundled stylesheet via '--include-in-header' instead; PDF keeps '--css'.

@test "html output passes no --css argument to pandoc" {
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--css'
  assert_last_call_has_arg pandoc '--include-in-header'
}

@test "html output embeds the bundled stylesheet in a <style> block via --include-in-header" {
  md2x_write_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  local header
  header="$(md2x_pandoc_capture header)"
  [[ "${header}" == '<style>'* ]] \
    || md2x_fail "expected the header include to start with <style>, got: ${header}"
  [[ "${header}" == *'</style>' ]] \
    || md2x_fail "expected the header include to end with </style>, got: ${header}"
  [[ "${header}" == *'.markdown-body'* ]] \
    || md2x_fail "expected the header include to carry the bundled stylesheet, got: ${header}"
}

@test "html output never references the work directory in any pandoc argument" {
  md2x_write_doc 'report.md'

  md2x_run --keep-intermediate --output-format html --flatten-dirs --output-path . report.md

  assert_success
  refute_last_call_has_arg pandoc '--css'
  local css_arg
  css_arg="$(md2x_stub_last_call_args pandoc | grep '\.css$' || true)"
  [[ -z "${css_arg}" ]] || md2x_fail "expected no .css argument for html, got: ${css_arg}"
}

@test "pdf output still passes a .css path to pandoc" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_last_call_has_arg pandoc '--css'
  refute_last_call_has_arg pandoc '--include-in-header'
  local css_arg
  css_arg="$(md2x_stub_last_call_args pandoc | grep '\.css$' || true)"
  [[ -n "${css_arg}" ]] || md2x_fail 'expected the pdf pandoc invocation to carry a .css argument'
}

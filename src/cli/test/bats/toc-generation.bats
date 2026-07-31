#!/usr/bin/env bats
#
# Integration coverage for the TOC preprocessor wired into 'generate-page()' (see
# plan/phase-01-markdown-toc-generation/004-wire-preprocessor-into-generate-page.md):
# that the buffer Pandoc actually receives carries the generated table of contents (or
# doesn't), in the right place, for every output format -- including docx, the
# headline behavior change (Pandoc's own '--toc' never worked for docx; see
# 'pandoc-args.bats', which now only asserts that flag is never passed). Placement,
# content, and the default heuristic are defined in
# 'plan/notes/toc-defaults-and-page-heuristic.md'; the slug algorithm and
# per-line preprocessor behavior are unit-tested directly against
# 'src/cli/lib/toc-preprocess.py' in 'toc-preprocess.bats'. This file drives the built
# CLI end to end and asserts only on the buffer 'md2x_pandoc_capture input' returns.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- fixtures ----------------------------------------------------------------------

# md2x_write_toc_worthy_doc <path>
# Writes a document that clears the default auto-heuristic on both axes: 4 '##'
# sections (at least the 4-section floor) and, once padded with blank filler lines,
# more than the 90-estimated-rendered-line threshold that stands in for "more than 2
# pages" (see plan/notes/toc-defaults-and-page-heuristic.md's calibrated estimator).
# 18 structural lines + 90 blank padding lines = 108 total, comfortably past both
# floors (each blank line contributes exactly 1 to the estimator's line total).
md2x_write_toc_worthy_doc() {
  local path="$1"
  md2x_toc_worthy_doc_text > "${path}"
}

# md2x_toc_worthy_doc_text -- same content as above, printed to stdout, for driving
# the stdin ('-') path.
md2x_toc_worthy_doc_text() {
  local n i
  printf '# Doc Title\n\n'
  for n in 0 1 2 3; do
    printf '## Section %s\n\nBody text for section %s.\n\n' "${n}" "${n}"
  done
  for ((i = 0; i < 90; i++)); do
    printf '\n'
  done
}

# md2x_write_tiny_toc_doc <path>
# A title-plus-one-section document: far too small to trigger the auto heuristic (one
# top-level section, well under the estimated-page floor), but -- unlike a
# title-only fixture -- carries a non-title heading that CAN appear in a forced TOC.
# The document-title heading is always excluded from the emitted list (see
# plan/notes/toc-defaults-and-page-heuristic.md's 'Document title' section), so a
# title-only document can never show a TOC list regardless of '--toc'.
md2x_write_tiny_toc_doc() {
  local path="$1"
  cat > "${path}" <<'EOF'
# Tiny Title

Some intro text.

## Only Section

Section body text.
EOF
}

# --- TOC-worthy document: bullet list present, all three formats -------------------

@test "a TOC-worthy document gets a bullet list in the pandoc buffer for pdf" {
  md2x_write_toc_worthy_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'](#'* ]] \
    || md2x_fail 'expected the pdf buffer to carry a generated TOC bullet list' "got: ${run_input}"
}

@test "a TOC-worthy document gets a bullet list in the pandoc buffer for html" {
  md2x_write_toc_worthy_doc 'report.md'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'](#'* ]] \
    || md2x_fail 'expected the html buffer to carry a generated TOC bullet list' "got: ${run_input}"
}

@test "a TOC-worthy document gets a bullet list in the pandoc buffer for docx (headline behavior change)" {
  md2x_write_toc_worthy_doc 'report.md'

  md2x_run --output-format docx --flatten-dirs --output-path . report.md

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'](#'* ]] \
    || md2x_fail 'expected the docx buffer to carry a generated TOC bullet list' "got: ${run_input}"
}

# --- --no-toc / --toc / neither, resolution -----------------------------------------

@test "--no-toc on a TOC-worthy document adds no bullet list" {
  md2x_write_toc_worthy_doc 'report.md'

  md2x_run --no-toc --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" != *'](#'* ]] \
    || md2x_fail 'expected --no-toc to suppress the generated TOC bullet list' "got: ${run_input}"
}

@test "--toc on an otherwise-small document forces a bullet list" {
  md2x_write_tiny_toc_doc 'report.md'

  md2x_run --toc --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'](#only-section)'* ]] \
    || md2x_fail 'expected --toc to force a TOC bullet list even on a small document' "got: ${run_input}"
}

@test "neither --toc nor --no-toc on a small document adds no bullet list" {
  md2x_write_tiny_toc_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" != *'](#'* ]] \
    || md2x_fail 'expected a small document with neither flag to get no TOC' "got: ${run_input}"
}

# --- marker placement / literal-comment removal -------------------------------------

@test "a md2x:toc marker places the list at the marker and removes the literal comment" {
  cat > 'report.md' <<'EOF'
# Marker Doc

SENTINEL_PARAGRAPH

<!-- md2x:toc -->

## Section One

Body one.

## Section Two

Body two.
EOF

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local run_input after_sentinel
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" != *'<!-- md2x:toc -->'* ]] \
    || md2x_fail 'expected the literal marker comment to be removed from the buffer' "got: ${run_input}"
  after_sentinel="${run_input#*SENTINEL_PARAGRAPH}"
  [[ "${after_sentinel}" == *'- ['* ]] \
    || md2x_fail 'expected the TOC bullet list to follow the sentinel paragraph' "got: ${run_input}"
}

# --- no marker: list lands after the title, not before it (the defect this fixes) --

@test "with no marker, the list lands after the document title, not before it" {
  cat > 'report.md' <<'EOF'
# Title Doc

Intro text.

## Section One

Body one.

## Section Two

Body two.
EOF

  md2x_run --toc --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local run_input after_title before_first_section
  run_input="$(md2x_pandoc_capture input)"
  after_title="${run_input#*'# Title Doc'}"
  before_first_section="${after_title%%'## '*}"
  [[ "${before_first_section}" == *'- ['* ]] \
    || md2x_fail 'expected the TOC bullet list to land after the title and before the first section' \
      "got: ${run_input}"
}

# --- marker inside a fence is inert --------------------------------------------------

@test "a md2x:toc marker inside a fenced code block is left verbatim and is not an insertion point" {
  cat > 'report.md' <<'EOF'
# Fence Doc

Some intro text.

```text
<!-- md2x:toc -->
```

## Section One

Body one.
EOF

  md2x_run --toc --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local run_input after_title before_first_section
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'<!-- md2x:toc -->'* ]] \
    || md2x_fail 'expected the fenced marker to be left verbatim' "got: ${run_input}"
  after_title="${run_input#*'# Fence Doc'}"
  before_first_section="${after_title%%'## '*}"
  [[ "${before_first_section}" == *'- ['* ]] \
    || md2x_fail 'expected the default-position TOC bullet list to appear after the title, since the' \
      'fenced marker is not a real insertion point' "got: ${run_input}"
}

# --- --single-page cross-file heading dedup -----------------------------------------

@test "--single-page dedups a '## Overview' heading repeated across files: #overview then #overview-1" {
  cat > 'chapter1.md' <<'EOF'
# Chapter One

## Overview

Body text one.
EOF
  cat > 'chapter2.md' <<'EOF'
# Chapter Two

## Overview

Body text two.
EOF

  md2x_run --toc --single-page --output-path . chapter1.md chapter2.md

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'(#overview)'* ]] \
    || md2x_fail 'expected the first Overview heading to slug to #overview' "got: ${run_input}"
  [[ "${run_input}" == *'(#overview-1)'* ]] \
    || md2x_fail 'expected the second Overview heading to dedup to #overview-1' \
      '(dedup must run over the whole concatenated stream, not per file)' "got: ${run_input}"
}

# --- stdin parity ---------------------------------------------------------------------

@test "the stdin '-' path gets the same TOC treatment as a file argument" {
  # A here-string (or '$(...)') would strip the fixture's trailing blank padding
  # lines -- command substitution trims trailing newlines -- silently shrinking the
  # document back under the auto-heuristic's line-count floor. Redirect from a real
  # file instead, so every padding line survives exactly as the file-argument cases
  # see it.
  md2x_write_toc_worthy_doc 'report.md'

  md2x_run --output-format html --output-path . - < 'report.md'

  assert_success
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'](#'* ]] \
    || md2x_fail 'expected the piped document to get a generated TOC bullet list' "got: ${run_input}"
}

# --- --keep-intermediate retention of the preprocessed temp file --------------------

@test "--keep-intermediate retains the preprocessed temp file, and it contains the TOC" {
  md2x_write_toc_worthy_doc 'report.md'

  md2x_run --keep-intermediate --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local preprocessed_tmp_file
  preprocessed_tmp_file="$(md2x_stub_last_call_args pandoc | grep 'md2x-preprocessed\.' || true)"
  [[ -n "${preprocessed_tmp_file}" ]] \
    || md2x_fail 'expected the last pandoc invocation to carry a md2x-preprocessed temp file argument'
  assert_file_exists "${preprocessed_tmp_file}"
  assert_file_contains "${preprocessed_tmp_file}" '](#'

  # Unlike the case's own working directory (removed wholesale by 'md2x_teardown'),
  # 'PREPROCESSED_TMP_FILE' lives in the ambient '${TMPDIR}' -- exactly the CSS/
  # body-open/body-close temp files do -- so a case that deliberately retains it must
  # also delete it itself, once its assertions are done, to leave no orphan behind (see
  # this task doc's '## Validation').
  rm -f "${preprocessed_tmp_file}"
}

@test "without --keep-intermediate, the preprocessed temp file is removed after conversion" {
  md2x_write_toc_worthy_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  local preprocessed_tmp_file
  preprocessed_tmp_file="$(md2x_stub_last_call_args pandoc | grep 'md2x-preprocessed\.' || true)"
  [[ -n "${preprocessed_tmp_file}" ]] \
    || md2x_fail 'expected the last pandoc invocation to carry a md2x-preprocessed temp file argument'
  assert_file_not_exists "${preprocessed_tmp_file}"
}

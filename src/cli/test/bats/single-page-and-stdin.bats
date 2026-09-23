#!/usr/bin/env bats
#
# Behavioural coverage for '--single-page' (concatenate all inputs into a single
# document before conversion, UC4) and stdin '-' (read the document to convert from
# standard input, UC5). Neither passes through the mirrored-output-path branch of
# 'src/cli/md2x.sh' (task 002's concern -- see plan/notes/test-tooling-survey.md), so
# both are safe, invariant shapes for asserting exact output paths.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- --single-page --------------------------------------------------------------------

@test "--single-page concatenates multiple files, in order, into one output named from --title" {
  md2x_write_doc 'chapter1.md' 'Chapter One'
  md2x_write_doc 'chapter2.md' 'Chapter Two'
  md2x_write_doc 'chapter3.md' 'Chapter Three'

  md2x_run --single-page --title CombinedReport --output-path . chapter1.md chapter2.md chapter3.md

  assert_success
  assert_file_exists './CombinedReport.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'

  local pdf_count
  pdf_count="$(find . -maxdepth 1 -name '*.pdf' | wc -l | tr -d ' ')"
  assert_equal "${pdf_count}" '1' 'output pdf file count'

  # Prove ordering by checking that each chapter's heading follows the previous one in
  # the buffer pandoc actually received, rather than trusting the CLI happened to
  # process them in argument order.
  local run_input after_one after_two
  run_input="$(md2x_pandoc_capture input)"
  after_one="${run_input#*Chapter One}"
  [[ "${after_one}" == *'Chapter Two'* ]] \
    || md2x_fail "expected 'Chapter Two' to follow 'Chapter One' in the concatenated input" \
      "got: ${run_input}"
  after_two="${after_one#*Chapter Two}"
  [[ "${after_two}" == *'Chapter Three'* ]] \
    || md2x_fail "expected 'Chapter Three' to follow 'Chapter Two' in the concatenated input" \
      "got: ${run_input}"
}

@test "--single-page defaults the output name to 'output' when --title is absent" {
  md2x_write_doc 'chapter1.md' 'Chapter One'
  md2x_write_doc 'chapter2.md' 'Chapter Two'

  md2x_run --single-page --output-path . chapter1.md chapter2.md

  assert_success
  assert_file_exists './output.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'

  local pdf_count
  pdf_count="$(find . -maxdepth 1 -name '*.pdf' | wc -l | tr -d ' ')"
  assert_equal "${pdf_count}" '1' 'output pdf file count'

  # Regression coverage: the default-title concatenation target and the file
  # 'generate-page()' is told to read used to diverge (see
  # plan/notes/pipeline-verification.md), so pandoc silently received an empty buffer
  # and the CLI printed a 'cat: ... No such file' diagnostic while still exiting 0.
  # Assert on both the symptom (no diagnostic) and the content (both chapters present,
  # in order), rather than just the output file's existence.
  refute_stderr_contains 'cat:'

  local run_input after_one
  run_input="$(md2x_pandoc_capture input)"
  after_one="${run_input#*Chapter One}"
  [[ "${after_one}" == *'Chapter Two'* ]] \
    || md2x_fail "expected 'Chapter Two' to follow 'Chapter One' in the concatenated input" \
      "got: ${run_input}"
}

# --- stdin '-' -------------------------------------------------------------------------

@test "stdin '-' produces one output named from --title, invoking pandoc exactly once" {
  md2x_run --output-path . --title Piped - <<< '# Piped Heading'

  assert_success
  assert_file_exists './Piped.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'

  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'Piped Heading'* ]] \
    || md2x_fail "expected the piped markdown to reach pandoc, got: ${run_input}"
}

@test "stdin '-' defaults the output name to 'output' when --title is absent" {
  md2x_run --output-path . - <<< '# Piped Heading'

  assert_success
  assert_file_exists './output.pdf'
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'
}

# --- '--single-page' concatenation temp file (followup flSJ) ---------------------------

@test "--single-page removes the concatenation file from the cwd by default" {
  md2x_write_doc 'chapter1.md' 'Chapter One'
  md2x_write_doc 'chapter2.md' 'Chapter Two'

  md2x_run --single-page --title CombinedReport --output-path . chapter1.md chapter2.md

  assert_success
  assert_file_exists './CombinedReport.pdf'
  assert_file_not_exists './CombinedReport.md'
}

@test "--single-page --keep-intermediate retains the concatenation file and announces it on stderr" {
  md2x_write_doc 'chapter1.md' 'Chapter One'
  md2x_write_doc 'chapter2.md' 'Chapter Two'

  md2x_run --single-page --keep-intermediate --title CombinedReport --output-path . chapter1.md chapter2.md

  assert_success
  assert_file_exists './CombinedReport.pdf'
  assert_file_exists './CombinedReport.md'
  assert_stderr_contains "kept intermediate combined file: 'CombinedReport.md'"
}

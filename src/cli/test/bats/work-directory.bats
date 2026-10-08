#!/usr/bin/env bats
#
# Regression coverage for the per-run work directory: every intermediate file md2x
# creates lives in one 'mktemp -d' directory under TMPDIR, so nothing but the requested
# outputs is ever written to the cwd or the output directory, and nothing is left in
# TMPDIR unless '--keep-intermediate' is given. Covers audit findings B1 (a '--title'
# matching an input file deleted that file), S13 (stray 'pandoc-log.log' and
# '*-combined.pdf' files), and N6 (every kept path reported).

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# listing: the cwd's top-level entries (and those of any directory given), sorted, one
# line each, so an assertion can compare the whole set.
listing() {
  (cd "${1:-.}" && ls -A | LC_ALL=C sort | tr '\n' ' ')
}

@test "work directory: --single-page --title naming an input leaves that input untouched (B1)" {
  md2x_write_doc 'README.md' 'Readme Heading'
  md2x_write_doc 'two.md' 'Two Heading'
  local before
  before="$(cat README.md)"

  md2x_run -F html --single-page -t README README.md two.md

  assert_success
  assert_file_exists './README.md'
  assert_equal "$(cat README.md)" "${before}" 'README.md content'
  assert_file_exists './README.html'
  local run_input
  run_input="$(md2x_pandoc_capture input)"
  [[ "${run_input}" == *'Readme Heading'* ]] || md2x_fail "expected both documents in pandoc input, got: ${run_input}"
  [[ "${run_input}" == *'Two Heading'* ]] || md2x_fail "expected both documents in pandoc input, got: ${run_input}"
}

@test "work directory: a pre-existing input.md survives --single-page" {
  md2x_write_doc 'a.md' 'A Heading'
  md2x_write_doc 'b.md' 'B Heading'
  printf 'precious\n' > input.md

  md2x_run --single-page a.md b.md

  assert_success
  assert_equal "$(cat input.md)" 'precious' 'input.md content'
}

@test "work directory: html, pdf and --single-page pdf runs leave only the inputs and requested outputs" {
  md2x_write_doc 'a.md' 'A Heading'
  md2x_write_doc 'b.md' 'B Heading'
  mkdir out

  md2x_run -F html --output-path out a.md
  assert_success
  assert_equal "$(listing .)" 'a.md b.md out ' 'cwd after html'
  assert_equal "$(listing out)" 'a.html ' 'out after html'

  md2x_run -F pdf --output-path out b.md
  assert_success
  assert_equal "$(listing .)" 'a.md b.md out ' 'cwd after pdf'
  assert_equal "$(listing out)" 'a.html b.pdf ' 'out after pdf'

  md2x_run -F pdf --single-page -t both --output-path out a.md b.md
  assert_success
  assert_equal "$(listing .)" 'a.md b.md out ' 'cwd after single-page pdf'
  assert_equal "$(listing out)" 'a.html b.pdf both.pdf ' 'out after single-page pdf'
}

@test "work directory: TMPDIR is left empty after a successful run" {
  md2x_write_doc 'a.md'
  mkdir private-tmp

  TMPDIR="${PWD}/private-tmp" md2x_run a.md

  assert_success
  assert_equal "$(listing private-tmp)" '' 'TMPDIR after success'
}

@test "work directory: TMPDIR is left empty after a failed run" {
  md2x_write_doc 'a.md'
  mkdir private-tmp

  MD2X_TEST_STUB_EXIT_CODE=1 TMPDIR="${PWD}/private-tmp" md2x_run a.md

  assert_failure
  assert_equal "$(listing private-tmp)" '' 'TMPDIR after failure'
  # The failed run must not strand the pandoc log in the cwd either.
  assert_file_not_exists 'pandoc-log.log'
}

@test "work directory: a usage error creates no work directory" {
  mkdir private-tmp

  TMPDIR="${PWD}/private-tmp" md2x_run --bogus-option a.md

  assert_exit_status 2
  assert_equal "$(listing private-tmp)" '' 'TMPDIR after usage error'
}

@test "work directory: a TMPDIR with a trailing slash works" {
  md2x_write_doc 'a.md'
  mkdir private-tmp

  TMPDIR="${PWD}/private-tmp/" md2x_run --keep-intermediate -F html a.md

  assert_success
  local kept
  kept="$(md2x_kept_work_dir)"
  [[ "${kept}" == "${PWD}/private-tmp/md2x."* ]] || md2x_fail "unexpected work directory: ${kept}"
  [[ "${kept}" != *'//'* ]] || md2x_fail "work directory path has a doubled slash: ${kept}"
}

@test "work directory: --keep-intermediate names one directory holding css, log and overlay" {
  md2x_write_doc 'a.md'

  md2x_run --keep-intermediate a.md

  assert_success
  assert_equal "$(printf '%s\n' "${stderr}" | grep -c 'kept intermediate files in')" '1' 'notice count'
  local kept
  kept="$(md2x_kept_work_dir)"
  [[ -n "${kept}" ]] || md2x_fail "no kept-intermediate notice in stderr: ${stderr}"
  assert_dir_exists "${kept}"
  assert_file_exists "${kept}/github.css"
  assert_file_exists "${kept}/pandoc.log"
  assert_file_exists "${kept}/overlay.pdf"
  refute_output_contains 'kept intermediate'
}

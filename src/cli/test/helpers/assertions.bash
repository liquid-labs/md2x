#!/usr/bin/env bash
#
# Generic assertions for the md2x CLI test suite. Sourced by 'common.bash'; a test
# file should 'load' that rather than this file directly.
#
# Every assertion writes a diagnostic block to stderr and returns 1 on failure. bats
# runs test bodies under 'set -e', so a failing assertion fails the case.
#
# The assertions that read '$status', '$output' and '$stderr' work with both bats'
# built-in 'run' and the harness's 'md2x_run' wrapper (see common.bash).

# Print a failure diagnostic and return 1.
md2x_fail() {
  printf -- '-- md2x test assertion failed --\n' >&2
  printf '%s\n' "$@" >&2
  printf -- '--\n' >&2
  return 1
}

# Print '$status', '$output' and '$stderr' as diagnostic context.
md2x_report_run_context() {
  printf 'status: %s\n' "${status:-<unset>}" >&2
  printf 'stdout:\n%s\n' "${output:-}" >&2
  printf 'stderr:\n%s\n' "${stderr:-}" >&2
}

assert_success() {
  if [[ "${status:-0}" -ne 0 ]]; then
    md2x_report_run_context
    md2x_fail "expected command to succeed, but it exited ${status}"
  fi
}

# assert_failure [expected_status]
assert_failure() {
  local expected="${1:-}"
  if [[ "${status:-0}" -eq 0 ]]; then
    md2x_report_run_context
    md2x_fail 'expected command to fail, but it exited 0'
    return 1
  fi
  if [[ -n "${expected}" ]] && [[ "${status}" -ne "${expected}" ]]; then
    md2x_report_run_context
    md2x_fail "expected exit status ${expected}, got ${status}"
  fi
}

assert_exit_status() {
  local expected="$1"
  if [[ "${status:-}" != "${expected}" ]]; then
    md2x_report_run_context
    md2x_fail "expected exit status ${expected}, got ${status:-<unset>}"
  fi
}

assert_output_contains() {
  local needle="$1"
  if [[ "${output:-}" != *"${needle}"* ]]; then
    md2x_report_run_context
    md2x_fail "expected stdout to contain: ${needle}"
  fi
}

refute_output_contains() {
  local needle="$1"
  if [[ "${output:-}" == *"${needle}"* ]]; then
    md2x_report_run_context
    md2x_fail "expected stdout NOT to contain: ${needle}"
  fi
}

assert_output_equals() {
  local expected="$1"
  if [[ "${output:-}" != "${expected}" ]]; then
    md2x_report_run_context
    md2x_fail "expected stdout to equal: ${expected}"
  fi
}

assert_stderr_contains() {
  local needle="$1"
  if [[ "${stderr:-}" != *"${needle}"* ]]; then
    md2x_report_run_context
    md2x_fail "expected stderr to contain: ${needle}"
  fi
}

refute_stderr_contains() {
  local needle="$1"
  if [[ "${stderr:-}" == *"${needle}"* ]]; then
    md2x_report_run_context
    md2x_fail "expected stderr NOT to contain: ${needle}"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || md2x_fail "expected file to exist: ${path}" "cwd: ${PWD}"
}

assert_file_not_exists() {
  local path="$1"
  ! [[ -e "${path}" ]] || md2x_fail "expected file NOT to exist: ${path}" "cwd: ${PWD}"
}

assert_dir_exists() {
  local path="$1"
  [[ -d "${path}" ]] || md2x_fail "expected directory to exist: ${path}" "cwd: ${PWD}"
}

assert_file_contains() {
  local path="$1" needle="$2"
  assert_file_exists "${path}" || return 1
  local content
  content="$(cat -- "${path}")"
  if [[ "${content}" != *"${needle}"* ]]; then
    printf 'file content:\n%s\n' "${content}" >&2
    md2x_fail "expected '${path}' to contain: ${needle}"
  fi
}

# assert_equal <actual> <expected> [label]
assert_equal() {
  local actual="$1" expected="$2" label="${3:-value}"
  if [[ "${actual}" != "${expected}" ]]; then
    md2x_fail "expected ${label} to be '${expected}', got '${actual}'"
  fi
}

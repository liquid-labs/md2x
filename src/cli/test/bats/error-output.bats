#!/usr/bin/env bats
#
# Regression coverage for md2x's own error output and the exit-code contract (see
# 'src/cli/lib/errors.sh'): messages carry the 'md2x: ' prefix, never contain an ANSI
# escape off a TTY (bats is never a TTY), usage errors end with the --help hint, and a
# failing external tool maps to the runtime code (1) rather than leaking its own status.
# TTY color itself is not exercised here; it is checked manually.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

@test "a usage error's stderr contains no ANSI escape byte off a TTY" {
  md2x_write_doc 'report.md'

  md2x_run --toc --no-toc report.md

  assert_failure 2
  [[ "${stderr}" != *$'\033'* ]] \
    || md2x_fail "stderr contains an ESC byte off a TTY" "${stderr}"
}

@test "error lines start with 'md2x: '" {
  md2x_run no-such-file.md

  assert_failure 2
  # Other tooling (e.g. brew, via the option parser) may print its own noise to stderr,
  # so check the line carrying md2x's message rather than the first line.
  local line found=''
  while IFS= read -r line; do
    [[ "${line}" == *'is neither a file nor a directory'* ]] || continue
    found=1
    [[ "${line}" == "md2x: "* ]] \
      || md2x_fail "expected the error line to start with 'md2x: '" "${line}"
  done <<< "${stderr}"
  [[ -n "${found}" ]] || md2x_fail "error message not found in stderr" "${stderr}"
}

@test "a usage error prints the --help hint" {
  md2x_run --output-format bogus no-such.md

  assert_failure 2
  assert_stderr_contains "Try 'md2x --help' for more information."
}

@test "a pandoc stub exiting 64 makes md2x exit 1 and name the tool and input file" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_EXIT_CODE=64

  md2x_run --flatten-dirs --output-path . report.md

  assert_failure 1
  assert_stderr_contains "md2x: pandoc failed for 'report.md'"
}

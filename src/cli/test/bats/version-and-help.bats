#!/usr/bin/env bats
#
# '--version' (long-only, value injected from package.json at build time) and the contents
# of the '--help' text contract.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

package_version() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "${MD2X_REPO_ROOT}/package.json" | head -n 1
}

@test "--version prints 'md2x <package.json version>' and exits 0" {
  local expected
  expected="$(package_version)"
  [[ -n "${expected}" ]]

  md2x_run --version

  assert_success
  assert_equal "${output}" "md2x ${expected}"
}

@test "--version works with every preflight binary off PATH" {
  local expected
  expected="$(package_version)"
  # PATH holds only bash and the few coreutils the option parser itself needs: no pandoc,
  # gs, pdftk, python3, or jq (and, on most systems, no 'getopt' either).
  local bare_dir="${PWD}/bare-bin" tool
  mkdir -p "${bare_dir}"
  for tool in bash mktemp rm cat; do
    ln -s "$(command -v "${tool}")" "${bare_dir}/${tool}"
  done
  # Capture directly rather than through 'md2x_run', whose stderr filtering needs other tools.
  local out rc=0
  out="$(PATH="${bare_dir}" md2x_exec --version 2>/dev/null)" || rc=$?

  assert_equal "${rc}" 0
  assert_equal "${out}" "md2x ${expected}"
}

@test "--help with --version prints help" {
  md2x_run --help --version

  assert_success
  assert_output_contains 'Usage:'
  assert_output_contains 'Exit codes:'
}

@test "--version --help prints help" {
  md2x_run --version --help

  assert_success
  assert_output_contains 'Usage:'
}

@test "-v is a usage error with exit 2" {
  md2x_run -v

  assert_failure 2
}

@test "-V is a usage error with exit 2" {
  md2x_run -V

  assert_failure 2
}

@test "--help lists --version, the exit codes, and the homepage" {
  md2x_run --help

  assert_success
  assert_output_contains '      --version'
  assert_output_contains 'Exit codes:'
  assert_output_contains '  0  Success.'
  assert_output_contains '  1  Runtime or conversion failure.'
  assert_output_contains '  2  Usage error'
  assert_output_contains '  3  Missing or unusable dependency'
  assert_output_contains 'https://github.com/liquid-labs/md2x'
}

@test "--help does not claim other Pandoc-supported formats" {
  md2x_run --help

  assert_success
  if [[ "${output}" == *'other Pandoc'* ]]; then
    md2x_fail "help still mentions 'other Pandoc'"
  fi
}

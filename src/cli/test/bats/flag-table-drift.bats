#!/usr/bin/env bats
#
# Flag-table drift: the set of '(short, long)' flag pairs must be identical across the
# option parser's definition table ('MD2X_OPTION_TABLE'), 'md2x --help', and the README
# CLI reference table; and the spec must link to that README table rather than carry a
# flag table of its own. Nothing is hardcoded: the three sources are compared with each
# other. The drift cases run the same comparison against deliberately broken temp copies
# to prove the test would catch a real divergence.

load '../helpers/common'
load '../helpers/flag-table'

setup() {
  md2x_setup
  PARSER_SRC="${MD2X_REPO_ROOT}/src/cli/lib/parse-options.sh"
  README_SRC="${MD2X_REPO_ROOT}/README.md"
  SPEC_SRC="${MD2X_REPO_ROOT}/docs/md2x-spec.md"
  SETS_DIR="${MD2X_TEST_TMPDIR}/flag-sets"
  mkdir -p "${SETS_DIR}"
}

teardown() {
  rm -rf "${SETS_DIR}"
  md2x_teardown
}

# Writes the three pair files, optionally from substitute inputs:
#   collect_sets [readme-file] [help-file]
collect_sets() {
  local readme="${1:-${README_SRC}}" help_file="${2:-}"
  flag_pairs_from_parser "${PARSER_SRC}" > "${SETS_DIR}/parser"
  flag_pairs_from_readme "${readme}" > "${SETS_DIR}/readme"
  if [[ -n "${help_file}" ]]; then
    flag_pairs_from_help < "${help_file}" > "${SETS_DIR}/help"
  else
    md2x_run --help
    [[ "${status}" -eq 0 ]] || { echo "md2x --help failed: ${output}"; return 1; }
    printf '%s\n' "${output}" | flag_pairs_from_help > "${SETS_DIR}/help"
  fi
}

# Compares all three sets; prints a drift report and returns 1 on any disagreement.
compare_all() {
  local rc=0
  flag_sets_compare 'parser table' "${SETS_DIR}/parser" '--help' "${SETS_DIR}/help" || rc=1
  flag_sets_compare 'parser table' "${SETS_DIR}/parser" 'README table' "${SETS_DIR}/readme" || rc=1
  return "${rc}"
}

@test "extraction sanity: the parser set is non-empty and includes --help, --version, and -o" {
  collect_sets
  [[ -s "${SETS_DIR}/parser" ]]
  grep -qx -- '-h,--help' "${SETS_DIR}/parser"
  grep -qx -- ',--version' "${SETS_DIR}/parser"
  grep -qx -- '-o,--output' "${SETS_DIR}/parser"
  ! grep -q MALFORMED "${SETS_DIR}/parser" "${SETS_DIR}/help" "${SETS_DIR}/readme"
}

@test "the parser table, 'md2x --help', and the README CLI table list the same (short, long) pairs" {
  collect_sets
  run compare_all
  echo "${output}"
  assert_success
}

@test "drift: a bogus row in a README copy is reported as missing from the parser table" {
  awk '/^\| `--toc` \|/ { print "| `-Z`, `--bogus-flag` | Not real. |" } { print }' "${README_SRC}" > "${SETS_DIR}/README.drift.md"
  grep -q -- '--bogus-flag' "${SETS_DIR}/README.drift.md"
  collect_sets "${SETS_DIR}/README.drift.md"
  run compare_all
  assert_failure
  assert_output_contains 'in README table but missing from parser table'
  assert_output_contains '-Z,--bogus-flag'
}

@test "drift: a README copy missing a flag row is reported as missing from the README table" {
  grep -v '^| `--quiet` |' "${README_SRC}" > "${SETS_DIR}/README.drift.md"
  collect_sets "${SETS_DIR}/README.drift.md"
  run compare_all
  assert_failure
  assert_output_contains 'in parser table but missing from README table'
  assert_output_contains ',--quiet'
}

@test "drift: a flag removed from a help copy is reported as missing from --help" {
  md2x_run --help
  assert_success
  printf '%s\n' "${output}" | grep -v -e '^  -s, --to-stdout' > "${SETS_DIR}/help.drift.txt"
  collect_sets '' "${SETS_DIR}/help.drift.txt"
  run compare_all
  assert_failure
  assert_output_contains 'in parser table but missing from --help'
  assert_output_contains '-s,--to-stdout'
}

@test "drift: a changed short flag in a README copy is a pair mismatch" {
  sed 's/^| `-t`, `--title/| `-T`, `--title/' "${README_SRC}" > "${SETS_DIR}/README.drift.md"
  collect_sets "${SETS_DIR}/README.drift.md"
  run compare_all
  assert_failure
  assert_output_contains '-T,--title'
}

@test "the spec links to the README CLI reference and carries no flag table of its own" {
  grep -q '(\.\./README\.md#cli-reference)' "${SPEC_SRC}"
  run spec_flag_table_rows "${SPEC_SRC}"
  assert_success
  [[ -z "${output}" ]] || { echo "spec carries flag-table rows:"; echo "${output}"; false; }
}

@test "drift: a spec copy with a flag-table row is detected" {
  { cat "${SPEC_SRC}"; printf '\n| `--quiet` | Suppress output. |\n'; } > "${SETS_DIR}/spec.drift.md"
  run spec_flag_table_rows "${SETS_DIR}/spec.drift.md"
  [[ -n "${output}" ]]
}

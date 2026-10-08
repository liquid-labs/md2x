#!/usr/bin/env bats
#
# Unit coverage for 'md2x-percent-encode' (src/cli/lib/link-filter.sh), which encodes the
# directory and source names carried in the '--single-page' source markers. Each case runs
# the function in a fresh interpreter ("${MD2X_TEST_BASH:-bash}", so '/bin/bash' 3.2 on
# macOS exercises the 'printf -v' forms the function relies on) and compares the result
# with an independent oracle written in Python.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# pe_encode <bash-printf-format>: runs 'md2x-percent-encode' on the bytes the format yields.
pe_encode() {
  "${MD2X_TEST_BASH:-bash}" -c '
    source "$1/src/cli/lib/link-filter.sh"
    printf -v INPUT "$2"
    md2x-percent-encode "${INPUT}"' pe "${MD2X_REPO_ROOT}" "$1"
}

@test "percent-encode: every byte value but NUL (which no bash string can hold) matches the oracle" {
  # One line per byte: '<two hex digits> <encoded>'. Byte 0x0a is a newline in the input;
  # the function reads it through 'od', so it needs no special handling.
  local actual expected
  actual="$("${MD2X_TEST_BASH:-bash}" -c '
    source "$1/src/cli/lib/link-filter.sh"
    for (( I = 1; I < 256; I++ )); do
      printf -v HEX "%02x" "${I}"
      printf -v INPUT "\\x${HEX}"
      printf "%s %s\n" "${HEX}" "$(md2x-percent-encode "${INPUT}")"
    done' pe "${MD2X_REPO_ROOT}")"
  expected="$(python3 -c '
import re
for i in range(1, 256):
    c = chr(i)
    print("%02x %s" % (i, c if re.fullmatch(r"[A-Za-z0-9_./]", c) else "%%%02X" % i))')"
  assert_equal "${actual}" "${expected}" 'per-byte encoding'
}

@test "percent-encode: no output byte is a space, newline, '-' or '>'" {
  local all='' i hex
  for (( i = 1; i < 256; i++ )); do
    printf -v hex '%02x' "${i}"
    all="${all}\\x${hex}"
  done
  local out
  out="$(pe_encode "${all}")"
  [[ "${out}" != *' '* ]] || md2x_fail "space in output: ${out}"
  [[ "${out}" != *$'\n'* ]] || md2x_fail "newline in output"
  [[ "${out}" != *'-'* ]] || md2x_fail "'-' in output: ${out}"
  [[ "${out}" != *'>'* ]] || md2x_fail "'>' in output: ${out}"
}

@test "percent-encode: multibyte UTF-8, space, '-', '>' and newline are escaped; the safe set passes through" {
  assert_equal "$(pe_encode 'caf\303\251')" 'caf%C3%A9' 'two-byte UTF-8'
  assert_equal "$(pe_encode '\342\202\254')" '%E2%82%AC' 'three-byte UTF-8'
  assert_equal "$(pe_encode 'a b')" 'a%20b' 'space'
  assert_equal "$(pe_encode 'a-->b')" 'a%2D%2D%3Eb' 'comment terminator'
  assert_equal "$(pe_encode 'a\nb')" 'a%0Ab' 'newline'
  assert_equal "$(pe_encode '/Az_09./x')" '/Az_09./x' 'safe set'
  assert_equal "$(pe_encode '')" '' 'empty'
}

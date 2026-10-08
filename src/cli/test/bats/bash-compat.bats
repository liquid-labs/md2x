#!/usr/bin/env bats
#
# Bash-version compatibility of the built CLI: md2x supports bash 3.2 (macOS's
# /bin/bash) and later, and refuses to start under anything else.
#
# Two groups:
#
#   * The interpreter guard at the very top of 'src/cli/md2x.sh' (exit 3 for a shell that
#     is not bash, bash older than 3.2, and bash in POSIX mode). These always run the CLI
#     under the interpreter named in the case, regardless of 'MD2X_TEST_BASH'.
#   * Conversions under a bash 3.x ('MD2X_TEST_BASH' when it names a 3.x bash, else
#     '/bin/bash' when that is 3.x; skipped when neither is). Before the 3.2 fixes these
#     died on a parse error and still exited 0 with no output.
#
# See 'common.bash' for 'MD2X_TEST_BASH'.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# compat_run <command>...
# Runs the command with the CLI's stdout/stderr captured; sets '$status' and '$stderr'.
compat_run() {
  status=0
  "$@" > "${MD2X_TEST_TMPDIR}/compat-stdout" 2> "${MD2X_TEST_TMPDIR}/compat-stderr" || status=$?
  stderr="$(cat -- "${MD2X_TEST_TMPDIR}/compat-stderr")"
}

# compat_bash3
# Prints the path of a bash 3.x interpreter to test under, or nothing when there is none.
compat_bash3() {
  local candidate version
  for candidate in "${MD2X_TEST_BASH:-}" /bin/bash; do
    [[ -n "${candidate}" ]] && [[ -x "${candidate}" ]] || continue
    version="$("${candidate}" -c 'printf %s "${BASH_VERSION}"' 2>/dev/null || true)"
    if [[ "${version}" == 3.* ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    # An explicit override names the interpreter under test; do not fall back past it.
    [[ -z "${MD2X_TEST_BASH:-}" ]] || return 0
  done
}

# compat_require_bash3: sets 'BASH3' or skips the case.
compat_require_bash3() {
  BASH3="$(compat_bash3)"
  [[ -n "${BASH3}" ]] || skip "no bash 3.x available (set MD2X_TEST_BASH or use macOS /bin/bash)"
}

# --- interpreter guard ---------------------------------------------------------------

@test "guard: dash exits 3 with the bash-requirement message" {
  local dash_bin
  dash_bin="$(command -v dash || true)"
  [[ -n "${dash_bin}" ]] || skip "dash is not installed"

  compat_run "${dash_bin}" "${MD2X_BIN}" --help

  assert_exit_status 3
  assert_stderr_contains 'md2x: requires bash 3.2 or later'
  assert_stderr_contains 'not bash'
}

@test "guard: running it with 'sh' exits 3 (non-bash sh, or bash in POSIX mode)" {
  compat_run sh "${MD2X_BIN}" --help

  assert_exit_status 3
  assert_stderr_contains 'md2x: requires bash 3.2 or later'
}

@test "guard: bash in POSIX mode exits 3 and says to run it with bash" {
  local real_bash
  real_bash="$(PATH="${MD2X_TEST_ORIGINAL_PATH}" command -v bash)"

  compat_run "${real_bash}" --posix "${MD2X_BIN}" --help

  assert_exit_status 3
  assert_stderr_contains 'md2x: requires bash 3.2 or later'
  assert_stderr_contains 'POSIX mode'
  assert_stderr_contains 'Run it with bash'
}

@test "guard: the guard text is the first thing in the built CLI, ahead of strict mode and toolkit code" {
  local guard_line set_line first_function_line
  guard_line="$(grep -n '^if \[ -z "\${BASH_VERSION' "${MD2X_BIN}" | head -n 1 | cut -d: -f1)"
  set_line="$(grep -n '^set -o' "${MD2X_BIN}" | head -n 1 | cut -d: -f1)"
  first_function_line="$(grep -n '^[A-Za-z_-]*() {' "${MD2X_BIN}" | head -n 1 | cut -d: -f1)"

  [[ -n "${guard_line}" ]] && [[ -n "${set_line}" ]] && [[ -n "${first_function_line}" ]] \
    || md2x_fail "could not locate the guard, strict-mode and first function lines"
  (( guard_line < set_line )) || md2x_fail "guard (line ${guard_line}) is not before 'set' (line ${set_line})"
  (( guard_line < first_function_line )) \
    || md2x_fail "guard (line ${guard_line}) is not before the inlined toolkit code (line ${first_function_line})"
}

# --- conversions under bash 3.x ------------------------------------------------------

@test "bash 3.x: an html conversion succeeds and writes its output" {
  compat_require_bash3
  md2x_write_doc 'report.md'

  compat_run "${BASH3}" "${MD2X_BIN}" --output-format html --flatten-dirs --output-path . report.md

  assert_exit_status 0
  assert_file_exists './report.html'
}

@test "bash 3.x: a docx conversion succeeds (empty INCLUDE_BODY_ARGS under nounset) and writes its output" {
  compat_require_bash3
  md2x_write_doc 'report.md'

  compat_run "${BASH3}" "${MD2X_BIN}" --output-format docx --flatten-dirs --output-path . report.md

  assert_exit_status 0
  assert_file_exists './report.docx'
}

@test "bash 3.x: a directory conversion through the file-discovery process substitution succeeds" {
  compat_require_bash3
  md2x_make_fixture_tree docs > /dev/null

  compat_run "${BASH3}" "${MD2X_BIN}" --output-format html --output-path out docs

  assert_exit_status 0
  assert_file_exists 'out/alpha.html'
  assert_file_exists 'out/nested/beta.html'
}

@test "bash 3.x: a failing pandoc exits 1, not 0" {
  compat_require_bash3
  md2x_write_doc 'report.md'

  MD2X_TEST_STUB_EXIT_CODE=1 compat_run "${BASH3}" "${MD2X_BIN}" --output-format html --flatten-dirs --output-path . report.md

  assert_exit_status 1
  assert_stderr_contains "pandoc failed for 'report.md'"
}

@test "any bash: a failing pandoc exits 1" {
  md2x_write_doc 'report.md'

  MD2X_TEST_STUB_EXIT_CODE=1 md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_failure 1
  assert_stderr_contains "pandoc failed for 'report.md'"
}

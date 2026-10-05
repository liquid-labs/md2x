#!/usr/bin/env bats
#
# Regression coverage for md2x's own option parser ('src/cli/lib/parse-options.sh'): the
# explicit flag table (the single '-s' means '--to-stdout'; no auto-derived shorts), friendly
# getopt errors with the usage hint, help that works without GNU getopt or 'brew', the
# 'MD2X_GETOPT' override and its dependency error, and the GNU getopt semantics md2x keeps
# (unambiguous long-option prefixes, '--opt=value', an attached short value, '--').
#
# The harness PATH deliberately has no 'brew' (see 'MD2X_TEST_PASSTHROUGH_TOOLS' in
# 'helpers/common.bash'), so every case here also proves the CLI finds GNU getopt without it.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# Fails unless stderr is a single-line friendly usage error: an 'md2x: ' line, the usage
# hint, and no raw 'getopt:' text.
assert_friendly_usage_error() {
  assert_failure 2
  assert_stderr_contains 'md2x: '
  assert_stderr_contains "Try 'md2x --help' for more information."
  refute_stderr_contains 'getopt:'
}

# --- the short-flag table ------------------------------------------------------------

@test "harness precondition: brew is not on PATH" {
  ! command -v brew >/dev/null 2>&1 \
    || md2x_fail "'brew' is reachable on the case's PATH: $(command -v brew)"
}

@test "-s writes to stdout (--to-stdout) and does not enter single-page mode" {
  md2x_write_doc 'report.md' 'Piped Report'

  md2x_run -s --output-format html report.md

  assert_success
  assert_output_contains 'md2x-test-stub: pandoc output'
  # '--single-page' (the old meaning of '-s') would have written 'output.html'.
  assert_file_not_exists './output.html'
}

@test "-D maps to --flatten-dirs" {
  md2x_make_fixture_tree 'tree' >/dev/null

  md2x_run -D -F html -p out tree

  assert_success
  assert_file_exists './out/alpha.html'
  assert_file_exists './out/beta.html'
}

@test "-F maps to --output-format" {
  md2x_write_doc 'report.md'

  md2x_run -F html -p . report.md

  assert_success
  assert_file_exists './report.html'
}

@test "-p maps to --output-path" {
  md2x_write_doc 'report.md'

  md2x_run -F html -p dest report.md

  assert_success
  assert_file_exists './dest/report.html'
}

@test "-t maps to --title" {
  md2x_write_doc 'report.md'

  md2x_run -t Foo -F html -p . report.md

  assert_success
  assert_file_exists './Foo.html'
}

@test "-h maps to --help" {
  md2x_run -h

  assert_success
  assert_output_contains 'Usage:'
}

@test "the removed auto-shorts -q, -l, -n, and -i are usage errors" {
  md2x_write_doc 'report.md'
  local flag
  for flag in -q -l -n -i; do
    md2x_run "${flag}" report.md
    assert_friendly_usage_error
    assert_stderr_contains "unrecognized option '${flag}'"
  done
}

# --- friendly errors -----------------------------------------------------------------

@test "an unknown long option is a friendly usage error" {
  md2x_run --foo report.md

  assert_friendly_usage_error
  assert_stderr_contains "unrecognized option '--foo'"
}

@test "a missing option argument is a friendly usage error" {
  md2x_run --title

  assert_friendly_usage_error
  assert_stderr_contains 'requires an argument'
}

@test "an ambiguous long-option prefix is a friendly usage error" {
  md2x_write_doc 'report.md'

  md2x_run --t report.md

  assert_friendly_usage_error
  assert_stderr_contains 'ambiguous'
}

# --- help and the getopt dependency --------------------------------------------------

@test "--help exits 0 with brew absent from PATH" {
  ! command -v brew >/dev/null 2>&1 \
    || md2x_fail "'brew' is reachable on the case's PATH: $(command -v brew)"

  md2x_run --help

  assert_success
  assert_output_contains 'Usage:'
}

@test "--help exits 0 when MD2X_GETOPT is not GNU getopt" {
  MD2X_GETOPT=/usr/bin/getopt md2x_run --help

  assert_success
  assert_output_contains 'Usage:'
}

@test "--help exits 0 when MD2X_GETOPT does not exist" {
  MD2X_GETOPT="${MD2X_TEST_TMPDIR}/no-such-getopt" md2x_run --help

  assert_success
  assert_output_contains 'Usage:'
}

@test "-h also works without a usable getopt" {
  MD2X_GETOPT="${MD2X_TEST_TMPDIR}/no-such-getopt" md2x_run -h

  assert_success
  assert_output_contains 'Usage:'
}

@test "a conversion with a nonexistent MD2X_GETOPT exits 3 and names gnu-getopt" {
  md2x_write_doc 'report.md'

  MD2X_GETOPT="${MD2X_TEST_TMPDIR}/no-such-getopt" md2x_run report.md

  assert_failure 3
  assert_stderr_contains 'MD2X_GETOPT'
  assert_stderr_contains 'gnu-getopt'
}

@test "a conversion with MD2X_GETOPT set to a non-GNU getopt exits 3 and names gnu-getopt" {
  md2x_write_doc 'report.md'

  # Linux's /usr/bin/getopt is GNU (util-linux); the case only applies where it is not.
  local rc=0
  /usr/bin/getopt --test >/dev/null 2>&1 || rc=$?
  [[ "${rc}" -ne 4 ]] || skip '/usr/bin/getopt is GNU getopt on this host'

  MD2X_GETOPT=/usr/bin/getopt md2x_run report.md

  assert_failure 3
  assert_stderr_contains 'gnu-getopt'
}

@test "MD2X_GETOPT pointing at GNU getopt is honored" {
  local gnu=''
  local candidate
  for candidate in /opt/homebrew/opt/gnu-getopt/bin/getopt /usr/local/opt/gnu-getopt/bin/getopt \
                   /opt/local/bin/getopt /usr/bin/getopt; do
    [[ -x "${candidate}" ]] || continue
    local rc=0
    "${candidate}" --test >/dev/null 2>&1 || rc=$?
    if [[ "${rc}" -eq 4 ]]; then gnu="${candidate}"; break; fi
  done
  [[ -n "${gnu}" ]] || skip 'no GNU getopt on this host'
  md2x_write_doc 'report.md'

  MD2X_GETOPT="${gnu}" md2x_run -F html -p . report.md

  assert_success
  assert_file_exists './report.html'
}

# --- GNU getopt semantics that are kept ----------------------------------------------

@test "an unambiguous long-option prefix works: --single means --single-page" {
  md2x_write_doc 'one.md'
  md2x_write_doc 'two.md'

  md2x_run --single --title Combined -F html -p . one.md two.md

  assert_success
  assert_file_exists './Combined.html'
  assert_equal "$(md2x_pandoc_capture_count)" '1' 'pandoc invocation count'
}

@test "--no resolves to --no-toc" {
  md2x_write_doc 'report.md'

  md2x_run --no --toc report.md

  assert_failure 2
  assert_stderr_contains "Cannot specify both '--toc' and '--no-toc'"
}

@test "-p=x sets the output path to '=x'" {
  md2x_write_doc 'report.md'

  md2x_run -F html -p=x report.md

  assert_success
  assert_file_exists './=x/report.html'
}

@test "--opt=value works" {
  md2x_write_doc 'report.md'

  md2x_run --output-format=html --output-path=dest report.md

  assert_success
  assert_file_exists './dest/report.html'
}

@test "options are permuted after positional arguments" {
  md2x_write_doc 'report.md'

  md2x_run report.md -F html -p dest

  assert_success
  assert_file_exists './dest/report.html'
}

@test "-- ends option parsing" {
  md2x_run -- --not-an-option

  assert_failure 2
  assert_stderr_contains "'--not-an-option' is neither a file nor a directory"
}

@test "--title -h x.md takes -h as the title value, not a help request" {
  md2x_write_doc 'x.md'

  md2x_run --title -h -F html -p . x.md

  assert_success
  assert_file_exists './-h.html'
  refute_output_contains 'Usage:'
}

@test "--title -h is not a help request without a usable getopt either" {
  md2x_write_doc 'x.md'

  MD2X_GETOPT="${MD2X_TEST_TMPDIR}/no-such-getopt" md2x_run --title -h x.md

  assert_failure 3
  refute_output_contains 'Usage:'
}

#!/usr/bin/env bats
#
# '--title' is untrusted text that reaches three sinks: the output file name, pandoc's
# title metadata, and the PostScript program Ghostscript runs for the header/footer
# overlay. See 'lib/title-safe.sh'.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- filename sink: rejected titles --------------------------------------------------

# title_reject_case <mode> <title>
# Runs a conversion in <mode> (file|single|stdin) with the title and asserts exit 2 with
# the usage hint, no output file, and no pandoc invocation.
title_reject_case() {
  local mode="$1" title="$2"
  md2x_write_doc 'report.md'
  case "${mode}" in
    file) md2x_run --title "${title}" --output-path out report.md;;
    single) md2x_run --single-page --title "${title}" --output-path out report.md;;
    stdin) md2x_run --title "${title}" --output-path out - <<< '# Heading';;
  esac
  assert_failure 2
  assert_stderr_contains "cannot be used as a file name"
  assert_stderr_contains "Try 'md2x --help' for more information."
  refute_stub_called pandoc
  [[ ! -e out ]] || md2x_fail "expected no output directory, found: $(ls -A out)"
  [[ -z "$(ls -A . | grep -v '^report.md$' || true)" ]] \
    || md2x_fail "expected no stray files, found: $(ls -A .)"
}

@test "--title '' is a usage error in file, --single-page and stdin modes" {
  title_reject_case file ''
  title_reject_case single ''
  title_reject_case stdin ''
}

@test "--title . is a usage error in file, --single-page and stdin modes" {
  title_reject_case file '.'
  title_reject_case single '.'
  title_reject_case stdin '.'
}

@test "--title .. is a usage error in file, --single-page and stdin modes" {
  title_reject_case file '..'
  title_reject_case single '..'
  title_reject_case stdin '..'
}

@test "--title containing a slash is a usage error in file, --single-page and stdin modes" {
  title_reject_case file 'a/b'
  title_reject_case single 'a/b'
  title_reject_case stdin 'a/b'
}

@test "--title containing a control character is a usage error in file, --single-page and stdin modes" {
  local ctl
  ctl="$(printf 'a\tb')"
  title_reject_case file "${ctl}"
  title_reject_case single "${ctl}"
  title_reject_case stdin "${ctl}"
}

# --- filename sink: accepted titles --------------------------------------------------

@test "--title with PostScript/shell-special characters names the output file literally" {
  md2x_write_doc 'report.md'

  md2x_run --output-format html --title 'O(x)\y' --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './O(x)\y.html'
}

@test "--title with printable non-ASCII names the output file literally (LC_ALL=C)" {
  md2x_write_doc 'report.md'

  LC_ALL=C md2x_run --output-format html --title 'Ünïcødé 日本' --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './Ünïcødé 日本.html'
}

@test "--title with printable non-ASCII names the output file literally (UTF-8 locale)" {
  md2x_write_doc 'report.md'

  local utf8
  utf8="$(locale -a 2>/dev/null | grep -i -m1 'utf-\?8' || true)"
  [[ -n "${utf8}" ]] || skip 'no UTF-8 locale installed'
  LC_ALL="${utf8}" md2x_run --output-format html --title 'Ünïcødé 日本' --flatten-dirs --output-path . report.md

  assert_success
  assert_file_exists './Ünïcødé 日本.html'
}

@test "--title with quotes, colon, asterisk and spaces is accepted in stdin mode" {
  md2x_run --output-format html --output-path . --title "it's \"a\": *b* c" - <<< '# Heading'

  assert_success
  assert_file_exists "./it's \"a\": *b* c.html"
}

# --- metadata sink -------------------------------------------------------------------

@test "--infer-title passes exactly one -M argument carrying the literal title" {
  md2x_write_doc 'report.md'
  local title="O'Brien: *x* (a)b \\ \"q\""

  md2x_run --infer-title --title "${title}" --flatten-dirs --output-path . report.md

  assert_success
  assert_last_call_has_arg pandoc "title=${title}"
  refute_last_call_contains pandoc '--metadata-file'
  local count
  count="$(md2x_stub_last_call_args pandoc | grep -c '^-M$' || true)"
  assert_equal "${count}" '1' '-M argument count'
}

# --- PostScript sink -----------------------------------------------------------------

@test "md2x-ps-string escapes backslash and parens, strips controls, keeps non-ASCII" {
  # shellcheck source=/dev/null
  source "${MD2X_REPO_ROOT}/src/cli/lib/title-safe.sh"
  local input expected actual
  input="$(printf 'a\\b(c)d\001\037\177e\tf\n\303\251')"
  expected="$(printf 'a\\\\b\\(c\\)de' ; printf 'f\303\251')"
  actual="$(md2x-ps-string "${input}")"
  [[ "${actual}" == "${expected}" ]] \
    || md2x_fail "expected '${expected}', got '${actual}'"
  [[ "$(printf '%s' "${actual}" | od -An -tx1 | tr -d ' \n')" == "$(printf '%s' "${expected}" | od -An -tx1 | tr -d ' \n')" ]]
}

@test "the gs overlay program carries the escaped title" {
  md2x_write_doc 'report.md'

  md2x_run --title 'a)b' --flatten-dirs --output-path . report.md

  assert_success
  assert_any_call_contains gs 'a\)b'
  refute_any_call_contains gs ' a)b '
}

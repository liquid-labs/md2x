#!/usr/bin/env bats
#
# Behavioural coverage for 'generate-page()'s CSS delivery and stderr handling
# (plan/phase-01-restore-pdf-styling/001-fix-css-delivery-and-stream-handling.md):
#
#   * the bundled stylesheet is handed to pandoc as a real '.css' temp file (so
#     WeasyPrint, the pinned '--pdf-engine', can MIME-sniff it), never as a
#     '/dev/fd/*' process-substitution path.
#   * pandoc's (and, transitively, WeasyPrint's) stderr output flows to the CLI's own
#     real stderr untouched -- it never leaks onto the CLI's real stdout (the parsed
#     '--to-stdout'/'--list-files' data channel), and a non-zero pandoc/WeasyPrint exit
#     still propagates as a non-zero md2x exit rather than being silently swallowed.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- stderr never leaks onto real stdout ---------------------------------------------

@test "pandoc stderr noise never leaks onto stdout with --list-files" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_STDERR='Loading pages (3/6)
WARNING: Unsupported stylesheet type
Done'

  md2x_run --list-files --flatten-dirs --output-path . report.md

  assert_success
  assert_output_equals './report.pdf'
  refute_output_contains 'Loading pages'
  refute_output_contains 'Unsupported stylesheet type'
  assert_stderr_contains 'Loading pages (3/6)'
  assert_stderr_contains 'Unsupported stylesheet type'
}

@test "pandoc stderr noise never leaks onto stdout with --to-stdout" {
  # Use 'html' output: for pdf output the CLI overwrites the base output with the
  # pdftk-merged content before 'cat'-ing it, so a non-pdf format's stdout is the one
  # that still carries the pandoc stub's own placeholder verbatim (see
  # output-shaping.bats's '--to-stdout' case for the same rationale).
  md2x_write_doc 'report.md' 'Piped Report'
  export MD2X_TEST_STUB_STDERR='WARNING: some WeasyPrint chatter'

  md2x_run --to-stdout --output-format html --flatten-dirs --output-path . report.md

  assert_success
  assert_output_contains 'md2x-test-stub: pandoc output'
  refute_output_contains 'WARNING: some WeasyPrint chatter'
  assert_stderr_contains 'WARNING: some WeasyPrint chatter'
}

# --- a genuine pandoc/WeasyPrint failure still propagates -----------------------------

@test "a non-zero pandoc exit still fails the md2x invocation" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_EXIT_CODE=1
  export MD2X_TEST_STUB_STDERR='ERROR: fatal WeasyPrint failure'

  md2x_run --flatten-dirs --output-path . report.md

  assert_failure
  assert_stderr_contains 'ERROR: fatal WeasyPrint failure'
}

# --- '--css' is a real, MIME-sniffable file, never a process substitution ------------

@test "--css is a real path ending in '.css', never a '/dev/fd/*' process substitution" {
  md2x_write_doc 'report.md'

  md2x_run --flatten-dirs --output-path . report.md

  assert_success
  # '--metadata-file' and the (link-rewritten) input document are still legitimately
  # delivered via process substitution -- out of this task's scope -- so assert on the
  # '--css' argument's own value specifically, not the whole invocation line.
  local css_arg previous='' found=''
  while IFS= read -r css_arg; do
    if [[ "${previous}" == '--css' ]]; then
      found="${css_arg}"
      break
    fi
    previous="${css_arg}"
  done < <(md2x_stub_last_call_args pandoc)
  [[ -n "${found}" ]] || md2x_fail 'expected the last pandoc invocation to include a --css argument'
  [[ "${found}" == *'.css' ]] \
    || md2x_fail "expected the --css argument to end in .css, got: ${found}"
  [[ "${found}" != '/dev/fd/'* ]] \
    || md2x_fail "expected the --css argument NOT to be a /dev/fd/* process substitution, got: ${found}"

  # 'src/cli/lib/generate-page.sh's CSS variable is a bash-rollup directive
  # ('source ./github.css # bash-rollup-no-recur') that the rollup step inlines with
  # the real stylesheet's content, so assert on a marker from the bundled stylesheet
  # itself rather than the (build-time-only) source reference.
  local css_content
  css_content="$(md2x_pandoc_capture css)"
  [[ "${css_content}" == *'markdown-body'* ]] \
    || md2x_fail "expected captured CSS to contain the bundled stylesheet's content, got: ${css_content}"
}

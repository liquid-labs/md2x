#!/usr/bin/env bats
#
# True end-to-end cases: run the built md2x CLI against the REAL pandoc/gs/pdftk on
# this machine's PATH -- not the stub executables the rest of the suite (see
# 'harness-smoke.bats' and the sibling behavioural '*.bats' files) deliberately
# substitutes in for speed and determinism. This file is the fidelity backstop for
# that trade-off; see '../../../plan/notes/test-tooling-survey.md'.
#
# These cases never call 'md2x_use_stub_path' / 'md2x_setup' and never put
# 'MD2X_STUB_DIR' on PATH -- that is the whole point of this file, so it is called out
# explicitly here and guarded in 'e2e_setup' below, rather than left implicit.
#
# Gating is per-capability, not per-binary:
#   * HTML/DOCX cases only need 'pandoc' resolvable on the ambient PATH.
#   * The PDF case additionally needs pandoc's HTML5-to-PDF path to have a working
#     external "pdf engine" available -- specifically md2x's self-managed
#     '~/.md2x/venv/bin/weasyprint' (see ensure-weasyprint.sh), the absolute path md2x
#     itself invokes; a bare 'weasyprint' on PATH is deliberately never assumed. 'pandoc'
#     being on PATH does not imply that engine is present, so the PDF case is gated on a
#     throwaway probe conversion against that same binary, not a binary-presence check.
#     The probe (and thus the case) skips, naming what's missing, when the managed
#     venv/binary has not been bootstrapped on the machine running the suite.
# A skipped case reports as skipped (with a message naming what was missing) and does
# not affect the suite's exit status; a run case exercises the real toolchain and its
# assertions must hold for real.

load '../helpers/common'

setup() {
  e2e_setup
}

teardown() {
  e2e_teardown
}

# --- local setup/teardown ------------------------------------------------------------
#
# Deliberately NOT 'md2x_setup': that helper installs the stub 'pandoc'/'gs'/'pdftk' on
# PATH via 'md2x_use_stub_path', which is exactly what these cases must not use. This
# reimplements just the parts of 'md2x_setup' these cases still need (a private,
# outside-the-repo working directory) and otherwise leaves PATH as inherited from the
# environment running the suite.

e2e_setup() {
  if ! [[ -x "${MD2X_BIN}" ]]; then
    md2x_fail "built CLI not found at '${MD2X_BIN}'" \
      "run 'make all' (or 'make test', which depends on it) before running bats directly"
    return 1
  fi

  # Guard against accidental stub-PATH leakage from another case: these e2e cases must
  # run against the real toolchain, never the stubs.
  if [[ ":${PATH}:" == *":${MD2X_STUB_DIR}:"* ]]; then
    md2x_fail "stub directory is on PATH: ${MD2X_STUB_DIR}" \
      'this e2e file must run against the real toolchain, not the stubs'
    return 1
  fi

  E2E_ORIGINAL_DIR="${PWD}"

  local tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  MD2X_TEST_TMPDIR="$(mktemp -d "${tmp_root}/md2x-e2e-test.XXXXXX")"

  if [[ "${MD2X_TEST_TMPDIR}" == *' '* ]]; then
    md2x_fail "temporary directory path contains a space: ${MD2X_TEST_TMPDIR}" \
      'the CLI word-splits paths unquoted; set TMPDIR to a space-free location'
    return 1
  fi
  if [[ "${MD2X_TEST_TMPDIR}" == "${MD2X_REPO_ROOT}"/* ]]; then
    md2x_fail "temporary directory is inside the repository: ${MD2X_TEST_TMPDIR}" \
      'the version probe would then read the repository git state; set TMPDIR elsewhere'
    return 1
  fi

  MD2X_TEST_WORK_DIR="${MD2X_TEST_TMPDIR}/work"
  mkdir -p "${MD2X_TEST_WORK_DIR}"
  cd "${MD2X_TEST_WORK_DIR}"

  # 'md2x_run' (from common.bash) only needs MD2X_TEST_TMPDIR for its stdout/stderr
  # capture files; it does not touch PATH itself, so the ambient, real-toolchain PATH
  # this process inherited is left untouched.
}

e2e_teardown() {
  cd "${E2E_ORIGINAL_DIR:-/}" 2>/dev/null || cd /
  if [[ -n "${MD2X_TEST_TMPDIR:-}" ]] \
     && [[ "${MD2X_TEST_TMPDIR}" == */md2x-e2e-test.* ]] \
     && [[ -d "${MD2X_TEST_TMPDIR}" ]]; then
    rm -rf "${MD2X_TEST_TMPDIR}"
  fi
  unset MD2X_TEST_TMPDIR MD2X_TEST_WORK_DIR E2E_ORIGINAL_DIR
}

# --- capability gates -----------------------------------------------------------------

# Binary-presence gate for the HTML/DOCX cases -- sufficient for those two formats,
# which never invoke an external PDF engine.
e2e_require_pandoc() {
  command -v pandoc >/dev/null 2>&1 || skip "real 'pandoc' not found on PATH"
}

# Capability probe for the PDF case. 'generate-page.sh' drives Pandoc's PDF output by
# passing '--to html5' while writing to a '.pdf'-extensioned '-o' target -- which routes
# through Pandoc's external HTML-to-PDF engine (weasyprint by default here) rather than
# a native PDF writer. A binary-presence check on 'pandoc' cannot see that dependency,
# so this attempts the same throwaway minimal conversion for real and skips, naming
# what failed, if it doesn't succeed.
e2e_require_pdf_engine() {
  command -v pandoc >/dev/null 2>&1 || skip "real 'pandoc' not found on PATH"

  local probe_dir probe_out probe_err
  probe_dir="$(mktemp -d "${MD2X_TEST_TMPDIR}/pdf-probe.XXXXXX")"
  probe_out="${probe_dir}/probe.pdf"
  probe_err="${probe_dir}/probe.err"

  # md2x never puts a bare 'weasyprint' on PATH -- it invokes the managed venv binary by
  # its absolute path instead (see ensure-weasyprint.sh). Point the probe at that same
  # binary so it tests what md2x actually uses rather than pandoc's PATH-based default.
  if ! pandoc --to html5 -o "${probe_out}" --pdf-engine="${HOME}/.md2x/venv/bin/weasyprint" --quiet <(printf '# probe\n') 2> "${probe_err}"; then
    skip "pandoc's PDF engine is unavailable: $(head -n 1 -- "${probe_err}")"
  fi
}

# --- content assertions ----------------------------------------------------------------

e2e_assert_nonempty() {
  local path="$1"
  [[ -s "${path}" ]] || md2x_fail "expected '${path}' to be non-empty" "cwd: ${PWD}"
}

e2e_assert_pdf_magic() {
  local path="$1" magic
  assert_file_exists "${path}" || return 1
  magic="$(head -c 4 -- "${path}")"
  [[ "${magic}" == '%PDF' ]] || md2x_fail "expected '${path}' to start with '%PDF', got: ${magic}"
}

e2e_assert_zip_magic() {
  local path="$1" magic
  assert_file_exists "${path}" || return 1
  magic="$(head -c 2 -- "${path}")"
  [[ "${magic}" == 'PK' ]] || md2x_fail "expected '${path}' to start with the zip magic 'PK', got: ${magic}"
}

# --- cases -----------------------------------------------------------------------------

@test "e2e: tiny-doc.md converts to real HTML with recognizable Pandoc/CSS markup" {
  e2e_require_pandoc

  md2x_copy_fixture 'tiny-doc.md'

  md2x_run --output-format html --flatten-dirs --output-path . tiny-doc.md

  assert_success
  assert_file_exists './tiny-doc.html'
  e2e_assert_nonempty './tiny-doc.html'
  # 'Tiny Doc' is the fixture's own heading text; '<style>' is the bundled GitHub CSS
  # 'generate-page.sh' embeds via '--css'. Neither marker exists in stub output, so this
  # is proof a real Pandoc conversion happened.
  assert_file_contains './tiny-doc.html' 'Tiny Doc'
  assert_file_contains './tiny-doc.html' '<style>'
  # 'class="markdown-body"' is the '--include-before-body' wrapper div (task 004 /
  # followup TNLq): direct proof, against real (non-stub) Pandoc output, that the div
  # genuinely lands around the rendered body so 'github.css''s bare '.markdown-body'
  # selectors match.
  assert_file_contains './tiny-doc.html' 'class="markdown-body"'
}

@test "e2e: tiny-doc.md converts to a real, non-empty DOCX" {
  e2e_require_pandoc

  md2x_copy_fixture 'tiny-doc.md'

  md2x_run --output-format docx --flatten-dirs --output-path . tiny-doc.md

  assert_success
  assert_file_exists './tiny-doc.docx'
  e2e_assert_nonempty './tiny-doc.docx'
  e2e_assert_zip_magic './tiny-doc.docx'
}

@test "e2e: tiny-doc.md converts to a real PDF with the Ghostscript/pdftk overlay applied" {
  e2e_require_pdf_engine

  md2x_copy_fixture 'tiny-doc.md'

  # '--keep-intermediate' keeps '<title>-overlay.pdf' around instead of deleting it once
  # merged, so its presence here is direct proof the Ghostscript/pdftk stage actually
  # ran -- not just that Pandoc produced a PDF on its own.
  md2x_run --flatten-dirs --output-path . --keep-intermediate tiny-doc.md

  assert_success
  e2e_assert_nonempty './tiny-doc.pdf'
  e2e_assert_pdf_magic './tiny-doc.pdf'

  assert_file_exists './tiny-doc-overlay.pdf'
  e2e_assert_nonempty './tiny-doc-overlay.pdf'
  e2e_assert_pdf_magic './tiny-doc-overlay.pdf'
}

@test "e2e: --single-page concatenates two fixtures into one real HTML document" {
  e2e_require_pandoc

  md2x_write_doc 'alpha.md' 'Alpha Heading'
  md2x_write_doc 'beta.md' 'Beta Heading'

  md2x_run --single-page --title combined --output-format html --flatten-dirs \
    --output-path . alpha.md beta.md

  assert_success
  assert_file_exists './combined.html'
  e2e_assert_nonempty './combined.html'
  assert_file_contains './combined.html' 'Alpha Heading'
  assert_file_contains './combined.html' 'Beta Heading'
}

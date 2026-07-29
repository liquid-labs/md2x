# Bootstraps a per-user WeasyPrint install for use as Pandoc's '--pdf-engine' on PDF output.
#
# WeasyPrint is managed entirely by md2x in a private virtualenv at '~/.md2x/venv'; it is never expected to be on
# 'PATH', is reached only by the absolute 'WEASYPRINT_BIN' path, and the venv is never activated. This is a per-user
# cache directory (derived from '${HOME}'), not project-relative -- a globally-installed 'md2x' has no stable
# project root at runtime.
#
# There is deliberately no version or staleness check: the '-x' test below is the entire gate. See
# 'plan/notes/weasyprint-bootstrap-design.md' for the rationale.

VENV_DIR="${HOME}/.md2x/venv"
WEASYPRINT_BIN="${VENV_DIR}/bin/weasyprint"

# Reports the failure of the bootstrap step named in $1, removes the incomplete venv so the next invocation retries
# from a clean state rather than resuming a half-built one, and exits with the same code the preflight loop uses for
# 'a required external dependency is not usable'.
ensure-weasyprint-fail() {
  echo "md2x: failed to install weasyprint (step: ${1})." >&2
  echo "md2x: likely causes: no network access, a proxy blocking PyPI, or missing platform build tooling." >&2
  echo "md2x: to retry manually, run:" >&2
  echo "  rm -rf '${VENV_DIR}' && python3 -m venv '${VENV_DIR}' && '${VENV_DIR}/bin/python3' -m ensurepip --upgrade && '${VENV_DIR}/bin/python3' -m pip install weasyprint" >&2
  rm -rf "${VENV_DIR}"
  exit 2
}

# Ensures '${WEASYPRINT_BIN}' exists and is executable, installing it into '${VENV_DIR}' on first use. Callers must
# gate calling this on PDF output only -- HTML/DOCX conversions never need WeasyPrint. Every byte any of the
# subprocesses below write goes to stderr, never stdout: stdout is a parsed data channel ('--list-files' and
# '--to-stdout'), and any bootstrap chatter on it would corrupt both.
ensure-weasyprint() {
  [[ -x "${WEASYPRINT_BIN}" ]] && return 0

  echo "md2x: installing weasyprint (one-time setup) into '${VENV_DIR}'; this may take a minute..." >&2

  python3 -m venv "${VENV_DIR}" >&2 || ensure-weasyprint-fail 'python3 -m venv'
  "${VENV_DIR}/bin/python3" -m ensurepip --upgrade >&2 || ensure-weasyprint-fail 'ensurepip'
  "${VENV_DIR}/bin/python3" -m pip install weasyprint >&2 || ensure-weasyprint-fail 'pip install weasyprint'

  [[ -x "${WEASYPRINT_BIN}" ]] || ensure-weasyprint-fail 'post-install check'

  echo "md2x: weasyprint installed." >&2
}

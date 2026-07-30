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

# Mutual-exclusion directory guarding the cold-bootstrap body of 'ensure-weasyprint()' (the
# 'python3 -m venv' / 'ensurepip' / 'pip install' sequence) against two concurrent 'md2x'
# processes racing to build '${VENV_DIR}' at the same time (followup AOJw). It is a sibling
# of '.md2x' rather than nested inside it, so acquiring the lock never depends on '.md2x'
# existing yet.
#
# 'mkdir' is atomic on POSIX filesystems -- of two processes racing 'mkdir
# "${WEASYPRINT_LOCK_DIR}"', exactly one succeeds -- so this needs no external locking
# tool. 'flock' (util-linux) was considered and rejected: it is a Linux-only tool not
# reliably present on macOS, which is this repo's dev/test environment (see AGENTS.md's
# Homebrew note), and the preflight check never verifies its presence.
WEASYPRINT_LOCK_DIR="${HOME}/.md2x-venv.lock"
# How long a losing process waits for the winner before giving up, in whole seconds. The
# cold bootstrap is a rare, human-triggered, ~1-minute event (see the docstring above), so
# a losing process blocks and waits rather than failing fast -- better UX than making a
# second concurrent 'md2x' invocation fail outright over a race it can't control. The wait
# is still bounded (never a silent indefinite hang): if the lock isn't released within this
# many seconds, either the winner is unusually slow (e.g. a very slow network) or it died
# mid-bootstrap and left a stale lock -- either way, this process gives up and reports
# rather than hanging forever.
WEASYPRINT_LOCK_TIMEOUT_SECS=180
WEASYPRINT_LOCK_POLL_SECS=1

# Reports the failure of the bootstrap step named in $1, releases the bootstrap lock (this
# is only ever called from within the locked section below, so the caller always holds the
# lock at this point), removes the incomplete venv so the next invocation retries from a
# clean state rather than resuming a half-built one, and exits with the same code the
# preflight loop uses for 'a required external dependency is not usable'.
ensure-weasyprint-fail() {
  echo "md2x: failed to install weasyprint (step: ${1})." >&2
  echo "md2x: likely causes: no network access, a proxy blocking PyPI, or missing platform build tooling." >&2
  echo "md2x: to retry manually, run:" >&2
  echo "  rm -rf '${VENV_DIR}' && python3 -m venv '${VENV_DIR}' && '${VENV_DIR}/bin/python3' -m ensurepip --upgrade && '${VENV_DIR}/bin/python3' -m pip install 'weasyprint==69.0'" >&2
  rm -rf "${VENV_DIR}"
  rmdir "${WEASYPRINT_LOCK_DIR}" 2>/dev/null || true
  exit 2
}

# Reports that this process gave up waiting for another 'md2x' process's weasyprint
# install to finish, and exits. Modeled on 'ensure-weasyprint-fail()' above: names what's
# wrong and gives an explicit manual remediation command rather than guessing -- this is
# the "stale lock" remediation path, so a lock left behind by a process that was killed
# mid-bootstrap does not permanently deadlock every future invocation; a human can always
# clear it and retry.
#
# Deliberately does NOT remove '${WEASYPRINT_LOCK_DIR}' or '${VENV_DIR}' itself -- this
# process never acquired the lock, so the other side may (rarely) still be legitimately
# mid-install on a very slow connection, and force-clearing state out from under a
# possibly-still-live process would be worse than a bounded wait timing out.
ensure-weasyprint-lock-timeout-fail() {
  echo "md2x: timed out after ${WEASYPRINT_LOCK_TIMEOUT_SECS}s waiting for another 'md2x' process's weasyprint install to finish." >&2
  echo "md2x: likely cause: another 'md2x' process is still installing (rare, but a cold install can be slow on a bad connection)." >&2
  echo "md2x: if no 'md2x' process is actually still running, a previous one was likely killed mid-install and left a stale lock." >&2
  echo "md2x: to clear it and retry, run:" >&2
  echo "  rm -rf '${WEASYPRINT_LOCK_DIR}' '${VENV_DIR}' && python3 -m venv '${VENV_DIR}' && '${VENV_DIR}/bin/python3' -m ensurepip --upgrade && '${VENV_DIR}/bin/python3' -m pip install 'weasyprint==69.0'" >&2
  exit 2
}

# Ensures '${WEASYPRINT_BIN}' exists and is executable, installing it into '${VENV_DIR}' on first use. Callers must
# gate calling this on PDF output only -- HTML/DOCX conversions never need WeasyPrint. Every byte any of the
# subprocesses below write goes to stderr, never stdout: stdout is a parsed data channel ('--list-files' and
# '--to-stdout'), and any bootstrap chatter on it would corrupt both.
ensure-weasyprint() {
  # Warm path: a single, cheap '-x' test, no lock-acquisition overhead of any kind. This
  # must stay true on essentially every invocation (see the file docstring above) -- only
  # the cold path below (the test failing) ever touches the locking machinery.
  [[ -x "${WEASYPRINT_BIN}" ]] && return 0

  # Cold path: race to acquire the bootstrap lock. 'mkdir' is atomic, so of any number of
  # concurrent invocations reaching this point, exactly one wins it; everyone else waits
  # (bounded by WEASYPRINT_LOCK_TIMEOUT_SECS) for the winner to finish.
  local waited=0
  while ! mkdir "${WEASYPRINT_LOCK_DIR}" 2>/dev/null; do
    # The winner (or another waiter's winner, if we're the Nth loser) may have finished
    # while we were polling -- recheck before deciding whether to keep waiting.
    [[ -x "${WEASYPRINT_BIN}" ]] && return 0

    (( waited < WEASYPRINT_LOCK_TIMEOUT_SECS )) || ensure-weasyprint-lock-timeout-fail

    sleep "${WEASYPRINT_LOCK_POLL_SECS}"
    waited=$(( waited + WEASYPRINT_LOCK_POLL_SECS ))
  done

  # We now hold the lock. Re-check '-x': the winner could have mkdir'd the lock,
  # installed, and released it again in the gap between our last failed 'mkdir' above and
  # this one succeeding, in which case there is nothing left for us to do.
  if [[ -x "${WEASYPRINT_BIN}" ]]; then
    rmdir "${WEASYPRINT_LOCK_DIR}" 2>/dev/null || true
    return 0
  fi

  echo "md2x: installing weasyprint (one-time setup) into '${VENV_DIR}'; this may take a minute..." >&2

  python3 -m venv "${VENV_DIR}" >&2 || ensure-weasyprint-fail 'python3 -m venv'
  "${VENV_DIR}/bin/python3" -m ensurepip --upgrade >&2 || ensure-weasyprint-fail 'ensurepip'
  "${VENV_DIR}/bin/python3" -m pip install 'weasyprint==69.0' >&2 || ensure-weasyprint-fail 'pip install weasyprint'

  [[ -x "${WEASYPRINT_BIN}" ]] || ensure-weasyprint-fail 'post-install check'

  echo "md2x: weasyprint installed." >&2
  rmdir "${WEASYPRINT_LOCK_DIR}" 2>/dev/null || true
}

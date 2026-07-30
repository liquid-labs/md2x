#!/usr/bin/env bats
#
# Proves followup AOJw is closed: two concurrent 'md2x' processes hitting a cold
# WeasyPrint bootstrap at once (e.g. the first-ever PDF conversion on a machine,
# kicked off twice concurrently) must not interleave the 'python3 -m venv' /
# 'ensurepip' / 'pip install' sequence inside 'ensure-weasyprint()', which would
# corrupt the shared '~/.md2x/venv' directory. See 'src/cli/lib/ensure-weasyprint.sh'.
#
# This file needs the OPPOSITE of what the shared 'md2x_setup' helper gives every
# other bats case: a genuinely cold environment (a private HOME with no pre-existing
# '.md2x/venv') so the cold-bootstrap body actually runs, rather than 'md2x_setup's
# pre-populated stub weasyprint binary (task 006 changes its default to install one),
# which would short-circuit the very code path under test here. It therefore never
# calls 'md2x_setup' / 'md2x_use_stub_path' and instead manages its own private
# working directory, HOME and PATH, following the 'e2e_setup'/'e2e_teardown' pattern
# in 'real-toolchain-e2e.bats' (see also 'plan/overview.md's parallel-eligibility
# notes on the 001/006 interaction).
#
# The real bootstrap needs network access and is slow (a real 'pip install'), so this
# file never drives it for real. Instead a fast fake 'python3' stands in for the real
# one on this file's private PATH:
#   * '-m venv <dir>'          -- after a deliberate short sleep (to widen the race
#                                  window), creates '<dir>/bin/' and copies itself in
#                                  as a nested fake 'python3' (which is what the two
#                                  subsequent calls below actually invoke).
#   * '-m ensurepip --upgrade' -- a no-op success.
#   * '-m pip install ...'     -- after another deliberate short sleep, creates
#                                  '<dir>/bin/weasyprint' as an executable placeholder.
# The venv-creation and pip-install steps bracket a single high-resolution,
# timestamped 'venv-start' / 'install-end' marker pair (tagged with which of the two
# concurrent invocations logged it, via 'MD2X_TEST_WPL_ID') in a shared log file this
# file controls. The assertions below parse that log to prove the two invocations'
# bootstrap bodies never actually overlapped in wall-clock time.

load '../helpers/common'

setup() {
  weasyprint_lock_setup
}

teardown() {
  weasyprint_lock_teardown
}

# --- local setup/teardown ------------------------------------------------------------
#
# Deliberately not 'md2x_setup' -- see the file header above. Builds a private HOME
# (with no pre-existing '.md2x') and a private PATH containing the repo's own stub
# 'pandoc'/'gs'/'pdftk' (fast and deterministic, same as the rest of the suite), the
# handful of real passthrough tools md2x itself needs, and the fake 'python3' that
# intercepts the WeasyPrint cold bootstrap instead of hitting the network.

weasyprint_lock_setup() {
  if ! [[ -x "${MD2X_BIN}" ]]; then
    md2x_fail "built CLI not found at '${MD2X_BIN}'" \
      "run 'make all' (or 'make test', which depends on it) before running bats directly"
    return 1
  fi

  WPL_ORIGINAL_DIR="${PWD}"
  WPL_ORIGINAL_PATH="${PATH}"

  local tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  WPL_TMPDIR="$(mktemp -d "${tmp_root}/md2x-wpl-test.XXXXXX")"

  if [[ "${WPL_TMPDIR}" == *' '* ]]; then
    md2x_fail "temporary directory path contains a space: ${WPL_TMPDIR}" \
      'the CLI word-splits paths unquoted; set TMPDIR to a space-free location'
    return 1
  fi
  if [[ "${WPL_TMPDIR}" == "${MD2X_REPO_ROOT}"/* ]]; then
    md2x_fail "temporary directory is inside the repository: ${WPL_TMPDIR}" \
      'the version probe would then read the repository git state; set TMPDIR elsewhere'
    return 1
  fi

  # 'WPL_HOME' has no '.md2x' at all -- the cold start this file exists to exercise.
  WPL_HOME="${WPL_TMPDIR}/home"
  WPL_WORK_DIR="${WPL_TMPDIR}/work"
  WPL_BIN_DIR="${WPL_TMPDIR}/bin"
  WPL_LOG="${WPL_TMPDIR}/bootstrap-log.tsv"
  mkdir -p "${WPL_HOME}" "${WPL_WORK_DIR}" "${WPL_BIN_DIR}"
  : > "${WPL_LOG}"

  # The repo's own stub 'pandoc'/'gs'/'pdftk' -- same fast, deterministic stand-ins
  # 'md2x_use_stub_path' gives the rest of the suite. This file only needs them to let
  # a PDF conversion reach and complete past 'ensure-weasyprint'; the stub pandoc
  # ignores whatever '--pdf-engine' path it's handed, so the placeholder weasyprint
  # binary the fake python3 below produces is never actually executed.
  local stub
  for stub in pandoc gs pdftk; do
    ln -s "${MD2X_STUB_DIR}/${stub}" "${WPL_BIN_DIR}/${stub}"
  done

  # Real passthrough tools md2x (or the bash it runs under) needs beyond the stubbed
  # three and the fake python3 below -- the same set and exec-wrapper mechanism
  # 'md2x_use_stub_path' uses (some, like 'brew', derive their own install prefix from
  # argv[0], so a wrapper rather than a symlink is required).
  local name real
  for name in bash brew git jq perl; do
    real="$(PATH="${WPL_ORIGINAL_PATH}" command -v "${name}" 2>/dev/null || true)"
    [[ -n "${real}" ]] && [[ -x "${real}" ]] || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "'${real}'" > "${WPL_BIN_DIR}/${name}"
    chmod +x "${WPL_BIN_DIR}/${name}"
  done

  weasyprint_lock_write_fake_python3 "${WPL_BIN_DIR}/python3"

  PATH="${WPL_BIN_DIR}:/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
  hash -r 2>/dev/null || true

  cd "${WPL_WORK_DIR}"
}

weasyprint_lock_teardown() {
  cd "${WPL_ORIGINAL_DIR:-/}" 2>/dev/null || cd /
  if [[ -n "${WPL_TMPDIR:-}" ]] \
     && [[ "${WPL_TMPDIR}" == */md2x-wpl-test.* ]] \
     && [[ -d "${WPL_TMPDIR}" ]]; then
    rm -rf "${WPL_TMPDIR}"
  fi
  if [[ -n "${WPL_ORIGINAL_PATH:-}" ]]; then
    PATH="${WPL_ORIGINAL_PATH}"
    export PATH
    hash -r 2>/dev/null || true
  fi
  unset WPL_TMPDIR WPL_HOME WPL_WORK_DIR WPL_BIN_DIR WPL_LOG WPL_ORIGINAL_DIR WPL_ORIGINAL_PATH
}

# weasyprint_lock_write_fake_python3 <path>
# Writes the fake 'python3' described in the file header to <path> and makes it
# executable. A single self-contained script: the '-m venv' branch copies '$0' into
# the new venv's 'bin/python3', so the exact same logic handles the two subsequent
# calls the real bootstrap makes against that nested copy.
weasyprint_lock_write_fake_python3() {
  local path="$1"
  cat > "${path}" <<'PYSTUB'
#!/usr/bin/env bash
#
# Fake 'python3' for the weasyprint-bootstrap-locking bats cases -- see that file's
# header for the full contract. 'MD2X_TEST_WPL_LOG' names the shared marker log;
# 'MD2X_TEST_WPL_ID' tags which of the concurrently-launched 'md2x' invocations is
# writing. Both are inherited from the environment md2x was launched with (a
# temporary env assignment on a simple command is exported to it and everything it
# execs), so every subprocess in the venv/ensurepip/pip-install chain -- including the
# nested copy of this very script -- sees the same values with no extra plumbing.

set -o errexit
set -o nounset

# A high-resolution timestamp. BSD/macOS 'date' has no '%N' for sub-second precision,
# so this shells out to perl's Time::HiRes instead of relying on GNU-only 'date'
# flags -- 'perl' is already a passthrough tool this suite's harness provides.
wpl_now() {
  perl -MTime::HiRes=time -e 'printf "%.6f\n", time'
}

wpl_log() {
  printf '%s\t%s\t%s\t%s\n' "${MD2X_TEST_WPL_ID:-unknown}" "$1" "$$" "$(wpl_now)" >> "${MD2X_TEST_WPL_LOG}"
}

case "${1:-}" in
  -m)
    case "${2:-}" in
      venv)
        VENV_DIR="${3:?venv dir required}"
        # Opens the interval this file's overlap assertion checks.
        wpl_log 'venv-start'
        sleep "${MD2X_TEST_WPL_SLEEP:-0.4}"
        mkdir -p "${VENV_DIR}/bin"
        cp "$0" "${VENV_DIR}/bin/python3"
        chmod +x "${VENV_DIR}/bin/python3"
        ;;
      ensurepip)
        # No-op success. Nothing to prove here beyond 'ensure-weasyprint()' calling it
        # at all, which the venv-creation/pip-install overlap check below already
        # exercises end to end.
        :
        ;;
      pip)
        # argv: python3 -m pip install weasyprint==69.0
        BIN_DIR="$(dirname "$0")"
        sleep "${MD2X_TEST_WPL_SLEEP:-0.4}"
        cat > "${BIN_DIR}/weasyprint" <<'WEASY'
#!/bin/sh
exit 0
WEASY
        chmod +x "${BIN_DIR}/weasyprint"
        # Closes the interval this file's overlap assertion checks.
        wpl_log 'install-end'
        ;;
      *)
        ;;
    esac
    ;;
  *)
    ;;
esac

exit 0
PYSTUB
  chmod +x "${path}"
}

# weasyprint_lock_assert_no_overlap <log-file>
# Parses '<id> <event> <pid> <hires-timestamp>' lines from a fake-python3 marker log
# into one '[venv-start, install-end]' interval per <id>-that-logged-a-pair, then
# fails if any two of those intervals overlap in wall-clock time. Correct locking
# means only the winner ever performs the install (the loser's post-wait '-x'
# recheck short-circuits it straight to success, per 'ensure-weasyprint()'), so this
# log almost always holds exactly one interval in practice -- but the check itself
# stays meaningful (and would catch a regression) for any number of intervals.
weasyprint_lock_assert_no_overlap() {
  local log="$1"
  local report
  report="$(awk -F'\t' '
    $2 == "venv-start"  { start[$1] = $4 }
    $2 == "install-end" { end[$1] = $4 }
    END {
      n = 0
      for (id in start) {
        if (!(id in end)) { next }
        ids[n] = id
        starts[n] = start[id]
        ends[n] = end[id]
        n++
      }
      for (i = 0; i < n; i++) {
        for (j = i + 1; j < n; j++) {
          if (starts[i] < ends[j] && starts[j] < ends[i]) {
            printf "overlap: %s [%s, %s] vs %s [%s, %s]\n", ids[i], starts[i], ends[i], ids[j], starts[j], ends[j]
          }
        }
      }
    }
  ' "${log}")"

  [[ -z "${report}" ]] || md2x_fail "concurrent bootstrap intervals overlapped:" "${report}" "full log:" "$(cat "${log}")"
}

# --- cases -----------------------------------------------------------------------------

@test "weasyprint-bootstrap-locking: two concurrent cold-start PDF conversions never interleave the install" {
  # Each invocation gets its OWN working directory (with its own copy of the fixture)
  # -- 'generate-page.sh' builds an intermediate '<title>-combined.<format>' file
  # relative to the process's cwd before moving it into place, so two invocations
  # sharing one cwd and title would race on that unrelated intermediate filename and
  # fail for a reason that has nothing to do with the WeasyPrint lock this test
  # exists to prove. Both invocations DO share 'WPL_HOME' -- that shared, cold
  # '~/.md2x/venv' is exactly what the two processes are racing to build.
  local work_dir_a="${WPL_TMPDIR}/work-a" work_dir_b="${WPL_TMPDIR}/work-b"
  local out_dir_a="${WPL_TMPDIR}/out-a" out_dir_b="${WPL_TMPDIR}/out-b"
  local stdout_a="${WPL_TMPDIR}/stdout-a" stderr_a="${WPL_TMPDIR}/stderr-a"
  local stdout_b="${WPL_TMPDIR}/stdout-b" stderr_b="${WPL_TMPDIR}/stderr-b"
  mkdir -p "${work_dir_a}" "${work_dir_b}" "${out_dir_a}" "${out_dir_b}"
  md2x_write_doc "${work_dir_a}/report.md"
  md2x_write_doc "${work_dir_b}/report.md"

  ( cd "${work_dir_a}" \
      && HOME="${WPL_HOME}" MD2X_TEST_WPL_LOG="${WPL_LOG}" MD2X_TEST_WPL_ID='proc-a' \
         "${MD2X_BIN}" --flatten-dirs --output-path "${out_dir_a}" report.md \
         > "${stdout_a}" 2> "${stderr_a}" ) &
  local pid_a=$!

  ( cd "${work_dir_b}" \
      && HOME="${WPL_HOME}" MD2X_TEST_WPL_LOG="${WPL_LOG}" MD2X_TEST_WPL_ID='proc-b' \
         "${MD2X_BIN}" --flatten-dirs --output-path "${out_dir_b}" report.md \
         > "${stdout_b}" 2> "${stderr_b}" ) &
  local pid_b=$!

  local status_a=0 status_b=0
  wait "${pid_a}" || status_a=$?
  wait "${pid_b}" || status_b=$?

  # (a) both invocations succeed.
  if [[ "${status_a}" -ne 0 ]]; then
    md2x_fail "concurrent invocation A exited ${status_a}" "stderr: $(cat "${stderr_a}")"
  fi
  if [[ "${status_b}" -ne 0 ]]; then
    md2x_fail "concurrent invocation B exited ${status_b}" "stderr: $(cat "${stderr_b}")"
  fi

  # (b) the logged install intervals never overlapped -- the two processes never ran
  # the venv-creation/pip-install sequence concurrently.
  weasyprint_lock_assert_no_overlap "${WPL_LOG}"

  # (c) the shared weasyprint binary ends up executable exactly once, not
  # corrupted/partially-overwritten by an interleaved second install: exactly one
  # 'venv-start' and one 'install-end' marker in the combined log proves the loser
  # never redid (and re-clobbered) the winner's install.
  local start_count end_count
  start_count="$(grep -c -F $'\tvenv-start\t' "${WPL_LOG}" || true)"
  end_count="$(grep -c -F $'\tinstall-end\t' "${WPL_LOG}" || true)"
  assert_equal "${start_count}" '1' "'venv-start' marker count"
  assert_equal "${end_count}" '1' "'install-end' marker count"

  assert_file_exists "${WPL_HOME}/.md2x/venv/bin/weasyprint"
  [[ -x "${WPL_HOME}/.md2x/venv/bin/weasyprint" ]] \
    || md2x_fail "expected '${WPL_HOME}/.md2x/venv/bin/weasyprint' to be executable"

  # The lock is released on every exit path -- nothing should be left behind once
  # both invocations have returned.
  assert_file_not_exists "${WPL_HOME}/.md2x-venv.lock"
}

@test "weasyprint-bootstrap-locking: warm path (pre-existing weasyprint) never touches the lock" {
  mkdir -p "${WPL_HOME}/.md2x/venv/bin"
  cat > "${WPL_HOME}/.md2x/venv/bin/weasyprint" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "${WPL_HOME}/.md2x/venv/bin/weasyprint"

  md2x_write_doc 'report.md'

  local status=0
  HOME="${WPL_HOME}" MD2X_TEST_WPL_LOG="${WPL_LOG}" MD2X_TEST_WPL_ID='warm' \
    "${MD2X_BIN}" --flatten-dirs --output-path "${WPL_TMPDIR}/out-warm" report.md \
    > "${WPL_TMPDIR}/stdout-warm" 2> "${WPL_TMPDIR}/stderr-warm" || status=$?

  [[ "${status}" -eq 0 ]] \
    || md2x_fail "warm-path run exited ${status}" "stderr: $(cat "${WPL_TMPDIR}/stderr-warm")"

  # No lock directory ever created (the warm path never touches the locking
  # machinery at all -- only the '-x' test).
  assert_file_not_exists "${WPL_HOME}/.md2x-venv.lock"
  # No fake-python3 activity logged either -- the warm path never spawns python3.
  if [[ -s "${WPL_LOG}" ]]; then
    md2x_fail 'expected no fake-python3 activity on the warm path' "log: $(cat "${WPL_LOG}")"
  fi
}

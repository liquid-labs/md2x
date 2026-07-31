#!/usr/bin/env bats
#
# Behavioural coverage for md2x's non-zero exit paths: a missing required external
# binary (exit 2, naming the binary -- docs/md2x-spec.md's 'General features' and
# 'Exit behavior') and an input path that is neither a file nor a directory (non-zero,
# naming the path -- 'Exit behavior'). 'harness-smoke.bats' exercises the missing-
# 'pandoc' case as part of proving the harness's 'md2x_path_without' helper works;
# these cases are the dedicated behavioural coverage for the CLI's own contract.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  # Restore permissions unconditionally before delegating to 'md2x_teardown''s
  # 'rm -rf' -- if an assertion in one of the "unreadable search root" cases below
  # fails, the case's own trailing 'chmod 755' never runs, and bats' own temp-directory
  # cleanup can't recurse into a mode-000 directory to remove it. Harmless no-op when
  # the directory doesn't exist or is already readable.
  if [[ -d "${PWD}/unreadable-root" ]]; then
    chmod 755 "${PWD}/unreadable-root" 2>/dev/null || true
  fi
  md2x_teardown
}

@test "a PATH missing 'pandoc' exits 2 and names 'pandoc'" {
  md2x_write_doc 'report.md'
  md2x_path_without pandoc

  md2x_run report.md

  assert_failure 2
  assert_stderr_contains "Required executable 'pandoc' not found"
  refute_stub_called pandoc
  assert_file_not_exists './report.pdf'
}

@test "a PATH missing 'gs' exits 2 and names 'gs'" {
  md2x_write_doc 'report.md'
  md2x_path_without gs

  md2x_run report.md

  assert_failure 2
  assert_stderr_contains "Required executable 'gs' not found"
  refute_stub_called gs
  refute_stub_called pandoc
  assert_file_not_exists './report.pdf'
}

@test "an input path that is neither a file nor a directory exits non-zero and names the path" {
  md2x_run no-such-file.md

  assert_failure
  assert_stderr_contains "'no-such-file.md' is neither a file nor a directory"
}

# --- unreadable search root: abort loudly, not silently (followup 8ZmD) --------------
#
# 'src/cli/md2x.sh's file-discovery pipe nests 'find "${ROOT_DIR}" -name "*.md" | while
# ...; done' inside a per-root outer loop, itself inside a '< <(...)' process
# substitution feeding the main conversion loop. Process-substitution failures are
# invisible to the parent's own 'errexit'/'pipefail', so a 'find' failure (e.g. an
# unreadable root) can't propagate its exit status to the top-level script directly;
# 'md2x.sh' instead signals it via a sentinel temp file the top-level script checks
# right after that process substitution closes. These two cases pin down the resulting,
# maintainer-confirmed contract: any unreadable search root makes the whole run exit
# non-zero and name the failing root, regardless of where it falls in the argument
# list -- no partial run is ever silently reported as a success.
#
# Skipped under 'root', which can read a mode-000 directory and would make these cases
# vacuously pass/fail differently -- same guard rationale as 'md2x_path_without' above.

@test "an unreadable search root listed before a readable one aborts and names the root" {
  (( $(id -u) != 0 )) || skip "running as root can read a mode-000 directory; skip to avoid a vacuous result"

  mkdir -p unreadable-root
  md2x_write_doc 'unreadable-root/hidden.md'
  md2x_write_doc 'good-root/report.md'
  chmod 000 unreadable-root

  md2x_run --output-format html --output-path out unreadable-root good-root

  assert_failure
  assert_stderr_contains 'Permission denied'
  assert_stderr_contains 'unreadable-root'
  assert_file_not_exists 'out/report.html'

  chmod 755 unreadable-root
}

@test "an unreadable search root listed after a readable one still aborts and names the root" {
  (( $(id -u) != 0 )) || skip "running as root can read a mode-000 directory; skip to avoid a vacuous result"

  mkdir -p unreadable-root
  md2x_write_doc 'unreadable-root/hidden.md'
  md2x_write_doc 'good-root/report.md'
  chmod 000 unreadable-root

  md2x_run --output-format html --output-path out good-root unreadable-root

  assert_failure
  assert_stderr_contains 'Permission denied'
  assert_stderr_contains 'unreadable-root'
  # The good root's own conversion already completed before the later root's failure
  # was discovered; a healthy root's real output is not rolled back, only the run's
  # overall exit status is affected.
  assert_file_exists 'out/report.html'

  chmod 755 unreadable-root
}

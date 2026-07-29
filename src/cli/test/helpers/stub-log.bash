#!/usr/bin/env bash
#
# Helpers for asserting against the stub invocation log written by
# '../stubs/pandoc', '../stubs/gs' and '../stubs/pdftk'. Sourced by 'common.bash'; a
# test file should 'load' that rather than this file directly.
#
# Log format: one line per invocation, tab separated, first field is the stub's
# command name and the remaining fields are its argument vector verbatim. The stubs
# never emit tabs or newlines of their own, so a line always maps to one invocation.
#
# Naming convention: 'assert_*' / 'refute_*' fail the case; 'md2x_stub_*' are plain
# accessors that print to stdout so a test can capture and inspect them.

MD2X_STUB_FIELD_SEPARATOR=$'\t'

# Absolute path of the current case's stub log.
md2x_stub_log_path() {
  printf '%s\n' "${MD2X_TEST_STUB_LOG:-}"
}

# Print the whole log; used as failure context.
md2x_stub_log_dump() {
  if [[ -n "${MD2X_TEST_STUB_LOG:-}" ]] && [[ -f "${MD2X_TEST_STUB_LOG}" ]]; then
    printf 'stub invocation log (%s):\n' "${MD2X_TEST_STUB_LOG}" >&2
    cat -- "${MD2X_TEST_STUB_LOG}" >&2
  else
    printf 'stub invocation log: <none>\n' >&2
  fi
}

# md2x_stub_calls <stub-name> -- print every logged invocation of that stub, one per
# line. Prints nothing (and still succeeds) when there were none.
md2x_stub_calls() {
  local name="$1"
  if [[ -n "${MD2X_TEST_STUB_LOG:-}" ]] && [[ -f "${MD2X_TEST_STUB_LOG}" ]]; then
    grep "^${name}${MD2X_STUB_FIELD_SEPARATOR}" "${MD2X_TEST_STUB_LOG}" || true
  fi
}

# md2x_stub_call_count <stub-name>
md2x_stub_call_count() {
  local calls
  calls="$(md2x_stub_calls "$1")"
  if [[ -z "${calls}" ]]; then
    printf '0\n'
  else
    printf '%s\n' "${calls}" | wc -l | tr -d ' '
  fi
}

# md2x_stub_last_call <stub-name> -- the most recent invocation line, or empty.
md2x_stub_last_call() {
  md2x_stub_calls "$1" | tail -n 1
}

# md2x_stub_last_call_args <stub-name> -- the most recent invocation's arguments, one
# per line, with the leading command-name field dropped.
md2x_stub_last_call_args() {
  local line
  line="$(md2x_stub_last_call "$1")"
  [[ -n "${line}" ]] || return 0
  local -a fields=()
  IFS="${MD2X_STUB_FIELD_SEPARATOR}" read -r -a fields <<< "${line}"
  local index=1
  while (( index < ${#fields[@]} )); do
    printf '%s\n' "${fields[index]}"
    index=$(( index + 1 ))
  done
}

assert_stub_called() {
  local name="$1"
  if [[ -z "$(md2x_stub_calls "${name}")" ]]; then
    md2x_stub_log_dump
    md2x_fail "expected the '${name}' stub to have been invoked"
  fi
}

refute_stub_called() {
  local name="$1"
  if [[ -n "$(md2x_stub_calls "${name}")" ]]; then
    md2x_stub_log_dump
    md2x_fail "expected the '${name}' stub NOT to have been invoked"
  fi
}

# assert_stub_call_count <stub-name> <expected-count>
assert_stub_call_count() {
  local name="$1" expected="$2" actual
  actual="$(md2x_stub_call_count "${name}")"
  if [[ "${actual}" != "${expected}" ]]; then
    md2x_stub_log_dump
    md2x_fail "expected ${expected} '${name}' invocation(s), got ${actual}"
  fi
}

# assert_last_call_contains <stub-name> <substring> -- substring match against the
# most recent invocation's whole argument vector.
assert_last_call_contains() {
  local name="$1" needle="$2" line
  line="$(md2x_stub_last_call "${name}")"
  if [[ -z "${line}" ]]; then
    md2x_stub_log_dump
    md2x_fail "expected the '${name}' stub to have been invoked"
    return 1
  fi
  if [[ "${line}" != *"${needle}"* ]]; then
    md2x_stub_log_dump
    md2x_fail "expected the last '${name}' invocation to contain: ${needle}"
  fi
}

refute_last_call_contains() {
  local name="$1" needle="$2" line
  line="$(md2x_stub_last_call "${name}")"
  if [[ "${line}" == *"${needle}"* ]]; then
    md2x_stub_log_dump
    md2x_fail "expected the last '${name}' invocation NOT to contain: ${needle}"
  fi
}

# assert_any_call_contains <stub-name> <substring> -- substring match against any
# logged invocation of that stub.
assert_any_call_contains() {
  local name="$1" needle="$2" calls
  calls="$(md2x_stub_calls "${name}")"
  if [[ "${calls}" != *"${needle}"* ]]; then
    md2x_stub_log_dump
    md2x_fail "expected some '${name}' invocation to contain: ${needle}"
  fi
}

refute_any_call_contains() {
  local name="$1" needle="$2" calls
  calls="$(md2x_stub_calls "${name}")"
  if [[ "${calls}" == *"${needle}"* ]]; then
    md2x_stub_log_dump
    md2x_fail "expected no '${name}' invocation to contain: ${needle}"
  fi
}

# assert_last_call_has_arg <stub-name> <arg> -- exact match against a single argument
# of the most recent invocation. Use this rather than the substring variants when a
# flag could otherwise match a longer one (e.g. '--toc' inside '--toc-depth').
assert_last_call_has_arg() {
  local name="$1" wanted="$2" arg
  while IFS= read -r arg; do
    [[ "${arg}" == "${wanted}" ]] || continue
    return 0
  done < <(md2x_stub_last_call_args "${name}")
  md2x_stub_log_dump
  md2x_fail "expected the last '${name}' invocation to include the argument: ${wanted}"
}

refute_last_call_has_arg() {
  local name="$1" wanted="$2" arg
  while IFS= read -r arg; do
    [[ "${arg}" == "${wanted}" ]] || continue
    md2x_stub_log_dump
    md2x_fail "expected the last '${name}' invocation NOT to include the argument: ${wanted}"
    return 1
  done < <(md2x_stub_last_call_args "${name}")
  return 0
}

# --- pandoc process-substitution captures ------------------------------------------
#
# The CLI passes '--metadata-file', '--css' and the (link-rewritten) input document as
# process substitutions, so their content is not visible in the argument log. The
# pandoc stub copies each into "${MD2X_TEST_STUB_CAPTURE_DIR}".

# Number of pandoc invocations whose input was captured.
md2x_pandoc_capture_count() {
  local count_file="${MD2X_TEST_STUB_CAPTURE_DIR:-}/pandoc.count"
  if [[ -f "${count_file}" ]]; then
    cat -- "${count_file}"
  else
    printf '0\n'
  fi
}

# md2x_pandoc_capture <input|metadata|css> [invocation-number]
# Prints the captured content; defaults to the most recent invocation.
md2x_pandoc_capture() {
  local kind="$1" number="${2:-}"
  [[ -n "${number}" ]] || number="$(md2x_pandoc_capture_count)"
  local path="${MD2X_TEST_STUB_CAPTURE_DIR:-}/pandoc-${number}-${kind}"
  if ! [[ -f "${path}" ]]; then
    md2x_fail "no captured pandoc ${kind} for invocation ${number} (looked for ${path})"
    return 1
  fi
  cat -- "${path}"
}

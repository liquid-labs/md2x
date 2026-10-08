# md2x error output and exit-code helpers. Sourced-only library: defining the functions
# below has no side effects at source time.
#
# Exit-code contract (the in-code source of truth; see plan/notes/design-decisions.md,
# "exit-code contract"):
#
#   | Code | Meaning                                |
#   | ---- | -------------------------------------- |
#   | 0    | success                                |
#   | 1    | runtime or conversion failure          |
#   | 2    | usage error                            |
#   | 3    | missing or unusable dependency         |
#
# Every message goes to stderr, prefixed 'md2x: ' ('md2x: warning: ' for warnings). Color
# is used only when stderr is a TTY and NO_COLOR is unset or empty; off a TTY no byte of
# output is an ANSI escape. This module never calls 'tput' and never folds lines. Kept
# compatible with bash 3.2.

# md2x-use-color: true when stderr is a TTY and NO_COLOR is unset or empty.
md2x-use-color() {
  [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]
}

# md2x-emit <label> <color-code> <message>...
# Prints '<label> <message>' to stderr, coloring the label when permitted.
md2x-emit() {
  local LABEL="${1}" COLOR="${2}"
  shift 2
  if md2x-use-color; then
    printf '\033[%sm%s\033[0m %s\n' "${COLOR}" "${LABEL}" "$*" >&2
  else
    printf '%s %s\n' "${LABEL}" "$*" >&2
  fi
}

# md2x-warn <message>...: print a warning; does not exit.
md2x-warn() {
  md2x-emit 'md2x: warning:' '1;33' "$@"
}

# md2x-die-usage <message>...: report a usage error and exit 2.
md2x-die-usage() {
  md2x-emit 'md2x:' '1;31' "$@"
  printf "Try 'md2x --help' for more information.\n" >&2
  exit 2
}

# md2x-die-runtime <message>...: report a runtime or conversion failure and exit 1.
md2x-die-runtime() {
  md2x-emit 'md2x:' '1;31' "$@"
  exit 1
}

# md2x-die-dependency <message>...: report a missing or unusable dependency and exit 3.
md2x-die-dependency() {
  md2x-emit 'md2x:' '1;31' "$@"
  exit 3
}

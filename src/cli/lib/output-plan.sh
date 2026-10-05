# md2x output-planning helpers: path normalization, target-location checks, and the lookup
# the collision check uses. Sourced-only library: defining the functions below has no side
# effects at source time. Kept compatible with bash 3.2 (no namerefs, no '${var,,}').
#
# Every user-facing failure goes through 'md2x-die-usage' (exit 2) and echoes paths through
# 'md2x-title-display', so these helpers need 'errors.sh' and 'title-safe.sh' loaded.

# md2x-canonical-path <file>
# Prints the physical directory of <file> (symlinks resolved at the directory level, via
# 'pwd -P', which needs no GNU 'realpath') plus its basename. The file itself is never
# resolved through a symlink.
md2x-canonical-path() {
  local FILE_IN="${1}" DIR_PART BASE_PART
  case "${FILE_IN}" in
    */*) DIR_PART="${FILE_IN%/*}"; BASE_PART="${FILE_IN##*/}";;
    *) DIR_PART='.'; BASE_PART="${FILE_IN}";;
  esac
  [[ -n "${DIR_PART}" ]] || DIR_PART='/'
  DIR_PART="$(CDPATH='' cd -- "${DIR_PART}" 2>/dev/null && pwd -P)" \
    || { printf '%s' "${FILE_IN}"; return 0; }
  printf '%s/%s' "${DIR_PART%/}" "${BASE_PART}"
}

# normalize-path <path>
# Collapse repeated slashes, drop '/./' segments and any leading './' so that roots and
# found paths written in different-but-equivalent forms ('docs', './docs', 'docs/')
# compare as strings, and so no '/./' survives into a path we build or print.
normalize-path() {
  local PATH_IN="${1}"
  while [[ "${PATH_IN}" == *'//'* ]]; do PATH_IN="${PATH_IN//\/\//\/}"; done
  while [[ "${PATH_IN}" == *'/./'* ]]; do PATH_IN="${PATH_IN//\/.\//\/}"; done
  while [[ "${PATH_IN}" == './'* ]]; do PATH_IN="${PATH_IN#./}"; done
  printf '%s' "${PATH_IN}"
}

# relative-output-dir <md-file> <search-root>
#
# The directory the output file must occupy under '--output-path': the directory part of
# <md-file> taken relative to <search-root>, the directory argument the file was found
# under. An empty <search-root> means the file was named directly on the command line,
# which the contract places directly in '--output-path'. Prints nothing when the file
# sits at the root, so callers can skip appending a subdirectory entirely rather than
# appending a '.' segment.
relative-output-dir() {
  local MD_PATH ROOT PREFIX REL
  # A file named directly on the command line carries no search root; it is rooted at
  # its own directory and so always lands directly in '--output-path'.
  [[ -n "${2}" ]] || return 0

  MD_PATH="$(normalize-path "${1}")"
  ROOT="$(normalize-path "${2}")"

  REL="${MD_PATH}"
  if [[ -n "${ROOT}" ]] && [[ "${ROOT}" != '.' ]]; then
    PREFIX="${ROOT}"
    [[ "${PREFIX}" == */ ]] || PREFIX="${PREFIX}/"
    # A found path always starts with the root 'find' was given, so the prefix match is
    # the normal case; leaving REL as the whole path is a conservative fallback.
    [[ "${MD_PATH}" != "${PREFIX}"* ]] || REL="${MD_PATH#"${PREFIX}"}"
  fi

  # Parameter expansion rather than 'dirname', so a name starting with '-' needs no '--'.
  REL="$(md2x-parent-dir "${REL}")"
  [[ "${REL}" == '.' ]] || [[ "${REL}" == '/' ]] || printf '%s' "${REL}"
}

# md2x-trim-trailing-slashes <path>
# Drops every trailing '/' from <path>, except that '/' itself stays '/'.
md2x-trim-trailing-slashes() {
  local PATH_IN="${1}"
  while [[ "${PATH_IN}" == */ ]] && [[ "${PATH_IN}" != '/' ]]; do
    PATH_IN="${PATH_IN%/}"
  done
  printf '%s' "${PATH_IN}"
}

# md2x-join-path <dir> <name>
# Prints '<dir>/<name>', without doubling the slash when <dir> is '/'.
md2x-join-path() {
  if [[ "${1}" == '/' ]]; then
    printf '/%s' "${2}"
  else
    printf '%s/%s' "${1}" "${2}"
  fi
}

# md2x-parent-dir <path>
# Prints the directory part of <path> ('.' when it has none, '/' for a top-level name).
md2x-parent-dir() {
  local PATH_IN="${1}" DIR_PART
  case "${PATH_IN}" in
    */*) DIR_PART="${PATH_IN%/*}";;
    *) DIR_PART='.';;
  esac
  [[ -n "${DIR_PART}" ]] || DIR_PART='/'
  printf '%s' "${DIR_PART}"
}

# md2x-canonical-target <path>
# Prints a canonical form of <path> for equality checks: a symlink at the final component
# is followed (so writing through it is recognized as writing its destination), and the
# directory part is resolved physically up to its deepest existing ancestor; any
# not-yet-existing remainder is appended as written. The path need not exist.
md2x-canonical-target() {
  local PATH_IN="${1}" LINK COUNT=0 DIR_PART BASE_PART REST='' PHYSICAL
  while [[ -L "${PATH_IN}" ]] && (( COUNT < 40 )); do
    LINK="$(readlink "${PATH_IN}")" || break
    case "${LINK}" in
      /*) PATH_IN="${LINK}";;
      *) PATH_IN="$(md2x-parent-dir "${PATH_IN}")/${LINK}";;
    esac
    COUNT=$(( COUNT + 1 ))
  done
  DIR_PART="$(md2x-parent-dir "${PATH_IN}")"
  BASE_PART="${PATH_IN##*/}"
  while [[ ! -d "${DIR_PART}" ]] && [[ "${DIR_PART}" != '.' ]] && [[ "${DIR_PART}" != '/' ]]; do
    REST="${DIR_PART##*/}/${REST}"
    DIR_PART="$(md2x-parent-dir "${DIR_PART}")"
  done
  PHYSICAL="$(CDPATH='' cd -- "${DIR_PART}" 2>/dev/null && pwd -P)" || PHYSICAL="${DIR_PART}"
  printf '%s/%s%s' "${PHYSICAL%/}" "${REST}" "${BASE_PART}"
}

# md2x-lowercase <text>
# ASCII-lowercases <text> (byte-wise, so it behaves the same in every locale). Prints no
# newline. Used for the case-insensitive collision comparison.
md2x-lowercase() {
  printf '%s' "${1}" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

# md2x-check-output-location <target>
# Reports a usage error (exit 2) when <target> cannot possibly be written: it is an
# existing directory, or a component of its parent path exists as a non-directory (so
# the parent directory cannot be created). Runs at planning time, before any conversion.
md2x-check-output-location() {
  local TARGET="${1}" DIR_PART
  if [[ -d "${TARGET}" ]]; then
    md2x-die-usage "output path '$(md2x-title-display "${TARGET}")' is a directory, not a file."
  fi
  DIR_PART="$(md2x-parent-dir "${TARGET}")"
  while [[ ! -e "${DIR_PART}" ]] && [[ ! -L "${DIR_PART}" ]] \
        && [[ "${DIR_PART}" != '.' ]] && [[ "${DIR_PART}" != '/' ]]; do
    DIR_PART="$(md2x-parent-dir "${DIR_PART}")"
  done
  if [[ -e "${DIR_PART}" ]] && [[ ! -d "${DIR_PART}" ]]; then
    md2x-die-usage "cannot create the output directory for '$(md2x-title-display "${TARGET}")':" \
      "'$(md2x-title-display "${DIR_PART}")' exists and is not a directory."
  fi
}

# md2x-lookup-record <records> <key>
# <records> is a newline-led list of '<key><tab><value>' lines. Prints the value of the
# first record whose key equals <key> exactly and returns 0, or returns 1 when none does.
md2x-lookup-record() {
  local RECORDS="${1}" PATTERN
  PATTERN=$'\n'"${2}"$'\t'
  [[ "${RECORDS}" == *"${PATTERN}"* ]] || return 1
  RECORDS="${RECORDS#*"${PATTERN}"}"
  printf '%s' "${RECORDS%%$'\n'*}"
}

# md2x-target-is-input <target> <inputs>
# Succeeds when <target> is the same file as any input in <inputs> (the resolved-input list:
# one '<file><tab><search-root>' record per line). 'test -ef' compares device and inode, so
# it also catches a hard link, a symlink, or an alternate mount path to an input that the
# plan-time string comparison cannot see. A target that does not exist yet is never an input.
md2x-target-is-input() {
  local TARGET="${1}" INPUTS="${2}" INPUT_FILE INPUT_ROOT
  [[ -e "${TARGET}" ]] || return 1
  while IFS=$'\t' read -r INPUT_FILE INPUT_ROOT; do
    [[ -n "${INPUT_FILE}" ]] || continue
    [[ ! "${TARGET}" -ef "${INPUT_FILE}" ]] || return 0
  done <<< "${INPUTS}"
  return 1
}

# md2x-deliver-output <staged-file> <target> <inputs>
# Delivers the staged result to <target> without ever writing through the target path: the
# copy goes to a temp file in the target's own directory, and 'mv' (an atomic 'rename' within
# one directory) puts it in place. A symlink at <target> is therefore replaced, not followed,
# and a hard link to an input keeps its other names untouched. Immediately before the rename
# the target is re-checked against <inputs> (see 'md2x-target-is-input'). Dies (runtime error)
# on any failure, removing the temp file first. Needs 'errors.sh' and 'title-safe.sh'.
md2x-deliver-output() {
  local STAGED="${1}" TARGET="${2}" INPUTS="${3}" TARGET_DIR TARGET_SHOWN TEMP_FILE MODE
  TARGET_SHOWN="$(md2x-title-display "${TARGET}")"
  TARGET_DIR="$(md2x-parent-dir "${TARGET}")"
  # 'mv' onto a directory would move the file into it instead of replacing it.
  [[ ! -d "${TARGET}" ]] || [[ -L "${TARGET}" ]] \
    || md2x-die-runtime "could not write '${TARGET_SHOWN}': it is a directory."
  TEMP_FILE="$(mktemp "${TARGET_DIR%/}/.md2x-out.XXXXXX" 2>/dev/null)" \
    || md2x-die-runtime "could not write '${TARGET_SHOWN}'."
  # 'mktemp' creates the file 0600; give it the mode a plain new file would get.
  MODE="$(printf '%03o' $(( 0666 & ~$(umask) )))"
  if ! { cp -- "${STAGED}" "${TEMP_FILE}" && chmod "${MODE}" "${TEMP_FILE}"; } 2>/dev/null; then
    rm -f -- "${TEMP_FILE}"
    md2x-die-runtime "could not write '${TARGET_SHOWN}'."
  fi
  if md2x-target-is-input "${TARGET}" "${INPUTS}"; then
    rm -f -- "${TEMP_FILE}"
    md2x-die-runtime "refusing to overwrite '${TARGET_SHOWN}': it is the same file as an input."
  fi
  if ! mv -f -- "${TEMP_FILE}" "${TARGET}" 2>/dev/null; then
    rm -f -- "${TEMP_FILE}"
    md2x-die-runtime "could not write '${TARGET_SHOWN}'."
  fi
}

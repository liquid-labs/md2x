# md2x input-argument processing and input discovery. Sourced-only library: defining the
# functions below has no side effects at source time, and they set no state until called.
# Kept compatible with bash 3.2 (no namerefs), so results come back through the documented
# global variables below, the way 'parse-options.sh' does it. Needs 'errors.sh',
# 'title-safe.sh' and 'output-plan.sh' (for 'md2x-canonical-path') loaded.
#
# The two entry points run in order, with the same arguments 'md2x' was given after option
# parsing:
#
#   md2x-process-input-args "$@"   sets STDIN_MODE, SEARCH_DIRS, MD_FILES
#   md2x-resolve-inputs            sets RESOLVED_INPUTS, RESOLVED_COUNT, SEARCH_ERROR_ROOT
#
# Every user-facing failure goes through 'md2x-die-usage' (exit 2) or 'md2x-die-runtime'
# (exit 1), and warnings through 'md2x-warn', exactly as when this ran inline in 'md2x'.

# md2x-process-input-args <arg>...
# Sets, as globals:
#   STDIN_MODE   non-empty ('true') when the sole argument is '-'; the document itself is
#                copied byte for byte into the work directory once that exists (see
#                'STDIN_FILE' in 'md2x'). A '-' next to any other input is a usage error.
#   SEARCH_DIRS  newline-terminated list of the directory arguments, in the order given
#   MD_FILES     newline-terminated list of the file arguments, in the order given
# Every other argument (nonexistent, unreadable, or containing a control character) is a
# usage error.
md2x-process-input-args() {
  local TEST_PATH
  SEARCH_DIRS=''
  MD_FILES=''
  STDIN_MODE=''
  for TEST_PATH in "$@"; do
    if [[ "${TEST_PATH}" == '-' ]] && (( $# > 1 )); then
      md2x-die-usage "'-' (stdin) cannot be combined with other inputs"
    fi
  done
  if (( $# == 1 )) && [[ ${1} == '-' ]]; then
    STDIN_MODE='true'
  else
    while (( $# > 0 )); do
      TEST_PATH="${1}"; shift
      # Records below are line- and tab-oriented, and every name is echoed in messages, so
      # a control character (tab, newline, ESC, ...) in an input path is refused up front.
      if md2x-has-control-chars "${TEST_PATH}"; then
        md2x-die-usage "input path '$(md2x-title-display "${TEST_PATH}")' contains control characters."
      fi
      if [[ -d "${TEST_PATH}" ]]; then
        SEARCH_DIRS="${SEARCH_DIRS}${TEST_PATH}"$'\n'
      elif [[ -f "${TEST_PATH}" ]]; then
        [[ -r "${TEST_PATH}" ]] \
          || md2x-die-usage "'$(md2x-title-display "${TEST_PATH}")' is not readable."
        MD_FILES="${MD_FILES}${TEST_PATH}"$'\n'
      else
        # Planner decision: a nonexistent (or otherwise unusable) input argument is a usage
        # error (exit 2), not a runtime failure -- the caller named something invalid.
        md2x-die-usage "'$(md2x-title-display "${TEST_PATH}")' is neither a file nor a directory. Bailing out."
      fi
    done
  fi
}

# md2x-resolve-inputs
# Reads STDIN_MODE, SEARCH_DIRS and MD_FILES (see 'md2x-process-input-args'). Builds the
# resolved input list ONCE, before any conversion: 'RESOLVED_INPUTS' holds one
# '<md-file><tab><search-root>' record per file to convert, directly named files first
# (empty search-root field), then the recursive search results sorted by path; each
# physical file appears once, the first occurrence winning (so its search root decides
# its output location). 'RESOLVED_COUNT' is its length. Both the '--title' gate in 'md2x'
# and the conversion loop consume this list, so they cannot drift.
#
# A search that fails (an unreadable root) stops the search of any later root, keeps what
# was found so far, and is reported once the files found so far were converted; see
# 'exit-codes.bats' "unreadable search root" cases and followup 8ZmD. 'SEARCH_ERROR_ROOT'
# names that root (empty when every search succeeded).
#
# Also reports the directories that held no Markdown files: a usage error when nothing at
# all resolved, a warning each otherwise.
md2x-resolve-inputs() {
  local CANDIDATES EMPTY_DIRS ROOT_DIR FIND_STATUS FIND_ROOT FOUND ROOT_FOUND FOUND_FILE
  local SEEN_CANONICAL ALL_CANDIDATES NAMED_FILE RESOLVE_FILE RESOLVE_ROOT CANONICAL
  local NO_MATCH_LABEL EMPTY_DIR
  RESOLVED_INPUTS=''
  RESOLVED_COUNT=0
  SEARCH_ERROR_ROOT=''
  [[ -z "${STDIN_MODE}" ]] || return 0

  CANDIDATES=''
  EMPTY_DIRS=''
  while IFS= read -r ROOT_DIR; do
    [[ -n "${ROOT_DIR}" ]] || continue
    # '-print0' piped through 'tr' (NUL to newline, and any newline inside a name to the
    # control character \001) keeps every name on exactly one line and lets the control
    # character check below see names that contain a newline.
    FIND_STATUS=0
    # 'find' errors (an unreadable directory) are not shown raw: the status is checked and
    # reported through 'md2x-die-runtime' below, naming the search root.
    # A relative root could be read by 'find' as an option ('-x') or an expression token
    # ('!', '(', ')', ','), so every non-absolute root is searched as './<root>' and the
    # './' is stripped from each result to keep the names as the user gave them.
    FIND_ROOT="${ROOT_DIR}"
    [[ "${ROOT_DIR}" == /* ]] || FIND_ROOT="./${ROOT_DIR}"
    FOUND="$(find "${FIND_ROOT}" \( -iname '*.md' -o -iname '*.markdown' \) ! -type d -print0 2>/dev/null \
      | tr '\012\000' '\001\012')" || FIND_STATUS=$?
    ROOT_FOUND=0
    while IFS= read -r FOUND_FILE; do
      [[ -n "${FOUND_FILE}" ]] || continue
      [[ "${FIND_ROOT}" == "${ROOT_DIR}" ]] || FOUND_FILE="${FOUND_FILE#./}"
      if md2x-has-control-chars "${FOUND_FILE}"; then
        md2x-die-usage "file name '$(md2x-title-display "${FOUND_FILE}")' found under" \
          "'$(md2x-title-display "${ROOT_DIR}")' contains control characters."
      fi
      ROOT_FOUND=$(( ROOT_FOUND + 1 ))
      CANDIDATES="${CANDIDATES}${FOUND_FILE}"$'\t'"${ROOT_DIR}"$'\n'
    done <<< "${FOUND}"
    if (( FIND_STATUS != 0 )); then
      SEARCH_ERROR_ROOT="${ROOT_DIR}"
      break
    fi
    (( ROOT_FOUND > 0 )) || EMPTY_DIRS="${EMPTY_DIRS}${ROOT_DIR}"$'\n'
  done <<< "${SEARCH_DIRS}"

  if [[ -n "${SEARCH_ERROR_ROOT}" ]] && [[ -z "${CANDIDATES}" ]] && [[ -z "${MD_FILES}" ]]; then
    md2x-die-runtime "could not fully search '$(md2x-title-display "${SEARCH_ERROR_ROOT}")' for Markdown files. Bailing out."
  fi

  CANDIDATES="$(printf '%s' "${CANDIDATES}" | sort)"
  SEEN_CANONICAL=$'\n'
  ALL_CANDIDATES=''
  while IFS= read -r NAMED_FILE; do
    [[ -n "${NAMED_FILE}" ]] || continue
    ALL_CANDIDATES="${ALL_CANDIDATES}${NAMED_FILE}"$'\t\n'
  done <<< "${MD_FILES}"
  ALL_CANDIDATES="${ALL_CANDIDATES}${CANDIDATES}"
  while IFS=$'\t' read -r RESOLVE_FILE RESOLVE_ROOT; do
    [[ -n "${RESOLVE_FILE}" ]] || continue
    CANONICAL="$(md2x-canonical-path "${RESOLVE_FILE}")"
    [[ "${SEEN_CANONICAL}" != *$'\n'"${CANONICAL}"$'\n'* ]] || continue
    SEEN_CANONICAL="${SEEN_CANONICAL}${CANONICAL}"$'\n'
    RESOLVED_INPUTS="${RESOLVED_INPUTS}${RESOLVE_FILE}"$'\t'"${RESOLVE_ROOT}"$'\n'
    RESOLVED_COUNT=$(( RESOLVED_COUNT + 1 ))
  done <<< "${ALL_CANDIDATES}"

  if [[ -n "${EMPTY_DIRS}" ]]; then
    if (( RESOLVED_COUNT == 0 )) && [[ -z "${SEARCH_ERROR_ROOT}" ]]; then
      NO_MATCH_LABEL=''
      while IFS= read -r EMPTY_DIR; do
        [[ -n "${EMPTY_DIR}" ]] || continue
        NO_MATCH_LABEL="${NO_MATCH_LABEL}${NO_MATCH_LABEL:+, }'$(md2x-title-display "${EMPTY_DIR}")'"
      done <<< "${EMPTY_DIRS}"
      md2x-die-usage "no Markdown files found in ${NO_MATCH_LABEL}"
    fi
    while IFS= read -r EMPTY_DIR; do
      [[ -n "${EMPTY_DIR}" ]] || continue
      md2x-warn "no Markdown files found in '$(md2x-title-display "${EMPTY_DIR}")'"
    done <<< "${EMPTY_DIRS}"
  fi
}

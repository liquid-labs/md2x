# md2x dependency preflight and version-inference helpers. Sourced-only library: defining
# the functions below has no side effects at source time. Kept compatible with bash 3.2
# (no namerefs, no '${var,,}', no 'sort -V').
#
# Every failure goes through the helpers in 'errors.sh' (exit 3 for a dependency problem),
# so a tool's own raw error text never reaches the user.

# The oldest pandoc md2x supports, and why. Every pandoc feature md2x uses first appeared in
# pandoc 2.0 (2017-10-29), so 2.0 is the highest minimum among them, checked against the
# pandoc changelog:
#   --lua-filter and the Lua 'Pandoc' filter function, 'pandoc.utils.stringify', and the
#     element 'walk' method (the link/image filter, 'lib/md2x-links.lua') ... pandoc 2.0
#   --log, the JSON log file ........................................ pandoc 2.0
#   --pdf-engine, with weasyprint as an HTML-to-PDF engine .......... pandoc 2.0
#   '--from gfm' (the GitHub-flavored CommonMark reader) ............ pandoc 2.0
#   -M/--metadata, --include-in-header/-before-body/-after-body, --css,
#     --standalone, '--to html5' .................................... pandoc 1.x
# Only pandoc 3.10.1 has actually been exercised; the floor comes from the changelog and
# the Lua filter documentation, not from test runs on older releases. Raise it here if an
# older release turns out to misbehave.
MD2X_PANDOC_MIN_VERSION='2.0'

# md2x-version-at-least <found> <floor>
# Returns 0 when dotted-numeric version <found> is greater than or equal to <floor>,
# comparing component by component as base-10 integers (missing components count as 0).
# Both arguments must be dotted digits; the caller validates <found>.
md2x-version-at-least() {
  local FOUND="${1}" FLOOR="${2}" FOUND_PART FLOOR_PART
  while [[ -n "${FOUND}" ]] || [[ -n "${FLOOR}" ]]; do
    FOUND_PART="${FOUND%%.*}"
    FLOOR_PART="${FLOOR%%.*}"
    [[ "${FOUND}" == *.* ]] && FOUND="${FOUND#*.}" || FOUND=''
    [[ "${FLOOR}" == *.* ]] && FLOOR="${FLOOR#*.}" || FLOOR=''
    FOUND_PART=$(( 10#${FOUND_PART:-0} ))
    FLOOR_PART=$(( 10#${FLOOR_PART:-0} ))
    (( FOUND_PART == FLOOR_PART )) && continue
    (( FOUND_PART > FLOOR_PART )) && return 0
    return 1
  done
  return 0
}

# md2x-check-pandoc-version
# Exits 3 when 'pandoc --version' cannot be run or parsed, or reports a version below
# 'MD2X_PANDOC_MIN_VERSION'. The first output line reads 'pandoc 3.10.1' (or, for a
# development build, 'pandoc 3.10.1-nightly'); anything after the leading dotted digits of
# the second word is ignored.
md2x-check-pandoc-version() {
  local VERSION_OUTPUT VERSION_LINE PROGRAM FOUND
  VERSION_OUTPUT="$(pandoc --version 2>/dev/null)" \
    || md2x-die-dependency "could not run 'pandoc --version'; md2x requires pandoc >= ${MD2X_PANDOC_MIN_VERSION}."
  VERSION_LINE="${VERSION_OUTPUT%%$'\n'*}"
  FOUND=''
  read -r PROGRAM FOUND _ <<< "${VERSION_LINE}" || true
  FOUND="${FOUND%%[!0-9.]*}"
  case "${FOUND}" in
    ''|.*|*..*|*.) md2x-die-dependency "could not determine the pandoc version from" \
      "'$(md2x-title-display "${VERSION_LINE}")'; md2x requires pandoc >= ${MD2X_PANDOC_MIN_VERSION}.";;
  esac
  md2x-version-at-least "${FOUND}" "${MD2X_PANDOC_MIN_VERSION}" \
    || md2x-die-dependency "pandoc ${FOUND} is too old; md2x requires pandoc >= ${MD2X_PANDOC_MIN_VERSION}"
}

# md2x-require-infer-version-tools
# '--infer-version' needs 'git' and 'jq'; they are checked only when the flag is given.
md2x-require-infer-version-tools() {
  local TOOL
  for TOOL in git jq; do
    command -v "${TOOL}" >/dev/null 2>&1 \
      || md2x-die-dependency "Required executable '${TOOL}' not found; it is needed only for '--infer-version'. Add to 'PATH' or install, or drop '--infer-version'."
  done
}

# md2x-infer-version <dir>
# Prints the version string for the footer, resolved against the git repository containing
# <dir>: the 'version' of '<toplevel>/package.json', or 'working' when the work tree has
# uncommitted changes. Prints nothing, after one warning on stderr, when <dir> is not in a
# git work tree or the package.json is missing, unreadable, or has no version; the caller
# omits the version from the footer and carries on. Needs 'git' and 'jq' (see above).
md2x-infer-version() {
  local DIR="${1}" TOP PKG STATUS VER
  TOP="$(git -C "${DIR}" rev-parse --show-toplevel 2>/dev/null)" || TOP=''
  if [[ -z "${TOP}" ]]; then
    md2x-warn "--infer-version: '$(md2x-title-display "${DIR}")' is not inside a git work tree; no version in the footer."
    return 0
  fi
  PKG="${TOP}/package.json"
  if [[ ! -f "${PKG}" ]]; then
    md2x-warn "--infer-version: no package.json at the top of the git work tree '$(md2x-title-display "${TOP}")'; no version in the footer."
    return 0
  fi
  STATUS="$(git -C "${TOP}" status --porcelain 2>/dev/null)" || STATUS='?'
  if [[ -n "${STATUS}" ]]; then
    printf 'working'
    return 0
  fi
  VER="$(jq -r '.version // empty | tostring' "${PKG}" 2>/dev/null)" || VER=''
  if [[ -z "${VER}" ]]; then
    md2x-warn "--infer-version: could not read a version from '$(md2x-title-display "${PKG}")'; no version in the footer."
    return 0
  fi
  printf '%s' "${VER}"
}

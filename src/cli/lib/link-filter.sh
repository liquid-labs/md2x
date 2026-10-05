# md2x helpers for the link/image Lua filter ('md2x-links.lua'). Sourced-only library:
# defining the functions below has no side effects at source time. Kept compatible with
# bash 3.2. Needs 'errors.sh', 'title-safe.sh' and 'output-plan.sh' loaded.

# md2x-percent-encode <text>
# Prints <text> percent-encoded byte by byte: only ASCII letters, digits, '_', '.' and '/'
# pass through. The result has no space, newline, '-' or '>' in it, so it is safe inside a
# single-line HTML comment. Prints no newline.
md2x-percent-encode() {
  local HEX BYTE OUT=''
  HEX="$(printf '%s' "${1-}" | LC_ALL=C od -An -v -tx1 | tr -d ' \n')"
  while [[ -n "${HEX}" ]]; do
    BYTE="${HEX:0:2}"
    HEX="${HEX:2}"
    case "${BYTE}" in
      2[ef]|3[0-9]|4[1-9a-f]|5[0-9af]|6[1-9a-f]|7[0-9a]) OUT="${OUT}$(printf "\\x${BYTE}")";;
      *) OUT="${OUT}%$(printf '%s' "${BYTE}" | tr 'a-f' 'A-F')";;
    esac
  done
  printf '%s' "${OUT}"
}

# md2x-abs-dir-of <file>
# Prints the absolute, physical directory that holds <file>.
md2x-abs-dir-of() {
  md2x-parent-dir "$(md2x-canonical-path "${1}")"
}

# md2x-new-nonce
# Prints a fresh per-run random token: 32 lowercase hex digits read from /dev/urandom
# (works on bash 3.2, macOS and Linux). Returns 1, printing nothing, when the random
# source is unavailable or short -- the caller must fail rather than fall back to a
# guessable value, since the token is what makes a source marker unforgeable.
md2x-new-nonce() {
  local NONCE
  NONCE="$(LC_ALL=C od -An -N16 -v -tx1 /dev/urandom 2>/dev/null | LC_ALL=C tr -d ' \n')" \
    || return 1
  [[ "${NONCE}" =~ ^[0-9a-f]{32}$ ]] || return 1
  printf '%s' "${NONCE}"
}

# md2x-source-marker <file> <nonce>
# Prints the one-line marker comment the '--single-page' concatenation inserts before
# <file>'s content (see 'md2x-links.lua'), followed by a newline. The marker carries the
# per-run <nonce> (also handed to the filter as 'md2x-nonce'); the filter honors only a
# marker bearing it, so a comment written in a source cannot redirect resolution.
md2x-source-marker() {
  printf '<!-- md2x:source-dir=%s source=%s nonce=%s -->\n' \
    "$(md2x-percent-encode "$(md2x-abs-dir-of "${1}")")" \
    "$(md2x-percent-encode "$(md2x-title-display "${1}")")" \
    "${2}"
}

# md2x-report-missing-images <miss-file>
# Prints one warning per '<target><tab><source>' record the filter wrote to <miss-file>.
md2x-report-missing-images() {
  local MISS_FILE="${1}" M_TARGET M_SOURCE
  [[ -s "${MISS_FILE}" ]] || return 0
  while IFS=$'\t' read -r M_TARGET M_SOURCE; do
    [[ -n "${M_TARGET}" ]] || continue
    md2x-warn "could not find image '$(md2x-title-display "${M_TARGET}")'" \
      "(referenced from $(md2x-title-display "${M_SOURCE}"))"
  done < "${MISS_FILE}"
}

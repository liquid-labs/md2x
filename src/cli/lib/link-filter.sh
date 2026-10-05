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

# md2x-source-marker <file>
# Prints the one-line marker comment the '--single-page' concatenation inserts before
# <file>'s content (see 'md2x-links.lua'), followed by a newline.
md2x-source-marker() {
  printf '<!-- md2x:source-dir=%s source=%s -->\n' \
    "$(md2x-percent-encode "$(md2x-abs-dir-of "${1}")")" \
    "$(md2x-percent-encode "$(md2x-title-display "${1}")")"
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

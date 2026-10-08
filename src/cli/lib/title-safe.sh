# md2x title-safety helpers: encode or validate an untrusted '--title' (or version string)
# for the sinks it reaches. Sourced-only library: defining the functions below has no
# side effects at source time. Kept compatible with bash 3.2.
#
# Control-character checks run under 'LC_ALL=C' so they are byte-wise and behave the same
# under 'LC_ALL=C' and a UTF-8 locale; printable non-ASCII bytes (the 0x80-0xFF range) are
# never treated as control characters.

# md2x-ps-string <text>
# Prints <text> encoded for the inside of a PostScript literal string '( ... )': control
# characters (0x00-0x1F, 0x7F) are stripped, '\', '(' and ')' are backslash-escaped, and
# every other byte (including non-ASCII) passes through unchanged. Prints no newline.
md2x-ps-string() {
  printf '%s' "${1-}" \
    | LC_ALL=C tr -d '\000-\037\177' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/(/\\(/g' -e 's/)/\\)/g' \
    | LC_ALL=C tr -d '\n'
}

# md2x-title-display <text>
# Prints <text> with every control character replaced by '?', so an untrusted title can
# be shown in a message without carrying terminal escapes. Prints no newline.
md2x-title-display() {
  printf '%s' "${1-}" | LC_ALL=C tr '\001-\037\177' '?'
}

# md2x-validate-title <title>
# Returns 0 when <title> is usable as an output file name stem; otherwise reports a usage
# error (exit 2) via 'md2x-die-usage'. Rejected: empty, '.', '..', anything containing
# '/', and anything containing a control character (0x01-0x1F, 0x7F). NUL cannot occur in
# an argv string, so it needs no check.
md2x-validate-title() {
  local TITLE_IN="${1-}" STRIPPED
  STRIPPED="$(printf '%s' "${TITLE_IN}" | LC_ALL=C tr -d '\001-\037\177'; printf x)"
  STRIPPED="${STRIPPED%x}"
  if [[ -z "${TITLE_IN}" ]] || [[ "${TITLE_IN}" == '.' ]] || [[ "${TITLE_IN}" == '..' ]] \
     || [[ "${TITLE_IN}" == */* ]] || [[ "${STRIPPED}" != "${TITLE_IN}" ]]; then
    md2x-die-usage "--title '$(md2x-title-display "${TITLE_IN}")' cannot be used as a file name."
  fi
}

# md2x-has-control-chars <text>
# Returns 0 when <text> contains a control character (0x01-0x1F, 0x7F), including tab and
# newline; the line- and tab-oriented input records and the messages that echo a name
# cannot carry them. NUL cannot occur in a bash string.
md2x-has-control-chars() {
  local TEXT_IN="${1-}" STRIPPED
  STRIPPED="$(printf '%s' "${TEXT_IN}" | LC_ALL=C tr -d '\001-\037\177'; printf x)"
  [[ "${STRIPPED}" != "${TEXT_IN}x" ]]
}

# md2x-strip-markdown-ext <path>
# Prints the basename of <path> with a trailing '.md' or '.markdown' removed, matched
# case-insensitively (so 'Notes.MARKDOWN' gives 'Notes'). A name that is nothing but the
# extension, or has neither, is printed unchanged. Uses parameter expansion, not
# 'basename', so a name starting with '-' needs no '--'. Prints no newline.
md2x-strip-markdown-ext() {
  local BASE="${1##*/}" LOWER STEM
  LOWER="$(printf '%s' "${BASE}" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  STEM="${BASE}"
  case "${LOWER}" in
    *.markdown) STEM="${BASE%?????????}";;
    *.md) STEM="${BASE%???}";;
  esac
  [[ -n "${STEM}" ]] || STEM="${BASE}"
  printf '%s' "${STEM}"
}

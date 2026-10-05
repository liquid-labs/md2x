# md2x command-line option parser. Sourced-only library: defining the table and the
# functions below has no side effects at source time. Kept compatible with bash 3.2.
#
# Replaces the bash-toolkit option parser. It still delegates the tokenizing
# to GNU getopt, which keeps the GNU conveniences md2x documents: unambiguous long-option
# prefixes ('--single' for '--single-page'), '--opt=value', an attached short value
# ('-p=x' sets the value '=x'), options permuted after positional arguments, and '--'.
# Nothing here needs 'brew' (it is only the last probe candidate), 'perl', or an 'eval' of
# generated code; the one 'eval set --' runs on getopt's own quoted output.

# The flag table: the single source of truth for every option. One row per option,
#
#   short|long|kind|VARIABLE
#
# 'short' is the one-letter form, or '-' when the option has none; 'long' is the long form
# without its leading dashes; 'kind' is 'flag' (sets VARIABLE to 'true') or 'value' (sets
# VARIABLE to the argument and 'VARIABLE_SET' to 'true'). Nothing derives a short form from
# a variable name. Keep exactly one row per line, as a single-quoted string, so a test can
# read this table by parsing the file.
MD2X_OPTION_TABLE=(
  'D|flatten-dirs|flag|FLATTEN_DIRS'
  'F|output-format|value|OUTPUT_FORMAT'
  'h|help|flag|HELP'
  '-|infer-title|flag|INFER_TITLE'
  '-|infer-version|flag|INFER_VERSION'
  '-|keep-intermediate|flag|KEEP_INTERMEDIATE'
  '-|list-files|flag|LIST_FILES'
  '-|no-toc|flag|NO_TOC'
  'p|output-path|value|OUTPUT_PATH'
  '-|quiet|flag|QUIET'
  '-|single-page|flag|SINGLE_PAGE'
  's|to-stdout|flag|TO_STDOUT'
  't|title|value|TITLE'
  '-|toc|flag|TOC'
)

# md2x-getopt-install-hints: the install guidance appended to a missing-getopt error.
md2x-getopt-install-hints() {
  printf '%s' "Install GNU getopt: 'brew install gnu-getopt' (macOS, Homebrew), 'port install getopt' (macOS, MacPorts), or the util-linux package on Linux."
}

# md2x-resolve-getopt
# Finds GNU getopt, accepting the first candidate whose '--test' exits 4. Probe order:
# 'MD2X_GETOPT', the Homebrew (Apple Silicon, Intel) and MacPorts locations, 'getopt' on
# 'PATH', and last, only when 'brew' is on 'PATH', the prefix 'brew' reports for gnu-getopt.
# Sets 'MD2X_GETOPT_BIN' on success. Return status: 0 found; 1 none found; 2 'MD2X_GETOPT'
# is set but is not GNU getopt (it never falls through to the other candidates).
md2x-resolve-getopt() {
  MD2X_GETOPT_BIN=''
  local _g_candidate _g_rc _g_prefix _g_brew

  if [[ -n "${MD2X_GETOPT:-}" ]]; then
    _g_rc=0
    "${MD2X_GETOPT}" --test >/dev/null 2>&1 || _g_rc=$?
    if (( _g_rc == 4 )); then
      MD2X_GETOPT_BIN="${MD2X_GETOPT}"
      return 0
    fi
    return 2
  fi

  for _g_candidate in \
      /opt/homebrew/opt/gnu-getopt/bin/getopt \
      /usr/local/opt/gnu-getopt/bin/getopt \
      /opt/local/bin/getopt; do
    [[ -x "${_g_candidate}" ]] || continue
    _g_rc=0
    "${_g_candidate}" --test >/dev/null 2>&1 || _g_rc=$?
    if (( _g_rc == 4 )); then
      MD2X_GETOPT_BIN="${_g_candidate}"
      return 0
    fi
  done

  _g_candidate="$(command -v getopt 2>/dev/null || true)"
  if [[ -n "${_g_candidate}" ]]; then
    _g_rc=0
    "${_g_candidate}" --test >/dev/null 2>&1 || _g_rc=$?
    if (( _g_rc == 4 )); then
      MD2X_GETOPT_BIN="${_g_candidate}"
      return 0
    fi
  fi

  _g_brew="$(command -v brew 2>/dev/null || true)"
  if [[ -n "${_g_brew}" ]]; then
    _g_prefix="$("${_g_brew}" --prefix gnu-getopt 2>/dev/null || true)"
    if [[ -n "${_g_prefix}" ]] && [[ -x "${_g_prefix}/bin/getopt" ]]; then
      _g_rc=0
      "${_g_prefix}/bin/getopt" --test >/dev/null 2>&1 || _g_rc=$?
      if (( _g_rc == 4 )); then
        MD2X_GETOPT_BIN="${_g_prefix}/bin/getopt"
        return 0
      fi
    fi
  fi

  return 1
}

# md2x-argv-requests-help <arg>...
# Fallback used only when no GNU getopt is resolvable: true when the arguments, scanned
# up to '--', ask for help. It skips the value of a value-taking option, so
# 'md2x --title -h' is not a help request, matching what getopt's parse would say.
md2x-argv-requests-help() {
  local _h_arg _h_rest _h_char _h_skip=''
  for _h_arg in "$@"; do
    if [[ -n "${_h_skip}" ]]; then
      _h_skip=''
      continue
    fi
    case "${_h_arg}" in
      --) return 1;;
      --help|--hel|--he|--h) return 0;;
      --output-path|--output-format|--title) _h_skip=true;;
      --*) ;;
      -?*)
        _h_rest="${_h_arg#-}"
        while [[ -n "${_h_rest}" ]]; do
          _h_char="${_h_rest%"${_h_rest#?}"}"
          _h_rest="${_h_rest#?}"
          case "${_h_char}" in
            h) return 0;;
            p|F|t)
              # The rest of the cluster is this option's value; with none, the next
              # argument is.
              [[ -n "${_h_rest}" ]] || _h_skip=true
              break;;
          esac
        done;;
    esac
  done
  return 1
}

# md2x-getopt-usage-error <getopt-stderr-line>
# Re-words getopt's first error line as an 'md2x: ' usage error (exit 2).
md2x-getopt-usage-error() {
  local _u_msg="${1:-}" _u_name _u_bt='`' _u_q="'"
  _u_msg="${_u_msg#getopt: }"
  _u_msg="${_u_msg#md2x: }"
  _u_msg="${_u_msg//${_u_bt}/${_u_q}}"
  case "${_u_msg}" in
    "invalid option -- "*)
      _u_name="${_u_msg#invalid option -- }"
      _u_name="${_u_name//\'/}"
      _u_msg="unrecognized option '-${_u_name}'";;
    "option requires an argument -- "*)
      _u_name="${_u_msg#option requires an argument -- }"
      _u_name="${_u_name//\'/}"
      _u_msg="option '-${_u_name}' requires an argument";;
    '')
      _u_msg='invalid command-line options';;
  esac
  md2x-die-usage "${_u_msg}"
}

# md2x-parse-options <arg>...
# Parses the command line against 'MD2X_OPTION_TABLE'. Sets every option variable (empty
# when absent, 'true' when given; for value-taking options the value, plus
# '<VARIABLE>_SET=true'), and leaves the positional arguments in the array
# 'MD2X_POSITIONAL'. The caller restores them with:
#
#   set -- ${MD2X_POSITIONAL[@]+"${MD2X_POSITIONAL[@]}"}
#
# Help works without GNU getopt: when none is resolvable, a help-only argv scan runs, and
# only if it finds no help request is the missing dependency fatal (exit 3).
md2x-parse-options() {
  local _p_row _p_short _p_long _p_kind _p_var
  local _p_shorts='' _p_longs='' _p_suffix

  # Defaults.
  for _p_row in "${MD2X_OPTION_TABLE[@]}"; do
    IFS='|' read -r _p_short _p_long _p_kind _p_var <<< "${_p_row}"
    printf -v "${_p_var}" '%s' ''
    [[ "${_p_kind}" != 'value' ]] || printf -v "${_p_var}_SET" '%s' ''
  done
  MD2X_POSITIONAL=()

  local _p_status=0
  md2x-resolve-getopt || _p_status=$?
  if (( _p_status != 0 )); then
    if md2x-argv-requests-help "$@"; then
      HELP=true
      return 0
    fi
    if (( _p_status == 2 )); then
      md2x-die-dependency "MD2X_GETOPT is set to '${MD2X_GETOPT}', which is not GNU getopt (its '--test' did not exit 4). Unset MD2X_GETOPT or point it at GNU getopt. $(md2x-getopt-install-hints)"
    fi
    md2x-die-dependency "GNU getopt is required but was not found (the BSD getopt that ships with macOS is not enough). $(md2x-getopt-install-hints) Or set MD2X_GETOPT to its path."
  fi

  # Build the getopt specification from the table.
  for _p_row in "${MD2X_OPTION_TABLE[@]}"; do
    IFS='|' read -r _p_short _p_long _p_kind _p_var <<< "${_p_row}"
    _p_suffix=''
    [[ "${_p_kind}" != 'value' ]] || _p_suffix=':'
    [[ "${_p_short}" == '-' ]] || _p_shorts="${_p_shorts}${_p_short}${_p_suffix}"
    _p_longs="${_p_longs:+${_p_longs},}${_p_long}${_p_suffix}"
  done

  local _p_err_file _p_out='' _p_rc=0 _p_err_line=''
  _p_err_file="$(mktemp "${TMPDIR:-/tmp}/md2x-getopt.XXXXXX")" \
    || md2x-die-runtime "Could not create a temporary file."
  _p_out="$("${MD2X_GETOPT_BIN}" -n md2x -o "${_p_shorts}" -l "${_p_longs}" -- "$@" 2>"${_p_err_file}")" \
    || _p_rc=$?
  IFS= read -r _p_err_line < "${_p_err_file}" || true
  rm -f -- "${_p_err_file}"
  (( _p_rc == 0 )) || md2x-getopt-usage-error "${_p_err_line}"

  # getopt's output is a safely quoted, normalized argument list: long options expanded
  # to their full names, '--opt=value' split, short clusters separated, '--' before the
  # positional arguments.
  eval set -- "${_p_out}"

  local _p_opt
  while (( $# > 0 )); do
    _p_opt="${1}"; shift
    if [[ "${_p_opt}" == '--' ]]; then
      break
    fi
    for _p_row in "${MD2X_OPTION_TABLE[@]}"; do
      IFS='|' read -r _p_short _p_long _p_kind _p_var <<< "${_p_row}"
      if [[ "${_p_opt}" == "--${_p_long}" ]] \
         || { [[ "${_p_short}" != '-' ]] && [[ "${_p_opt}" == "-${_p_short}" ]]; }; then
        if [[ "${_p_kind}" == 'value' ]]; then
          printf -v "${_p_var}" '%s' "${1}"
          printf -v "${_p_var}_SET" '%s' 'true'
          shift
        else
          printf -v "${_p_var}" '%s' 'true'
        fi
        break
      fi
    done
  done
  while (( $# > 0 )); do
    MD2X_POSITIONAL+=("${1}")
    shift
  done
}

#!/usr/bin/env bash

# Interpreter guard. This block must stay first in the file: ahead of the strict-mode 'set'
# lines and of every 'import'/'source', and it must use POSIX 'sh' syntax only (no '[[',
# no arrays such as 'BASH_VERSINFO', no '<(...)'), so that a shell that is not bash --
# dash, say, when someone runs 'sh md2x' on a system where sh is not bash -- can still
# parse and run it, and reports the problem instead of dying on later bash-only syntax.
# Bash and dash both read and execute a script one complete top-level command at a time,
# so this runs before any later line they might fail to parse.
#
# Rejected, each with exit 3 (missing or unusable dependency; see 'lib/errors.sh', which
# is not loaded yet, hence the plain 'printf'):
#   * a shell that is not bash ('BASH_VERSION' empty);
#   * bash older than 3.2 (the oldest supported, macOS /bin/bash is 3.2.57); version
#     strings look like '3.2.57(1)-release', so a prefix match on 'BASH_VERSION' is exact;
#   * bash running in POSIX mode (as when started as 'sh', or with '--posix'): process
#     substitution, which this script needs, is unavailable there in bash 3.2.
if [ -z "${BASH_VERSION:-}" ]; then
  printf '%s\n' 'md2x: requires bash 3.2 or later; this shell is not bash. Run it with bash.' >&2
  exit 3
fi
case "${BASH_VERSION}" in
  0.*|1.*|2.*|3.0*|3.1*)
    printf '%s\n' "md2x: requires bash 3.2 or later (found ${BASH_VERSION}). Run it with a newer bash." >&2
    exit 3;;
esac
case "$(set +o 2>/dev/null)" in
  *'set -o posix'*)
    printf '%s\n' 'md2x: requires bash 3.2 or later not in POSIX mode (as when run via sh). Run it with bash.' >&2
    exit 3;;
esac

# bash strict settings
set -o errexit # exit on errors
set -o nounset # exit on use of uninitialized variable
set -o pipefail

import lists

source ./lib/index.sh

# extract options (sets the option variables, and leaves the positional arguments in
# 'MD2X_POSITIONAL'; see 'lib/parse-options.sh')
md2x-parse-options "$@"
set -- ${MD2X_POSITIONAL[@]+"${MD2X_POSITIONAL[@]}"}

if [[ -n "${HELP}" ]]; then
  cat <<'EOF'
Usage:
  md2x [OPTIONS] <file>...
  md2x [OPTIONS] <directory>...
  md2x [OPTIONS] -

Converts Markdown documents into PDF, HTML, and DOCX, adding consistent
GitHub-style styling, automatic page headers and footers, batch directory
processing, and single-page concatenation of multiple Markdown files.

md2x accepts one or more file paths, one or more directory paths (searched
recursively for '*.md' and '*.markdown' files, matched case-insensitively),
or a single '-' argument to read Markdown
from stdin.

Options:
  -D, --flatten-dirs         Write all output files directly into
                              --output-path instead of mirroring the input
                              directory structure. Without this flag, each
                              output file is written under --output-path at
                              the path its input occupies relative to the
                              directory argument it was found under; a file
                              named directly on the command line goes
                              straight into --output-path.
      --infer-title          Embed the title (from --title, or otherwise the
                              filename) as document metadata via Pandoc
                              (e.g. the HTML <title> element).
      --infer-version        Add an inferred version string to the PDF
                              footer: the package.json version of the git
                              repository containing the first input (the
                              current directory for stdin), or 'working' when
                              its tree is dirty. Needs 'git' and 'jq', which
                              are required only for this flag.
      --keep-intermediate    Keep the per-run work directory of intermediate
                              build artifacts (CSS, Pandoc log, PDF overlay,
                              and so on) instead of deleting it after
                              conversion; its path is printed to stderr.
  -o, --output <file|->      Write the single output to <file>, creating its
                              directory as needed ('-' is --to-stdout). Valid
                              only when exactly one output results (one input
                              file, stdin, or --single-page). The format is
                              inferred from a .pdf, .html, or .docx extension
                              when -F is absent; an unrecognized extension
                              writes the default format (pdf) to <file> as
                              given. Conflicts with -p.
  -p, --output-path <path>   Directory to write output files into. Default: '.'.
                              Conflicts with -o.
  -F, --output-format <format>
                              Output format: 'pdf' (default), 'html', or
                              'docx' (case-insensitive).
  -t, --title <title>        Document title; used for the output filename
                              (unless -o is given) and the PDF header text. Only honored when
                              exactly one file will be converted outside
                              --single-page (a lone directly-named file,
                              or a directory search resolving to exactly
                              one file); passing --title with more than
                              one file in that path is a fatal error.
      --single-page          Concatenate all input Markdown files into a
                              single document before conversion.
      --quiet                Suppress the "Created <file>" status message.
      --list-files           Print only the generated file path(s), instead
                              of "Created <file>".
  -s, --to-stdout            Write the single converted output to stdout and
                              nothing to disk (implies --quiet). Needs exactly
                              one output; conflicts with --list-files and
                              with -o <file>.
      --toc                  Force a table of contents; overrides the
                              default heuristic below (see --no-toc).
      --no-toc               Suppress the table of contents. md2x
                              generates the TOC itself for pdf, html, and
                              docx alike, placed at a '<!-- md2x:toc -->'
                              marker (or after the title, absent one).
                              With neither flag, a TOC is added only to
                              documents of more than about two pages with
                              four or more top-level sections. Giving both
                              flags is an error.
  -h, --help                 Print this help text and exit.
      --version              Print the md2x version and exit.

Long options may be abbreviated to any unambiguous prefix (--single for
--single-page), and a value may be attached with '=' (--title=Report).

Exit codes:
  0  Success.
  1  Runtime or conversion failure.
  2  Usage error (bad option, bad argument, or unusable input path).
  3  Missing or unusable dependency (for example pandoc, or GNU getopt).

Examples:
  # Convert a single Markdown file to PDF (the default format)
  md2x report.md

  # Convert every *.md and *.markdown file in a directory to HTML, with an inferred title and version footer
  md2x --output-format html --infer-title --infer-version --output-path ./out ./docs

  # Concatenate several files into one PDF
  md2x --single-page --title "Combined Report" chapter1.md chapter2.md chapter3.md

  # Read Markdown from stdin
  cat report.md | md2x -

Homepage: https://github.com/liquid-labs/md2x
EOF
  exit 0
fi

if [[ -n "${VERSION}" ]]; then
  # The placeholder is replaced with the package.json version when 'bin/md2x' is built
  # (see the Makefile); nothing reads package.json at run time for this.
  printf 'md2x %s\n' '@MD2X_VERSION@'
  exit 0
fi

# No input at all is a usage error, not a silent success.
(( $# > 0 )) \
  || md2x-die-usage "no input given. Usage: md2x [OPTIONS] <file>... | <directory>... | -"

# 'command -v' is quiet on a miss, so no raw shell text reaches stderr. 'git' and 'jq' are
# not in this list: they are needed only for '--infer-version' and checked just below.
for EXEC in gs pandoc pdftk python3; do
  command -v "${EXEC}" >/dev/null 2>&1 \
    || md2x-die-dependency "Required executable '${EXEC}' not found for 'md2x'. Add to 'PATH' or install."
done
md2x-check-pandoc-version
[[ -z "${INFER_VERSION}" ]] || md2x-require-infer-version-tools

# process options
test_formats() {
  local TEST_FORMAT
  for TEST_FORMAT in ${OUTPUT_FORMATS}; do
    [[ "${OUTPUT_FORMAT}" == "${TEST_FORMAT}" ]] && return 0
  done
  return 1
}
# 'OUTPUT_FORMAT_GIVEN' is empty when '-F' was absent (the '-o' extension inference below
# keys off that), before the default is applied.
OUTPUT_FORMAT_GIVEN="${OUTPUT_FORMAT}"
[[ -n "${OUTPUT_FORMAT}" ]] || OUTPUT_FORMAT='pdf'
# 'tr' lowercases here because '${var,,}' needs bash 4; the value is also validated
# case-insensitively, so '-F PDF' is the same as '-F pdf'.
OUTPUT_FORMAT="$(printf '%s' "${OUTPUT_FORMAT}" | tr '[:upper:]' '[:lower:]')"
test_formats \
  || md2x-die-usage "unsupported output format '$(md2x-title-display "${OUTPUT_FORMAT_GIVEN}")' (expected pdf|html|docx)"

# '-o, --output <file|->': an explicit output file. Validated here, ahead of any input work.
# 'OUTPUT_TARGET_FILE' is the explicit file ('-o -' is '--to-stdout' and has none).
OUTPUT_TARGET_FILE=''
if [[ -n "${OUTPUT_FILE_SET}" ]]; then
  [[ -n "${OUTPUT_FILE}" ]] \
    || md2x-die-usage "'-o'/'--output' needs a file name, or '-' for stdout."
  ! md2x-has-control-chars "${OUTPUT_FILE}" \
    || md2x-die-usage "output path '$(md2x-title-display "${OUTPUT_FILE}")' contains control characters."
  [[ -z "${OUTPUT_PATH_SET}" ]] \
    || md2x-die-usage "'-o'/'--output' cannot be combined with '-p'/'--output-path'."
  if [[ "${OUTPUT_FILE}" == '-' ]]; then
    TO_STDOUT=true
  else
    [[ -z "${TO_STDOUT}" ]] \
      || md2x-die-usage "'-o'/'--output' <file> cannot be combined with '--to-stdout'."
    # A trailing '/' names a directory, which '-o' (a file) cannot be; refusing it here keeps
    # delivery from failing after planning and leaving an empty directory behind.
    [[ "${OUTPUT_FILE}" != */ ]] \
      || md2x-die-usage "'-o'/'--output' '$(md2x-title-display "${OUTPUT_FILE}")' ends in '/' and names a directory;" \
        "give a file name, or use '-p'/'--output-path' for a directory."
    OUTPUT_TARGET_FILE="${OUTPUT_FILE}"
    # Format inference: a recognized extension sets the format when '-F' is absent and must
    # agree with '-F' when it is given; an unrecognized one leaves the default format and
    # the path is used exactly as given.
    case "$(md2x-lowercase "${OUTPUT_TARGET_FILE##*/}")" in
      *.pdf) EXT_FORMAT='pdf';;
      *.html) EXT_FORMAT='html';;
      *.docx) EXT_FORMAT='docx';;
      *) EXT_FORMAT='';;
    esac
    if [[ -n "${EXT_FORMAT}" ]]; then
      if [[ -z "${OUTPUT_FORMAT_GIVEN}" ]]; then
        OUTPUT_FORMAT="${EXT_FORMAT}"
      elif [[ "${OUTPUT_FORMAT}" != "${EXT_FORMAT}" ]]; then
        md2x-die-usage "'-F ${OUTPUT_FORMAT}' contradicts the '.${EXT_FORMAT}' extension of" \
          "'-o $(md2x-title-display "${OUTPUT_TARGET_FILE}")'."
      fi
    fi
  fi
fi
[[ -z "${TO_STDOUT}" ]] || [[ -z "${LIST_FILES}" ]] \
  || md2x-die-usage "'--to-stdout' (or '-o -') cannot be combined with '--list-files'."

# '--toc' and '--no-toc' resolve to a single 'TOC_MODE' the pipeline consumes; giving
# both is fatal, and must be checked before 'ensure-weasyprint' below, which can
# trigger a minute-long network install on a cold machine -- the conflict must abort
# before any conversion work begins.
[[ -z "${TOC}" ]] || [[ -z "${NO_TOC}" ]] \
  || md2x-die-usage "Cannot specify both '--toc' and '--no-toc'."
TOC_MODE='auto'
[[ -z "${TOC}" ]] || TOC_MODE='on'
[[ -z "${NO_TOC}" ]] || TOC_MODE='off'

# Input-path processing (which of SEARCH_DIRS/MD_FILES/STDIN_MODE the invocation resolves
# to) is done here, ahead of 'ensure-weasyprint' below, rather than in its previous
# position further down: the '--title' conflict gate that follows needs to know how
# many files this invocation will convert, and 'ensure-weasyprint' can trigger a
# minute-long network install on a cold machine that a doomed (conflicting) invocation
# should never pay for. Neither this block nor the gate reads 'OUTPUT_PATH' or anything
# 'ensure-weasyprint' sets, and 'OUTPUT_PATH's own default assignment and
# 'ensure-weasyprint' do not read 'SEARCH_DIRS'/'MD_FILES'/'STDIN_MODE', so this reordering
# is safe in both directions.
SEARCH_DIRS=''
MD_FILES=''
# process args
# 'STDIN_MODE' is non-empty when the sole argument is '-'; the document itself is copied
# byte for byte into the work directory once that exists (see 'STDIN_FILE' below). A '-'
# next to any other input is a usage error.
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
      list-add-item SEARCH_DIRS "${TEST_PATH}"
    elif [[ -f "${TEST_PATH}" ]]; then
      [[ -r "${TEST_PATH}" ]] \
        || md2x-die-usage "'$(md2x-title-display "${TEST_PATH}")' is not readable."
      list-add-item MD_FILES "${TEST_PATH}"
    else
      # Planner decision: a nonexistent (or otherwise unusable) input argument is a usage
      # error (exit 2), not a runtime failure -- the caller named something invalid.
      md2x-die-usage "'$(md2x-title-display "${TEST_PATH}")' is neither a file nor a directory. Bailing out."
    fi
  done
fi

# Build the resolved input list ONCE, before any conversion: 'RESOLVED_INPUTS' holds one
# '<md-file><tab><search-root>' record per file to convert, directly named files first
# (empty search-root field), then the recursive search results sorted by path; each
# physical file appears once, the first occurrence winning (so its search root decides
# its output location). 'RESOLVED_COUNT' is its length. Both the '--title' gate below
# and the conversion loop consume this list, so they cannot drift.
#
# A search that fails (an unreadable root) stops the search of any later root, keeps what
# was found so far, and is reported once the files found so far were converted; see
# 'exit-codes.bats' "unreadable search root" cases and followup 8ZmD.
RESOLVED_INPUTS=''
RESOLVED_COUNT=0
SEARCH_ERROR_ROOT=''
if [[ -z "${STDIN_MODE}" ]]; then
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
    # A root starting with '-' would be read by 'find' as an option, so it is searched as
    # './<root>' and the './' is stripped from each result to keep the names as the user gave them.
    FIND_ROOT="${ROOT_DIR}"
    [[ "${ROOT_DIR}" != -* ]] || FIND_ROOT="./${ROOT_DIR}"
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
    (( ROOT_FOUND > 0 )) || list-add-item EMPTY_DIRS "${ROOT_DIR}"
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
fi

# '--title'/'-t' only applies to a single-file conversion: the main per-file loop
# derives each output's filename (and, via 'generate-page()', the '--infer-title'
# metadata) from 'TITLE', so an explicit '--title' with more than one file in play
# would silently apply to only the loop's last iteration. This is checked only for the
# non-'--single-page'/non-stdin path -- the other two input modes always produce
# exactly one output file and already honor '--title' correctly. The count is the length
# of the resolved, deduplicated input list built above, the same list the conversion
# loop consumes.
if [[ -z "${SINGLE_PAGE}" ]] && [[ -z "${STDIN_MODE}" ]]; then
  TITLE_PRECEDENCE_FILE_COUNT="${RESOLVED_COUNT}"

  if [[ -n "${TITLE_SET:-}" ]] && (( TITLE_PRECEDENCE_FILE_COUNT > 1 )); then
    md2x-die-usage "Cannot use '--title'/'-t' with more than one input file" \
      "(${TITLE_PRECEDENCE_FILE_COUNT} files would be converted); '--title' only" \
      "applies to a single-file conversion. Use '--single-page' to combine multiple" \
      "files under one title, or omit '--title' to use each file's own basename."
  fi
fi

# An explicit '--title' becomes the output file name, so validate it before any conversion
# work (and before 'ensure-weasyprint', which can trigger a network install).
# With '-o' or '--to-stdout' no file name is derived from the title (it is display-only), so
# any printable title is accepted; the metadata and PostScript sinks still encode it.
[[ -z "${TITLE_SET:-}" ]] || [[ -n "${OUTPUT_TARGET_FILE}" ]] || [[ -n "${TO_STDOUT}" ]] \
  || md2x-validate-title "${TITLE}"

# '-o' and '--to-stdout' are valid only when exactly one output results.
if [[ -n "${STDIN_MODE}" ]] || [[ -n "${SINGLE_PAGE}" ]]; then
  OUTPUT_COUNT=1
else
  OUTPUT_COUNT="${RESOLVED_COUNT}"
fi
if (( OUTPUT_COUNT != 1 )) && { [[ -n "${OUTPUT_TARGET_FILE}" ]] || [[ -n "${TO_STDOUT}" ]]; }; then
  md2x-die-usage "'-o'/'--output' and '--to-stdout' need exactly one output, but ${OUTPUT_COUNT}" \
    "files would be converted. Name one input, or use '--single-page' to combine them."
fi

# '--output-path': trailing slashes are dropped ('o3/' prints 'o3/a.html'; '/' stays '/'),
# and an existing non-directory is a usage error.
[[ -n "${OUTPUT_PATH}" ]] || OUTPUT_PATH='.'
if [[ -z "${OUTPUT_TARGET_FILE}" ]] && [[ -z "${TO_STDOUT}" ]]; then
  ! md2x-has-control-chars "${OUTPUT_PATH}" \
    || md2x-die-usage "output path '$(md2x-title-display "${OUTPUT_PATH}")' contains control characters."
  OUTPUT_PATH="$(md2x-trim-trailing-slashes "${OUTPUT_PATH}")"
  if [[ -e "${OUTPUT_PATH}" ]] && [[ ! -d "${OUTPUT_PATH}" ]]; then
    md2x-die-usage "'-p'/'--output-path' '$(md2x-title-display "${OUTPUT_PATH}")' exists and is not a directory."
  fi
fi

# Target planning. Before any conversion (and before 'ensure-weasyprint' below, which can
# trigger a minute-long install), compute every output target from the resolved input list
# and run every check against it; the conversion loop consumes 'PLANNED_TARGETS' and
# 'SINGLE_TARGET' and recomputes nothing.
#   PLANNED_TARGETS  one '<md-file><tab><target>' record per file, outside --single-page/stdin
#   SINGLE_TARGET    the target of the one --single-page/stdin output
# With '--to-stdout' no destination file exists; targets stay empty and the output is
# staged in the work directory only.
PLANNED_TARGETS=''
SINGLE_TARGET=''
if [[ -z "${TO_STDOUT}" ]]; then
  NL=$'\n'
  TAB=$'\t'
  INPUT_KEYS="${NL}"
  TARGET_KEYS="${NL}"
  while IFS=$'\t' read -r PLAN_FILE PLAN_ROOT; do
    [[ -n "${PLAN_FILE}" ]] || continue
    PLAN_KEY="$(md2x-lowercase "$(md2x-canonical-target "${PLAN_FILE}")")"
    INPUT_KEYS="${INPUT_KEYS}${PLAN_KEY}${TAB}${PLAN_FILE}${NL}"
  done <<< "${RESOLVED_INPUTS}"

  # md2x-plan-register <source-label> <target>: checks <target> and records it.
  md2x-plan-register() {
    local REG_SOURCE="${1}" REG_TARGET="${2}" REG_KEY REG_OTHER
    md2x-check-output-location "${REG_TARGET}"
    REG_KEY="$(md2x-lowercase "$(md2x-canonical-target "${REG_TARGET}")")"
    if REG_OTHER="$(md2x-lookup-record "${INPUT_KEYS}" "${REG_KEY}")"; then
      md2x-die-usage "output '$(md2x-title-display "${REG_TARGET}")' would overwrite its own input" \
        "'$(md2x-title-display "${REG_OTHER}")'."
    fi
    if REG_OTHER="$(md2x-lookup-record "${TARGET_KEYS}" "${REG_KEY}")"; then
      md2x-die-usage "'$(md2x-title-display "${REG_OTHER}")' and '$(md2x-title-display "${REG_SOURCE}")'" \
        "would both be written to '$(md2x-title-display "${REG_TARGET}")'."
    fi
    TARGET_KEYS="${TARGET_KEYS}${REG_KEY}${TAB}${REG_SOURCE}${NL}"
  }

  if [[ -n "${STDIN_MODE}" ]] || [[ -n "${SINGLE_PAGE}" ]]; then
    if [[ -n "${OUTPUT_TARGET_FILE}" ]]; then
      SINGLE_TARGET="${OUTPUT_TARGET_FILE}"
    else
      SINGLE_TARGET="$(md2x-join-path "${OUTPUT_PATH}" "${TITLE:-output}.${OUTPUT_FORMAT}")"
    fi
    md2x-plan-register "${SINGLE_PAGE:+--single-page}${STDIN_MODE:+stdin}" "${SINGLE_TARGET}"
  else
    while IFS=$'\t' read -r PLAN_FILE PLAN_ROOT; do
      [[ -n "${PLAN_FILE}" ]] || continue
      if [[ -n "${OUTPUT_TARGET_FILE}" ]]; then
        PLAN_TARGET="${OUTPUT_TARGET_FILE}"
      else
        if [[ -n "${TITLE_SET:-}" ]]; then PLAN_TITLE="${TITLE}"; else PLAN_TITLE="$(md2x-strip-markdown-ext "${PLAN_FILE}")"; fi
        PLAN_DIR="${OUTPUT_PATH}"
        if [[ -z "${FLATTEN_DIRS}" ]]; then
          PLAN_REL="$(relative-output-dir "${PLAN_FILE}" "${PLAN_ROOT}")"
          [[ -z "${PLAN_REL}" ]] || PLAN_DIR="$(md2x-join-path "${PLAN_DIR}" "${PLAN_REL}")"
        fi
        PLAN_TARGET="$(md2x-join-path "${PLAN_DIR}" "${PLAN_TITLE}.${OUTPUT_FORMAT}")"
      fi
      md2x-plan-register "${PLAN_FILE}" "${PLAN_TARGET}"
      PLANNED_TARGETS="${PLANNED_TARGETS}${PLAN_FILE}${TAB}${PLAN_TARGET}${NL}"
    done <<< "${RESOLVED_INPUTS}"
  fi
fi

[[ "${OUTPUT_FORMAT}" == 'pdf' ]] && ensure-weasyprint

[[ -z "${TO_STDOUT}" ]] || QUIET=true

# Used by 'generate-page()' for the footer. Computed only with '--infer-version', against
# the git repository of the first input's directory (the cwd for stdin), so without the
# flag nothing here touches 'git', 'jq', or 'package.json'. Empty when no version could be
# determined (a warning was already printed); the footer then omits it.
INFERRED_VERSION=''
if [[ -n "${INFER_VERSION}" ]]; then
  INFER_DIR='.'
  if [[ -z "${STDIN_MODE}" ]]; then
    INFER_FIRST="${RESOLVED_INPUTS%%$'\t'*}"
    INFER_DIR="$(md2x-parent-dir "${INFER_FIRST}")"
  fi
  INFERRED_VERSION="$(md2x-infer-version "${INFER_DIR}")"
fi

case "${OUTPUT_FORMAT}" in
  pdf|html)
    INTERMEDIATE_FORMAT=html5;;
  *)
    INTERMEDIATE_FORMAT="${OUTPUT_FORMAT}";;
esac

# '$CSS' (the embedded github.css content) is static, deterministic content that never
# varies across 'generate-page()' calls within one md2x invocation, but the per-file
# loop below (and the single-page/stdin call further down) can invoke 'generate-page()'
# many times. Create the backing temp file once, here, rather than once per call --
# see followup QBKX. The 'bash-rollup' inline directive resolves relative to this
# file's own directory ('src/cli'), hence 'lib/github.css' rather than the bare
# './github.css' generate-page.sh (in 'src/cli/lib') used.
CSS=$(cat <<'EOF'
source ./lib/github.css # bash-rollup-no-recur
EOF
)

# 'src/cli/lib/toc-preprocess.py' is a source file, not a '.sh' one, so it travels
# through the rolled-up CLI the same way -- inlined verbatim by 'bash-rollup', then
# handed to 'python3 -c' at the call site in 'generate-page()' rather than written out
# to a temp file, since the document itself already needs to occupy stdin. Resolves
# relative to this file's own directory ('src/cli'), same as '$CSS' above.
TOC_PREPROCESSOR=$(cat <<'EOF'
source ./lib/toc-preprocess.py # bash-rollup-no-recur
EOF
)

# One per-run work directory holds every intermediate file this invocation creates (the
# CSS file, the body-wrapper include files, the TOC-preprocessed Markdown, the
# '--single-page' concatenation, the Pandoc log, the PDF overlay, the pdftk output, and
# the search-root error signal), so nothing but the requested outputs is ever written to
# the cwd or the output directory. It is created once, here -- after option and input
# validation, so a usage error never creates it -- and before any conversion work. The
# template's 'X's must be trailing: BSD 'mktemp' only randomizes a trailing run of 'X's.
MD2X_WORK_DIR=''
MD2X_TMP_ROOT="${TMPDIR:-/tmp}"
while [[ "${MD2X_TMP_ROOT}" == */ ]] && [[ "${MD2X_TMP_ROOT}" != '/' ]]; do
  MD2X_TMP_ROOT="${MD2X_TMP_ROOT%/}"
done
MD2X_WORK_DIR="$(mktemp -d "${MD2X_TMP_ROOT}/md2x.XXXXXX" 2>/dev/null)" \
  || md2x-die-runtime "could not create a work directory under '${MD2X_TMP_ROOT}'."

# One cleanup trap: it removes the work directory (a no-op while the variable is unset or
# empty) unless '--keep-intermediate' was given. bash runs an 'EXIT' trap on every exit
# path -- normal completion, 'errexit', and every 'md2x-die-*' -- so nothing leaks however
# the run ends. Bash keeps only one handler per signal, so any later need must be folded
# into this trap rather than registered separately.
#
# Exit-status backstop (keep this in any rewrite of this trap): the trap also normalizes
# any exit status outside the 0-3 contract (see 'lib/errors.sh') to 1, so a tool that
# slips past the explicit '|| md2x-die-runtime' guards under 'errexit' (e.g. a stub or
# real tool exiting 64) can never leak its own status as md2x's.
#
# Lost-status backstop (also keep): bash 3.2 -- but not bash 4.4 and later -- has a quirk
# where a fatal 'nounset' expansion error (e.g. an unbound variable inside 'generate-page()'
# or the conversion loop below) ends a non-interactive script with '$?' reading 0 inside
# the 'EXIT' trap, and the script then exits with the trap's status, 0, silently reporting
# success for a failed run. Without any 'EXIT' trap, 3.2 exits 1 correctly; the trap is
# what masks it. Every legitimate success path reaches the 'MD2X_COMPLETED=true' line at the
# very end of this script, so a trap that sees status 0 without it knows the run was cut
# short and turns that into exit 1 (a runtime failure) on every supported bash.
trap 'MD2X_EXIT_STATUS=$?
      [[ -n "${KEEP_INTERMEDIATE:-}" ]] || [[ -z "${MD2X_WORK_DIR:-}" ]] \
        || rm -rf "${MD2X_WORK_DIR}" 2>/dev/null
      if (( MD2X_EXIT_STATUS == 0 )) && [[ -z "${MD2X_COMPLETED:-}" ]]; then
        md2x-emit "md2x:" "1;31" "run aborted before completion; see the error above."
        exit 1
      fi
      if (( MD2X_EXIT_STATUS < 0 || MD2X_EXIT_STATUS > 3 )); then exit 1; fi' EXIT

# WeasyPrint (the pinned '--pdf-engine') MIME-sniffs '--css' from its path extension, so
# it needs a real file ending in '.css' rather than a process-substitution '/dev/fd/N'
# path. The work directory gives it a fixed '.css' name. '$CSS' is static, so the file is
# written once per run, not once per 'generate-page()' call (followup QBKX).
#
# Every write into the work directory is guarded: the redirect's own error is silenced
# (stderr is redirected first) and a failure (a full disk, say) is reported once through
# 'md2x-work-write-failed' rather than as a raw shell error.
md2x-work-write-failed() {
  md2x-die-runtime "could not write to the work directory '$(md2x-title-display "${MD2X_WORK_DIR}")'."
}
CSS_FILE="${MD2X_WORK_DIR}/github.css"
printf '%s' "${CSS}" 2>/dev/null > "${CSS_FILE}" || md2x-work-write-failed

# HTML output must not reference the work directory: a '--css' link would point at a file
# deleted at exit, leaving every HTML file unstyled. So HTML embeds the stylesheet inline
# via '--include-in-header' instead, from this file ('<style>' + '${CSS}' + '</style>').
STYLE_HEADER_FILE="${MD2X_WORK_DIR}/style.html"
{
  printf '%s\n' '<style>'
  printf '%s\n' "${CSS}"
  printf '%s\n' '</style>'
} 2>/dev/null > "${STYLE_HEADER_FILE}" || md2x-work-write-failed

# 'github.css' scopes every rule under a bare '.markdown-body' class selector, and neither
# Pandoc's default html5 template nor a '-V'/'--variable' metadata hook puts that class
# anywhere in the generated document. '--include-before-body'/'--include-after-body'
# inject literal content just inside the opening/closing '<body>' tag, so wrapping the
# whole rendered body in this div satisfies those selectors exactly as well as a class on
# '<body>' itself would. Static content, so written once per run.
BODY_OPEN_FILE="${MD2X_WORK_DIR}/body-open.html"
BODY_CLOSE_FILE="${MD2X_WORK_DIR}/body-close.html"
printf '%s' '<div class="markdown-body">' 2>/dev/null > "${BODY_OPEN_FILE}" || md2x-work-write-failed
printf '%s' '</div>' 2>/dev/null > "${BODY_CLOSE_FILE}" || md2x-work-write-failed

# The link/image filter, and the file it records missing images in ('generate-page()'
# reports them).
LINK_FILTER_FILE="${MD2X_WORK_DIR}/md2x-links.lua"
# Written with a plain heredoc, not a '$(cat <<EOF ...)' substitution: bash 3.2 mis-parses
# quotes and parentheses inside a heredoc nested in a command substitution, and the Lua
# source has both. The terminator is unique so a bare 'EOF' line in the Lua source cannot
# truncate it.
cat 2>/dev/null > "${LINK_FILTER_FILE}" <<'MD2X_LUA_EOF' || md2x-work-write-failed
source ./lib/md2x-links.lua # bash-rollup-no-recur
MD2X_LUA_EOF
MISSING_IMAGES_FILE="${MD2X_WORK_DIR}/missing-images.txt"

# Fixed names for the remaining intermediates; none is derived from '--title' or any
# other user input.
SINGLE_PAGE_FILE="${MD2X_WORK_DIR}/single-page.md"
PREPROCESSED_FILE="${MD2X_WORK_DIR}/preprocessed.md"
PANDOC_LOG_FILE="${MD2X_WORK_DIR}/pandoc.log"
OVERLAY_FILE="${MD2X_WORK_DIR}/overlay.pdf"
STAMPED_FILE="${MD2X_WORK_DIR}/combined.pdf"
STDIN_FILE="${MD2X_WORK_DIR}/stdin.md"

# Stdin mode: copy the document byte for byte (no 'read' loop, so no stripped indentation,
# eaten backslashes, or dropped unterminated last line). A zero-byte capture is a usage
# error; the trap above removes the work directory on that exit. Whitespace-only input is
# not empty.
if [[ -n "${STDIN_MODE}" ]]; then
  { cat > "${STDIN_FILE}"; } 2>/dev/null || md2x-die-runtime "could not read standard input."
  [[ -s "${STDIN_FILE}" ]] || md2x-die-usage "no input on stdin."
fi

# Announce the retained work directory once, to stderr (never stdout, which is the parsed
# data channel for '--list-files'/'--to-stdout'), and not gated on '--quiet': '--quiet'
# only suppresses the per-file "Created ..." status line, not this opt-in notice.
[[ -z "${KEEP_INTERMEDIATE}" ]] \
  || echo "md2x: kept intermediate files in '${MD2X_WORK_DIR}'" >&2

# Staged result of each conversion: a fixed name in the work directory, never derived from
# '--title' or any other user input (see the delivery step in 'generate-page()').
BASE_OUTPUT="${MD2X_WORK_DIR}/output.${OUTPUT_FORMAT}"
FINAL_OUTPUT=''

if [[ -n "${SINGLE_PAGE}" ]]; then
  # Per-run secret the source markers carry. The filter honors only a marker bearing it, so
  # a '<!-- md2x:source-dir=... -->' comment written in a source cannot redirect image
  # resolution or warning attribution.
  MD2X_MARKER_NONCE="$(md2x-new-nonce)" \
    || md2x-die-runtime "could not read random data to build the source-marker token."
  # Concatenate every resolved source into one document.
  while IFS=$'\t' read -r MD_FILE SEARCH_ROOT; do
    [[ -n "${MD_FILE}" ]] || continue
    [[ -r "${MD_FILE}" ]] || md2x-die-runtime "cannot read '$(md2x-title-display "${MD_FILE}")'."
    # Validate each source on its own so an encoding error names that file, not the
    # combined work-directory file.
    python3 -c "${TOC_PREPROCESSOR}" --validate \
      --source-name "$(md2x-title-display "${MD_FILE}")" < "${MD_FILE}" || exit 1
    # The marker (blank lines around it) tells the filter which directory this source's
    # images are relative to. An unterminated code fence or raw HTML block in a source
    # would swallow the next marker (a known limitation).
    { printf '\n'; md2x-source-marker "${MD_FILE}" "${MD2X_MARKER_NONCE}"; printf '\n'; cat -- "${MD_FILE}"; echo; } \
      2>/dev/null >> "${SINGLE_PAGE_FILE}" \
      || md2x-die-runtime "could not read '$(md2x-title-display "${MD_FILE}")' or write the combined document."
  done <<< "${RESOLVED_INPUTS}"
fi

if [[ -z "${STDIN_MODE}" ]] && [[ -z "${SINGLE_PAGE}" ]]; then
  # Each record of the plan is '<md-file><tab><target>' (empty target for '--to-stdout').
  while IFS=$'\t' read -r MD_FILE FINAL_OUTPUT; do
    [[ -n "${MD_FILE}" ]] || continue
    # '--to-stdout' has no planned target (the fallback list below carries search roots).
    [[ -z "${TO_STDOUT}" ]] || FINAL_OUTPUT=''
    # An explicit '--title' is honored as-is; the upfront gate above already guarantees
    # at most one file whenever 'TITLE_SET' is non-empty. Absent '--title', fall back to
    # each file's own basename.
    [[ -n "${TITLE_SET:-}" ]] || TITLE="$(md2x-strip-markdown-ext "${MD_FILE}")"
    generate-page
  done <<< "${PLANNED_TARGETS:-${RESOLVED_INPUTS}}"
fi

if [[ -n "${SINGLE_PAGE}" ]] || [[ -n "${STDIN_MODE}" ]]; then
  TITLE="${TITLE:-output}"
  FINAL_OUTPUT="${SINGLE_TARGET}"
  [[ -z "${SINGLE_PAGE}" ]] || MD_FILE="${SINGLE_PAGE_FILE}"
  [[ -z "${STDIN_MODE}" ]] || MD_FILE="${STDIN_FILE}"
  generate-page
fi

# A failed search (an unreadable root) was recorded while the input list was built; the
# files found before it were converted above, and the run still ends loudly rather than
# letting partial results pass as a silent success. Followup 8ZmD.
[[ -z "${SEARCH_ERROR_ROOT}" ]] \
  || md2x-die-runtime "could not fully search '$(md2x-title-display "${SEARCH_ERROR_ROOT}")' for Markdown files. Bailing out."

# Reached only when every step above succeeded; see the lost-status backstop on the 'EXIT'
# trap.
MD2X_COMPLETED=true

#!/usr/bin/env bash

# bash strict settings
set -o errexit # exit on errors
set -o nounset # exit on use of uninitialized variable
set -o pipefail

import echoerr
import lists
import options
# import prompt

source ./lib/index.sh

# require-answer "Host OU or context path? (E.g., 'DevOps-ProductionMainApp', 'Security-SDLCTest', etc.)" HOST_OU_PATH
# get-answer ""

# export HOST_OU_PATH

# At one point, we supported the idea of generating "final" yaml files from a gucci processed template file. It turned out to be unecessary (I think), but want to keep this around till confirmed.

# $(npm bin)/gucci ./cloud/auths/environment/devops-admin-auths.yaml.tmpl

# extract options
eval "$(setSimpleOptions --script FLATTEN_DIRS:D INFER_TITLE: INFER_VERSION KEEP_INTERMEDIATE: OUTPUT_PATH:p= OUTPUT_FORMAT:F= TITLE:t= SINGLE_PAGE QUIET LIST_FILES TO_STDOUT:s NO_TOC HELP:h -- "$@")"

if [[ -n "${HELP}" ]]; then
  cat <<'EOF'
Usage:
  md2x [OPTIONS] <file>...
  md2x [OPTIONS] <directory>...
  md2x [OPTIONS] -

Converts Markdown documents into PDF, HTML, DOCX, and other Pandoc-supported
formats, adding consistent GitHub-style styling, automatic page headers and
footers, batch directory processing, and single-page concatenation of
multiple Markdown files.

md2x accepts one or more file paths, one or more directory paths (searched
recursively for '*.md' files), or a single '-' argument to read Markdown
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
                              footer: the package.json version when
                              'git status --porcelain' is clean, or
                              'working' when the tree is dirty.
      --keep-intermediate    Keep intermediate build artifacts (the Pandoc
                              log and the PDF header/footer overlay) instead
                              of deleting them after conversion.
  -p, --output-path <path>   Directory to write output files into. Default: '.'.
  -F, --output-format <format>
                              Output format: 'pdf' (default), 'html', or
                              'docx'.
  -t, --title <title>        Document title; used for the output filename
                              and the PDF header text.
      --single-page          Concatenate all input Markdown files into a
                              single document before conversion.
      --quiet                Suppress the "Created <file>" status message.
      --list-files           Print only the generated file path(s), instead
                              of "Created <file>".
  -s, --to-stdout            Write the converted output to stdout (implies
                              --quiet).
      --no-toc               Suppress the table of contents Pandoc otherwise
                              adds for pdf/html output (docx output never
                              receives an automatic TOC).
  -h, --help                 Print this help text and exit.

Examples:
  # Convert a single Markdown file to PDF (the default format)
  md2x report.md

  # Convert every *.md file in a directory to HTML, with an inferred title and version footer
  md2x --output-format html --infer-title --infer-version --output-path ./out ./docs

  # Concatenate several files into one PDF
  md2x --single-page --title "Combined Report" chapter1.md chapter2.md chapter3.md

  # Read Markdown from stdin
  cat report.md | md2x -
EOF
  exit 0
fi

for EXEC in gs pandoc pdftk python3 jq; do
  type "${EXEC}" >/dev/null || {
    echo "Required executable '${EXEC}' not found for 'md2x'. Add to 'PATH' or install." >&2
    exit 2
  }
done

# process options
test_formats() {
  local TEST_FORMAT
  for TEST_FORMAT in ${OUTPUT_FORMATS}; do
    [[ "${OUTPUT_FORMAT}" == "${TEST_FORMAT}" ]] && return 0
  done
  return 1
}
[[ -n "${OUTPUT_FORMAT}" ]] || OUTPUT_FORMAT='pdf'
test_formats || echoerrandexit "Unsupported output format '${OUTPUT_FORMAT}'."

[[ -n "${OUTPUT_PATH}" ]] || OUTPUT_PATH='.'

[[ "${OUTPUT_FORMAT}" == 'pdf' ]] && ensure-weasyprint

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

  REL="$(dirname "${REL}")"
  [[ "${REL}" == '.' ]] || [[ "${REL}" == '/' ]] || printf '%s' "${REL}"
}

[[ -z "${TO_STDOUT}" ]] || QUIET=true

SEARCH_DIRS=''
MD_FILES=''
# process args
INPUT=''
if (( $# == 1 )) && [[ ${1} == '-' ]]; then
  while read LINE; do
    INPUT="${INPUT}${LINE}"$'\n'
  done < /dev/stdin
else
  while (( $# > 0 )); do
    TEST_PATH="${1}"; shift
    if [[ -d "${TEST_PATH}" ]]; then
      list-add-item SEARCH_DIRS "${TEST_PATH}"
    elif [[ -f "${TEST_PATH}" ]]; then
      list-add-item MD_FILES "${TEST_PATH}"
    else
      echoerrandexit "'${TEST_PATH}' is neither a file nor a directory. Bailing out."
    fi
  done
fi

# used in the 'generate-page' call later
VERSION=$(OUTPUT=$(git status --porcelain) && [ -z "${OUTPUT}" ] && cat package.json | jq '.version' || echo 'working')

case "${OUTPUT_FORMAT}" in
  pdf|html)
    INTERMEDIDATE_FORMAT=html5;;
  *)
    INTERMEDIDATE_FORMAT="${OUTPUT_FORMAT}";;
esac

if [[ -n "${SINGLE_PAGE}" ]]; then
  COMBINED_FILE="${TITLE:-input}.md"
  ! [[ -f "${COMBINED_FILE}" ]] || rm "${COMBINED_FILE}"
fi

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

# WeasyPrint (the pinned '--pdf-engine') MIME-sniffs '--css' from its path extension, so
# it needs a real file ending in '.css' rather than a process-substitution '/dev/fd/N'
# path. macOS's native (BSD) 'mktemp' -- unlike GNU coreutils' -- only randomizes a
# *trailing* run of 'X's: a template with a literal suffix after the 'X's (e.g.
# 'md2x-css.XXXXXX.css') is returned verbatim, unrandomized, so a second call collides
# with the first call's still-open file. Create the file with a trailing-only template,
# then rename it to add the '.css' suffix.
CSS_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-css.XXXXXX")"
mv "${CSS_TMP_FILE}" "${CSS_TMP_FILE}.css"
CSS_TMP_FILE="${CSS_TMP_FILE}.css"
printf '%s' "${CSS}" > "${CSS_TMP_FILE}"

# 'generate-page()' can run once per input file, under this script's 'errexit'. A
# failing Pandoc/WeasyPrint invocation aborts the whole script immediately, skipping any
# cleanup written after the loop below -- so a plain post-loop 'rm' would still leak
# 'CSS_TMP_FILE' (and 'generate-page()'s own per-call body-open/body-close temp files)
# on that path. Registering this trap up front instead guarantees they are removed
# whether the script ends normally or aborts mid-batch: it always fires at real script
# exit (bash runs an 'EXIT' trap on every exit path, including one triggered by
# 'errexit'), by which point 'BODY_OPEN_TMP_FILE'/'BODY_CLOSE_TMP_FILE' hold either
# already-removed paths (the normal case -- 'generate-page()' cleans up its own files
# directly at the end of every successful call, so 'rm -f' here is a harmless no-op) or
# the one in-flight call's not-yet-cleaned files (the failure case). The ':-' defaults
# keep the trap itself safe under 'nounset' if it fires before any 'generate-page()'
# call has run at all. See followups 9hZL/MwYH/QBKX.
[[ -n "${KEEP_INTERMEDIATE}" ]] \
  || trap 'rm -f "${CSS_TMP_FILE:-}" "${BODY_OPEN_TMP_FILE:-}" "${BODY_CLOSE_TMP_FILE:-}"' EXIT

{
  if [[ -z "${INPUT}" ]]; then
    # Each record is '<md-file><tab><search-root>'; an empty root means the file was
    # named directly on the command line rather than found under a directory argument.
    while IFS=$'\t' read -r MD_FILE SEARCH_ROOT; do
      [[ -n "${MD_FILE}" ]] || continue
      # --to html5 : uses the HTML 5 engine. Yes, even when rendering PDF. It renders and
      #              prints and saves us the hassle of having to install pdflatex

      if [[ -n "${SINGLE_PAGE}" ]]; then
        { cat "${MD_FILE}"; echo; } >> "${COMBINED_FILE}"
      else
        TITLE=$(basename "${MD_FILE}" .md)
        
        BASE_OUTPUT="${OUTPUT_PATH}"
        [[ -n "${FLATTEN_DIRS}" ]] || {
          REL_DIR="$(relative-output-dir "${MD_FILE}" "${SEARCH_ROOT}")"
          [[ -z "${REL_DIR}" ]] || BASE_OUTPUT="${BASE_OUTPUT}/${REL_DIR}"
        }
        # Both branches need this: '--flatten-dirs' writes straight into
        # '--output-path', which is just as likely not to exist yet.
        mkdir -p "${BASE_OUTPUT}"
        BASE_OUTPUT="${BASE_OUTPUT}/${TITLE}"
        BASE_OUTPUT="${BASE_OUTPUT}.${OUTPUT_FORMAT}"
        
        generate-page
      fi
    done
  fi
  
  if [[ -n "${SINGLE_PAGE}" ]] || [[ -n "${INPUT}" ]]; then
    TITLE="${TITLE:-output}"
    mkdir -p "${OUTPUT_PATH}"
    BASE_OUTPUT="${OUTPUT_PATH}/${TITLE:-output}.${OUTPUT_FORMAT}"
    MD_FILE="${TITLE:-input}.md"
    generate-page
  fi
} < <(
  # Directly-named files first (with an empty search-root field), then the recursive
  # '*.md' search results sorted by path, exactly as before -- except that each record
  # now carries the search root the file was found under so the loop can place the
  # output relative to it. The root is the second field so that sorting still orders
  # the stream by file path.
  while IFS= read -r NAMED_FILE; do
    [[ -n "${NAMED_FILE}" ]] || continue
    printf '%s\t\n' "${NAMED_FILE}"
  done <<< "${MD_FILES}"
  while IFS= read -r ROOT_DIR; do
    [[ -n "${ROOT_DIR}" ]] || continue
    find "${ROOT_DIR}" -name "*.md" | while IFS= read -r FOUND_FILE; do
      printf '%s\t%s\n' "${FOUND_FILE}" "${ROOT_DIR}"
    done
  done <<< "${SEARCH_DIRS}" | sort
)

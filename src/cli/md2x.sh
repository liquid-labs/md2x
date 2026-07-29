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
                              directory structure.
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

for EXEC in gs pandoc pdftk; do
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

{
  if [[ -z "${INPUT}" ]]; then
    while read -r MD_FILE; do
      [[ -n "${MD_FILE}" ]] || continue
      # --to html5 : uses the HTML 5 engine. Yes, even when rendering PDF. It renders and
      #              prints and saves us the hassle of having to install pdflatex

      if [[ -n "${SINGLE_PAGE}" ]]; then
        { cat "${MD_FILE}"; echo; } >> "${COMBINED_FILE}"
      else
        TITLE=$(basename "${MD_FILE}" .md)
        
        BASE_OUTPUT="${OUTPUT_PATH}"
        [[ -n "${FLATTEN_DIRS}" ]] || {
          REL_DIR=$(dirname "${MD_FILE#*/policy/}")
          BASE_OUTPUT="${BASE_OUTPUT}/${REL_DIR}"
          mkdir -p "${BASE_OUTPUT}"
        }
        BASE_OUTPUT="${BASE_OUTPUT}/${TITLE}"
        if [[ "${OUTPUT_FORMAT}" == 'html' ]]; then BASE_OUTPUT="${BASE_OUTPUT}-base"; fi
        BASE_OUTPUT="${BASE_OUTPUT}.${OUTPUT_FORMAT}"
        
        generate-page
      fi
    done
  fi
  
  if [[ -n "${SINGLE_PAGE}" ]] || [[ -n "${INPUT}" ]]; then
    TITLE="${TITLE:-output}"
    BASE_OUTPUT="${OUTPUT_PATH}/${TITLE:-output}.${OUTPUT_FORMAT}"
    MD_FILE="${TITLE:-input}.md"
    generate-page
  fi
} < <(echo "${MD_FILES}"; for ROOT_DIR in $SEARCH_DIRS; do find ${ROOT_DIR} -name "*.md"; done | sort)

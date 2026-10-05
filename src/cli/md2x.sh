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
# import prompt

source ./lib/index.sh

# require-answer "Host OU or context path? (E.g., 'DevOps-ProductionMainApp', 'Security-SDLCTest', etc.)" HOST_OU_PATH
# get-answer ""

# export HOST_OU_PATH

# At one point, we supported the idea of generating "final" yaml files from a gucci processed template file. It turned out to be unecessary (I think), but want to keep this around till confirmed.

# $(npm bin)/gucci ./cloud/auths/environment/devops-admin-auths.yaml.tmpl

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
                              and the PDF header text. Only honored when
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
  -s, --to-stdout            Write the converted output to stdout (implies
                              --quiet).
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
  type "${EXEC}" >/dev/null \
    || md2x-die-dependency "Required executable '${EXEC}' not found for 'md2x'. Add to 'PATH' or install."
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
test_formats || md2x-die-usage "Unsupported output format '${OUTPUT_FORMAT}'."

# '--toc' and '--no-toc' resolve to a single 'TOC_MODE' the pipeline consumes; giving
# both is fatal, and must be checked before 'ensure-weasyprint' below, which can
# trigger a minute-long network install on a cold machine -- the conflict must abort
# before any conversion work begins.
[[ -z "${TOC}" ]] || [[ -z "${NO_TOC}" ]] \
  || md2x-die-usage "Cannot specify both '--toc' and '--no-toc'."
TOC_MODE='auto'
[[ -z "${TOC}" ]] || TOC_MODE='on'
[[ -z "${NO_TOC}" ]] || TOC_MODE='off'

# Input-path processing (which of SEARCH_DIRS/MD_FILES/INPUT the invocation resolves
# to) is done here, ahead of 'ensure-weasyprint' below, rather than in its previous
# position further down: the '--title' conflict gate that follows needs to know how
# many files this invocation will convert, and 'ensure-weasyprint' can trigger a
# minute-long network install on a cold machine that a doomed (conflicting) invocation
# should never pay for. Neither this block nor the gate reads 'OUTPUT_PATH' or anything
# 'ensure-weasyprint' sets, and 'OUTPUT_PATH's own default assignment and
# 'ensure-weasyprint' do not read 'SEARCH_DIRS'/'MD_FILES'/'INPUT', so this reordering
# is safe in both directions.
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
      # Planner decision: a nonexistent (or otherwise unusable) input argument is a usage
      # error (exit 2), not a runtime failure -- the caller named something invalid.
      md2x-die-usage "'${TEST_PATH}' is neither a file nor a directory. Bailing out."
    fi
  done
fi

# '--title'/'-t' only applies to a single-file conversion: the main per-file loop
# derives each output's filename (and, via 'generate-page()', the '--infer-title'
# metadata) from 'TITLE', so an explicit '--title' with more than one file in play
# would silently apply to only the loop's last iteration. This is checked only for the
# non-'--single-page'/non-stdin path -- the other two input modes always produce
# exactly one output file and already honor '--title' correctly. The file count below
# does not replicate the real processing pipe's unreadable-search-root abort/continue
# subtlety (see followup S92a, out of scope); a plain 'find ... | wc -l' per root is
# sufficient here. Under 'pipefail', an unreadable root still makes the 'find | wc -l'
# pipeline's own exit status non-zero even though 'wc -l' itself always succeeds --
# empirically confirmed live, since it isn't obvious from reading alone -- so the
# trailing '|| true' is required to keep this count-only pass from tripping the
# top-level 'errexit' on a root the real pipe further below would otherwise just skip
# with a stderr notice (see 'exit-codes.bats'' "unreadable search root" cases).
if [[ -z "${SINGLE_PAGE}" ]] && [[ -z "${INPUT}" ]]; then
  TITLE_PRECEDENCE_FILE_COUNT=$(list-count MD_FILES)
  while IFS= read -r SEARCH_ROOT; do
    [[ -n "${SEARCH_ROOT}" ]] || continue
    TITLE_PRECEDENCE_FILE_COUNT=$(( TITLE_PRECEDENCE_FILE_COUNT \
      + $(find "${SEARCH_ROOT}" -name "*.md" | wc -l || true) ))
  done <<< "${SEARCH_DIRS}"

  if [[ -n "${TITLE_SET:-}" ]] && (( TITLE_PRECEDENCE_FILE_COUNT > 1 )); then
    md2x-die-usage "Cannot use '--title'/'-t' with more than one input file" \
      "(${TITLE_PRECEDENCE_FILE_COUNT} files would be converted); '--title' only" \
      "applies to a single-file conversion. Use '--single-page' to combine multiple" \
      "files under one title, or omit '--title' to use each file's own basename."
  fi
fi

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

# used in the 'generate-page' call later
VERSION=$(OUTPUT=$(git status --porcelain) && [ -z "${OUTPUT}" ] && cat package.json | jq '.version' || echo 'working')

case "${OUTPUT_FORMAT}" in
  pdf|html)
    INTERMEDIDATE_FORMAT=html5;;
  *)
    INTERMEDIDATE_FORMAT="${OUTPUT_FORMAT}";;
esac

if [[ -n "${SINGLE_PAGE}" ]]; then
  # Prefixed 'SINGLE_PAGE_' rather than the bare 'COMBINED_FILE' its own name would
  # suggest: 'generate-page()' (src/cli/lib/generate-page.sh) assigns its own,
  # unrelated 'COMBINED_FILE' global -- the pdftk multistamp output path for the PDF
  # header/footer overlay -- on every pdf-format call, with no 'local' to scope it. A
  # bare 'COMBINED_FILE' here would get silently clobbered by that assignment the
  # moment 'generate-page()' runs, leaving this script's own end-of-run cleanup below
  # reading a stale, already-'mv'-away path instead of this concatenation file's real
  # one. See followup flSJ.
  SINGLE_PAGE_COMBINED_FILE="${TITLE:-input}.md"
  ! [[ -f "${SINGLE_PAGE_COMBINED_FILE}" ]] || rm "${SINGLE_PAGE_COMBINED_FILE}"
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

# 'src/cli/lib/toc-preprocess.py' is a source file, not a '.sh' one, so it travels
# through the rolled-up CLI the same way -- inlined verbatim by 'bash-rollup', then
# handed to 'python3 -c' at the call site in 'generate-page()' rather than written out
# to a temp file, since the document itself already needs to occupy stdin. Resolves
# relative to this file's own directory ('src/cli'), same as '$CSS' above.
TOC_PREPROCESSOR=$(cat <<'EOF'
source ./lib/toc-preprocess.py # bash-rollup-no-recur
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

# A '< <(...)' process substitution's own failures never reach the parent shell's
# 'errexit'/'pipefail' (see the file-discovery pipe below), so an unreadable search
# root has no way to make the top-level script exit non-zero on its own. This file is
# the signal: the process substitution's inner loop writes the failing root's path here
# the moment 'find' fails for it, and the outer script checks it right after the loop
# completes, exiting loudly instead of silently returning 0. See followup 8ZmD.
SEARCH_ROOT_ERROR_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-search-root-error.XXXXXX")"

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
# call has run at all. 'PREPROCESSED_TMP_FILE' -- the materialized, TOC-preprocessed
# Markdown 'generate-page()' hands to Pandoc -- follows the same per-call lifecycle and
# is covered here for the same reason. 'SINGLE_PAGE_COMBINED_FILE' -- the '--single-page'
# concatenation target (see its own comment above for the 'SINGLE_PAGE_' naming) -- is
# instead set once, up front, and only read (not written) by 'generate-page()', but the
# same errexit-can-skip-post-loop-cleanup risk applies to it, so it rides along in this
# trap too. The ':-' default keeps it safe under 'nounset' on runs where '--single-page'
# was never passed and 'SINGLE_PAGE_COMBINED_FILE' is never set. See followups
# 9hZL/MwYH/QBKX/flSJ.
#
# 'SEARCH_ROOT_ERROR_TMP_FILE' is folded into this same trap rather than gated behind a
# second, separately-registered one: bash keeps only one handler per signal, so a later
# 'trap ... EXIT' would silently replace this one instead of adding to it. Unlike the
# '--keep-intermediate'-gated files above, it is never a build artifact a user would
# want to retain -- it is purely an internal signal -- so its removal is unconditional,
# with the '--keep-intermediate' gate moved inside the trap body instead of around the
# whole registration.
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
      [[ -n "${KEEP_INTERMEDIATE:-}" ]] \
        || rm -f "${CSS_TMP_FILE:-}" "${BODY_OPEN_TMP_FILE:-}" "${BODY_CLOSE_TMP_FILE:-}" "${PREPROCESSED_TMP_FILE:-}" "${SINGLE_PAGE_COMBINED_FILE:-}"
      rm -f "${SEARCH_ROOT_ERROR_TMP_FILE:-}"
      if (( MD2X_EXIT_STATUS == 0 )) && [[ -z "${MD2X_COMPLETED:-}" ]]; then
        md2x-emit "md2x:" "1;31" "run aborted before completion; see the error above."
        exit 1
      fi
      if (( MD2X_EXIT_STATUS < 0 || MD2X_EXIT_STATUS > 3 )); then exit 1; fi' EXIT

# Unlike the Pandoc log and the PDF header/footer overlay -- both written into the user's own
# working/output tree, and therefore discoverable by normal directory listing -- 'CSS_TMP_FILE'
# lives in '${TMPDIR:-/tmp}', so a user retaining it via '--keep-intermediate' has no way to find
# it without an explicit announcement. Print to stderr (never stdout, which is the parsed data
# channel for '--list-files'/'--to-stdout') and don't gate this on '--quiet': '--quiet' only
# suppresses the per-file "Created ..." status line, not this one-time opt-in retention notice.
[[ -z "${KEEP_INTERMEDIATE}" ]] \
  || echo "md2x: kept intermediate CSS file: '${CSS_TMP_FILE}'" >&2

# 'SINGLE_PAGE_COMBINED_FILE' (the '--single-page' concatenation target, set above) is only an
# intermediate artifact in service of the eventual 'generate-page()' call -- it doesn't
# escape the '${TMPDIR}' vs. cwd distinction that motivates the CSS notice above (it's
# always written into the cwd, so it's already discoverable by directory listing), but a
# user who passed '--keep-intermediate' still benefits from the same one-time
# announcement the other kept artifacts get, so print it here too. Guarded on
# 'SINGLE_PAGE' since 'SINGLE_PAGE_COMBINED_FILE' is only ever set in that mode.
[[ -z "${SINGLE_PAGE}" || -z "${KEEP_INTERMEDIATE}" ]] \
  || echo "md2x: kept intermediate combined file: '${SINGLE_PAGE_COMBINED_FILE}'" >&2

# md2x-list-inputs
#
# Prints one '<md-file><tab><search-root>' record per file to convert: directly-named
# files first (with an empty search-root field), then the recursive '*.md' search results
# sorted by path. Each record carries the search root the file was found under so the
# conversion loop can place the output relative to it; the root is the second field so
# that sorting still orders the stream by file path.
#
# This is a function, called from the '< <(...)' process substitution below, rather than
# an inline body, because bash 3.2 mis-parses a process substitution (or '$(...)') body
# that contains a comment with an apostrophe: it scans for the closing parenthesis while
# treating that apostrophe as an unterminated quote and dies with 'bad substitution: no
# closing )' (and, being a parse error, still exits 0). No comment containing an
# apostrophe may sit inside a '$(...)' or '<(...)' body anywhere in 'src/cli/'.
#
# Empirically confirmed abort/continue behavior for a 'find' failure in the loop below
# (e.g. an unreadable root), since it is not obvious from reading alone: under 'pipefail',
# the pipe's exit status is the rightmost non-zero status among find and the while loop,
# and the 'while read' loop always exits 0 (it just drains whatever 'find' emitted, or
# nothing, then hits EOF), so a 'find' error becomes the pipe's exit status. Left
# unguarded, that would trip 'errexit' right there, aborting the loop before
# 'SEARCH_ROOT_ERROR_TMP_FILE' could be written: any root listed after the failing one in
# 'SEARCH_DIRS' is never even attempted (silently dropped), while roots listed before it,
# and files 'find' already emitted for the SAME root before erroring deeper in its tree,
# are kept. Wrapping the pipe as an 'if !' condition exempts it from 'errexit' just long
# enough to record the failure; the explicit 'exit 1' right after reproduces the same
# abort-the-remaining-roots behavior 'errexit' would have produced on its own. Process
# substitution failures are invisible to the parent's own 'errexit'/'pipefail' --
# 'SEARCH_ROOT_ERROR_TMP_FILE' is what carries the failure out to the top-level script,
# checked right after the conversion loop below. See 'exit-codes.bats' "unreadable search
# root" cases and followup 8ZmD.
md2x-list-inputs() {
  local NAMED_FILE ROOT_DIR FOUND_FILE
  while IFS= read -r NAMED_FILE; do
    [[ -n "${NAMED_FILE}" ]] || continue
    printf '%s\t\n' "${NAMED_FILE}"
  done <<< "${MD_FILES}"
  while IFS= read -r ROOT_DIR; do
    [[ -n "${ROOT_DIR}" ]] || continue
    if ! find "${ROOT_DIR}" -name "*.md" | while IFS= read -r FOUND_FILE; do
          printf '%s\t%s\n' "${FOUND_FILE}" "${ROOT_DIR}"
        done
    then
      printf '%s\n' "${ROOT_DIR}" > "${SEARCH_ROOT_ERROR_TMP_FILE}"
      exit 1
    fi
  done <<< "${SEARCH_DIRS}" | sort
}

{
  if [[ -z "${INPUT}" ]]; then
    # Each record is '<md-file><tab><search-root>'; an empty root means the file was
    # named directly on the command line rather than found under a directory argument.
    while IFS=$'\t' read -r MD_FILE SEARCH_ROOT; do
      [[ -n "${MD_FILE}" ]] || continue
      # --to html5 : uses the HTML 5 engine. Yes, even when rendering PDF. It renders and
      #              prints and saves us the hassle of having to install pdflatex

      if [[ -n "${SINGLE_PAGE}" ]]; then
        { cat "${MD_FILE}"; echo; } >> "${SINGLE_PAGE_COMBINED_FILE}"
      else
        # An explicit '--title' is honored as-is; the upfront gate above (requirement
        # 3) already guarantees this loop processes at most one file whenever
        # 'TITLE_SET' is non-empty, so 'TITLE' stays pinned to the explicit value for
        # the loop's single iteration. Absent '--title', fall back to each file's own
        # basename, as before.
        [[ -n "${TITLE_SET:-}" ]] || TITLE=$(basename "${MD_FILE}" .md)

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
    [[ -z "${SINGLE_PAGE}" ]] || MD_FILE="${SINGLE_PAGE_COMBINED_FILE}"
    generate-page
  fi
} < <(md2x-list-inputs)

# The process substitution above can't propagate a failed search root's exit status to
# this, the parent shell -- see the comment at the 'find' pipe inside it. Its inner loop
# writes the failing root's path to 'SEARCH_ROOT_ERROR_TMP_FILE' instead, the moment
# 'find' fails for it; a non-empty file here means that happened, so abort loudly rather
# than let the run's partial results pass as a silent success. Followup 8ZmD.
[[ ! -s "${SEARCH_ROOT_ERROR_TMP_FILE}" ]] \
  || md2x-die-runtime "could not fully search '$(cat "${SEARCH_ROOT_ERROR_TMP_FILE}")' for Markdown files. Bailing out."

# Reached only when every step above succeeded; see the lost-status backstop on the 'EXIT'
# trap.
MD2X_COMPLETED=true

generate-page() {
  # Names the input in tool-failure messages; stdin mode has no file.
  local INPUT_LABEL="${MD_FILE:-}"
  local -a INCLUDE_BODY_ARGS STYLE_ARGS LINK_ARGS
  local FILTER_SOURCE_DIR FILTER_OUT_DIR
  local DOC_DATA PAGE_COUNT MEDIA_DIMENSIONS XPAGE YPAGE HF_FONT_SIZE PG_NUMBER_X_OFFSET
  local VERSION_X_OFFSET FOOTER_Y_OFFSET HEADER_Y_OFFSET TITLE_X_OFFSET FOOTER_STRING
  [[ -z "${STDIN_MODE:-}" ]] || INPUT_LABEL='stdin'
  # The label reaches stderr messages; a file name is untrusted, so show it control-free.
  local INPUT_DISPLAY PIPE_STATUS
  INPUT_DISPLAY="$(md2x-title-display "${INPUT_LABEL}")"
  local PS_TITLE PS_VERSION
  local -a METADATA_ARGS
  # '--infer-title' passes the title as one '-M' argv element: pandoc keeps the value as a
  # literal string (a metadata file would parse it as Markdown or YAML).
  METADATA_ARGS=()
  [[ -z "${INFER_TITLE}" ]] || METADATA_ARGS=(-M "title=${TITLE}")

  # Every intermediate file lives in the per-run work directory the caller (md2x.sh)
  # created and registered for cleanup: the CSS file, the body-open/body-close include
  # files (all written once per run, not per call), the preprocessed Markdown, the Pandoc
  # log, the overlay, and the pdftk output. This function only consumes them, and needs no
  # cleanup of its own: the caller's 'EXIT' trap removes the work directory.

  # Passed as separate, already-quoted array elements rather than folded into an
  # unquoted command-substitution string (the pattern the other conditional flags below
  # still use): a path built from a '${TMPDIR}' containing whitespace
  # would otherwise get IFS-word-split into extra, misaligned pandoc arguments instead
  # of failing loudly. It is empty for 'docx', and bash before 4.4 treats an empty array
  # as unset under 'nounset', so its expansion below uses the '[@]+' guard form.
  INCLUDE_BODY_ARGS=()
  [[ "${OUTPUT_FORMAT}" == 'docx' ]] \
    || INCLUDE_BODY_ARGS=(--include-before-body "${BODY_OPEN_FILE}" --include-after-body "${BODY_CLOSE_FILE}")

  # Stylesheet delivery: pdf hands WeasyPrint the work-directory '.css' file (read during
  # the run); html embeds it inline as a '<style>' block via '--include-in-header', so the
  # output never references the (deleted-at-exit) work directory; docx takes neither.
  STYLE_ARGS=()
  case "${OUTPUT_FORMAT}" in
    pdf) STYLE_ARGS=(--css "${CSS_FILE}");;
    html) STYLE_ARGS=(--include-in-header "${STYLE_HEADER_FILE}");;
  esac

  # Link and image handling is the Lua filter 'md2x-links.lua' (written to the work
  # directory by 'md2x.sh'); it is told its settings through '-M' metadata. Images resolve
  # against the source file's directory (the cwd for stdin; under '--single-page' the
  # per-source markers the concatenation inserted take over). For html the filter needs
  # the output file's directory, to make image paths relative to it; '--to-stdout' has no
  # output file, so those paths are relative to the cwd.
  if [[ -n "${STDIN_MODE}" ]] || [[ -n "${SINGLE_PAGE:-}" ]]; then
    FILTER_SOURCE_DIR="$(pwd -P)"
  else
    FILTER_SOURCE_DIR="$(md2x-abs-dir-of "${MD_FILE}")"
  fi
  LINK_ARGS=(--lua-filter "${LINK_FILTER_FILE}"
    -M "md2x-format=${OUTPUT_FORMAT}"
    -M "md2x-source-dir=${FILTER_SOURCE_DIR}"
    -M "md2x-miss-file=${MISSING_IMAGES_FILE}")
  [[ -n "${SINGLE_PAGE:-}" ]] || LINK_ARGS+=(-M "md2x-source=${INPUT_DISPLAY}")
  if [[ "${OUTPUT_FORMAT}" == 'html' ]]; then
    if [[ -n "${TO_STDOUT}" ]]; then
      FILTER_OUT_DIR="$(pwd -P)"
    else
      FILTER_OUT_DIR="$(md2x-parent-dir "$(md2x-canonical-target "${FINAL_OUTPUT}")")"
    fi
    LINK_ARGS+=(-M "md2x-out-dir=${FILTER_OUT_DIR}")
  fi
  { : > "${MISSING_IMAGES_FILE}"; } 2>/dev/null || md2x-work-write-failed

  # Materialize the TOC-preprocessed Markdown to a real temp file
  # rather than handing Pandoc a process substitution. A process substitution's exit
  # status is invisible to this script's 'errexit'/'pipefail', so a failing
  # preprocessor would otherwise hand Pandoc a truncated document and md2x would
  # report success; as a plain pipeline under 'pipefail', any stage's failure aborts
  # the conversion. '${TOC_PREPROCESSOR}' is the inlined 'toc-preprocess.py' source
  # (see 'md2x.sh'); running it via 'python3 -c' lets the document occupy stdin
  # without a fourth temp file. Stdin mode reads the captured copy in
  # the work directory, byte for byte, via 'MD_FILE'.
  # An input found by a directory search can still be unreadable; check it here, so 'cat'
  # never reports it raw.
  [[ -r "${MD_FILE}" ]] || md2x-die-runtime "cannot read '${INPUT_DISPLAY}'."
  cat -- "${MD_FILE}" 2>/dev/null \
    | python3 -c "${TOC_PREPROCESSOR}" --mode "${TOC_MODE}" --source-name "${INPUT_DISPLAY}" \
    > "${PREPROCESSED_FILE}" \
    || {
      # Status 4 is the preprocessor's invalid-encoding signal; it has already printed an
      # md2x-formatted message, so only the exit status remains to be set.
      PIPE_STATUS=("${PIPESTATUS[@]}")
      [[ "${PIPE_STATUS[1]:-}" != 4 ]] || exit 1
      md2x-die-runtime "TOC preprocessing failed for '${INPUT_DISPLAY}'."
    }

  # Pandoc features the Lua filter relies on, with the earliest pandoc version that provides
  # each (the version floor is set from this list):
  #   --lua-filter and the 'Pandoc' filter function ........ pandoc 2.0 (Lua filters)
  #   pandoc.utils.stringify (reads the '-M' settings) ..... pandoc 2.0
  #   block:walk{Link=, Image=, RawBlock=} ................. pandoc 2.0 (element 'walk' method)
  #   RawBlock 'format'/'text', Link 'target', Image 'src' . pandoc 2.0 field names, still
  #                                                          accepted in 3.x
  #   Not used: 'pandoc.path', 'PANDOC_VERSION', anything beyond Lua 5.1 syntax.
  # Only pandoc 3.10.1 has been exercised; the versions above come from the Lua filter
  # documentation, not from a test run on an older pandoc.
  pandoc \
    $( [[ "${OUTPUT_FORMAT}" != 'pdf' ]] || echo "--pdf-engine=${WEASYPRINT_BIN}" ) \
    ${INCLUDE_BODY_ARGS[@]+"${INCLUDE_BODY_ARGS[@]}"} \
    --quiet \
    --standalone \
    --from gfm \
    --to ${INTERMEDIATE_FORMAT} \
    ${STYLE_ARGS[@]+"${STYLE_ARGS[@]}"} \
    ${METADATA_ARGS[@]+"${METADATA_ARGS[@]}"} \
    "${LINK_ARGS[@]}" \
    "${PREPROCESSED_FILE}" \
    -o "${BASE_OUTPUT}" \
    --log "${PANDOC_LOG_FILE}" \
    1>/dev/null \
    || md2x-die-runtime "pandoc failed for '${INPUT_DISPLAY}'."
  md2x-report-missing-images "${MISSING_IMAGES_FILE}"
  # Pandoc's own stdout is inert when '-o <file>' is given; the explicit redirect
  # guarantees stdout purity for '--to-stdout'/'--list-files' by construction rather
  # than by relying on that behavior. Stderr is left untouched: WeasyPrint runs as a
  # Pandoc subprocess and inherits Pandoc's stderr fd, so its warning/progress chatter
  # (and any real fatal error) flows straight to the CLI's own real stderr, where
  # 'errexit' still catches a non-zero Pandoc exit since nothing pipes or masks it.
  #
  # Pandoc's own native table-of-contents flag is retired for every format: md2x now
  # generates the TOC itself, ahead of Pandoc, as ordinary Markdown content in
  # '${PREPROCESSED_FILE}' -- see 'toc-preprocess.py' and
  # 'plan/notes/toc-defaults-and-page-heuristic.md'. This is also what gives DOCX a
  # TOC for the first time: the 'docx' short-circuit that used to gate that flag is
  # gone along with the flag itself. The separate 'docx' short-circuit on
  # 'INCLUDE_BODY_ARGS' above is unrelated -- that one is about the 'markdown-body'
  # wrapper div, not the TOC.

  if [[ "${OUTPUT_FORMAT}" == 'pdf' ]]; then
    # generate headers and footers as a separate document and overlay them.
    # Note, if we ever go back to a latex generator, you can use 'header-include' to configure to generate headers and
    # footers as part of the first run.

    DOC_DATA="$(pdftk "${BASE_OUTPUT}" dump_data)" \
      || md2x-die-runtime "pdftk failed for '${INPUT_DISPLAY}'."
    PAGE_COUNT=$(echo "${DOC_DATA}" | grep NumberOfPages | cut -d: -f2)
    MEDIA_DIMENSIONS=$(echo "${DOC_DATA}" | grep PageMediaDimensions | head -n 1)
    XPAGE=$(echo "${MEDIA_DIMENSIONS}" | cut -d: -f2 | cut -d' ' -f 2)
    YPAGE=$(echo "${MEDIA_DIMENSIONS}" | cut -d: -f2 | cut -d' ' -f 3)
    # WeasyPrint reports fractional point dimensions (e.g. '595.276' for A4) where the previous pdf-engine gave
    # whole points; truncate to whole points so the integer arithmetic below stays valid regardless of pdf-engine.
    XPAGE="${XPAGE%%.*}"
    YPAGE="${YPAGE%%.*}"
    HF_FONT_SIZE=9
    PG_NUMBER_X_OFFSET=$((${XPAGE} - 145))
    VERSION_X_OFFSET=75
    FOOTER_Y_OFFSET=35
    HEADER_Y_OFFSET=$((${YPAGE} - ${FOOTER_Y_OFFSET}))
    TITLE_X_OFFSET=$((${XPAGE} / 2 + 10))


    # TODO: make the positioning relative to the margins, with proper justification; abstract into a 'top-left', 'top-
    # centered', 'top-right', 'bottom-right', 'bottom-centered', and 'bottom-left' abstraction
    # https://www.tek-tips.com/viewthread.cfm?qid=830058
    # Both strings are untrusted text interpolated into a PostScript program: encode them.
    PS_TITLE="$(md2x-ps-string "${TITLE}")"
    PS_VERSION="$(md2x-ps-string "${INFERRED_VERSION:-}")"

    FOOTER_STRING="/Helvetica findfont \
      ${HF_FONT_SIZE} scalefont setfont \
      1 1  ${PAGE_COUNT} {      \
      /PageNo exch def          \
      ${PG_NUMBER_X_OFFSET} ${FOOTER_Y_OFFSET} moveto \
      (Page ) show              \
      PageNo 3 string cvs       \
      show                      \
      ( of ${PAGE_COUNT}) show  "

    if [[ -n "${INFER_VERSION}" ]] && [[ -n "${INFERRED_VERSION:-}" ]]; then
      FOOTER_STRING="${FOOTER_STRING}${VERSION_X_OFFSET} ${FOOTER_Y_OFFSET} moveto \
      ( Version: ${PS_VERSION} ) show "
    fi

    FOOTER_STRING="${FOOTER_STRING}PageNo 1 gt \
      { /Helvetica-Oblique findfont \
        ${HF_FONT_SIZE} scalefont setfont \
        ${TITLE_X_OFFSET} ${HEADER_Y_OFFSET} moveto \
        ( ${PS_TITLE} ) show \
        /Helvetica findfont \
        ${HF_FONT_SIZE} scalefont setfont \
      } if \
      showpage                  \
      } for"
    gs -o "${OVERLAY_FILE}"       \
      -sDEVICE=pdfwrite             \
      -g${XPAGE}0x${YPAGE}0         \
      -c "${FOOTER_STRING}"         \
      -q > /dev/null \
      || md2x-die-runtime "gs failed for '${INPUT_DISPLAY}'."

    pdftk "${BASE_OUTPUT}" multistamp "${OVERLAY_FILE}" output "${STAMPED_FILE}" \
      || md2x-die-runtime "pdftk failed for '${INPUT_DISPLAY}'."
    mv -- "${STAMPED_FILE}" "${BASE_OUTPUT}" 2>/dev/null \
      || md2x-die-runtime "could not move the stamped PDF into place for '${INPUT_DISPLAY}'."
  fi

  # Delivery. 'BASE_OUTPUT' is the staged result in the per-run work directory, under a
  # fixed name ('output.<format>'): pandoc picks its PDF writer from the extension of its
  # '-o' path, so a user-chosen '-o' name could not be handed to it directly, and a failed
  # conversion never leaves a partial file at the destination. '--to-stdout' streams that
  # work-directory file and writes nothing else; otherwise it is copied to 'FINAL_OUTPUT',
  # the planned target (see 'md2x.sh'), creating its parent directory first.
  if [[ -n "${TO_STDOUT}" ]]; then
    cat -- "${BASE_OUTPUT}" 2>/dev/null \
      || md2x-die-runtime "could not write '${INPUT_DISPLAY}' to standard output."
  else
    mkdir -p -- "$(md2x-parent-dir "${FINAL_OUTPUT}")" 2>/dev/null \
      || md2x-die-runtime "could not create the directory for '$(md2x-title-display "${FINAL_OUTPUT}")'."
    cp -- "${BASE_OUTPUT}" "${FINAL_OUTPUT}" 2>/dev/null \
      || md2x-die-runtime "could not write '$(md2x-title-display "${FINAL_OUTPUT}")'."
  fi

  [[ -n "${QUIET}" ]] || {
    [[ -n "${LIST_FILES}" ]] && echo "${FINAL_OUTPUT}" || echo "Created ${FINAL_OUTPUT}"
  }
}

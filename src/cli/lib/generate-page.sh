generate-page() {
  # Names the input in tool-failure messages; stdin mode has no file.
  local INPUT_LABEL="${MD_FILE:-}"
  local LINK_CONVERTER
  local -a INCLUDE_BODY_ARGS
  local DOC_DATA PAGE_COUNT MEDIA_DIMENSIONS XPAGE YPAGE HF_FONT_SIZE PG_NUMBER_X_OFFSET
  local VERSION_X_OFFSET FOOTER_Y_OFFSET HEADER_Y_OFFSET TITLE_X_OFFSET FOOTER_STRING
  [[ -z "${STDIN_MODE:-}" ]] || INPUT_LABEL='stdin'
  local SETTINGS='---
'
  if [[ -n "${INFER_TITLE}" ]]; then
    SETTINGS="${SETTINGS}title: '${TITLE}'
"
  fi
  SETTINGS="${SETTINGS}...
"

# TODO: support 'author' if known
  # echo "generate-page for ${MD_FILE}..."

  # matches a linky thing; captures from '[...](' in $1, skips './' if present, and captures rest up but excluding '.md'
  #                   [....]      link not abs or ext                       add './' back in place
  #     link opening  vvvvvv       vvvvvvvvvvvvvvvv                           vv
  # perl -pe 's/(\[[^\]]+\]\()(?!\/|https?:\/\/)(?:\.\/)?(.*)\.md\s*\)$/$1.\/$2.docx)/g'
  LINK_CONVERTER='perl -pe '"'"'s/(\[[^\]]+\]\()(?!\/|https?:\/\/)(?:\.\/)?(.*)\.md\s*\)$/$1.\/$2.'${OUTPUT_FORMAT}")/g'"

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

  # Materialize the TOC-preprocessed, link-converted Markdown to a real temp file
  # rather than handing Pandoc a process substitution. A process substitution's exit
  # status is invisible to this script's 'errexit'/'pipefail', so a failing
  # preprocessor would otherwise hand Pandoc a truncated document and md2x would
  # report success; as a plain pipeline under 'pipefail', any stage's failure aborts
  # the conversion. '${TOC_PREPROCESSOR}' is the inlined 'toc-preprocess.py' source
  # (see 'md2x.sh'); running it via 'python3 -c' lets the document occupy stdin
  # without a fourth temp file. Stdin mode reads the captured copy in
  # the work directory, byte for byte, via 'MD_FILE'. The
  # preprocessor runs ahead of 'LINK_CONVERTER': the two do not interfere, since
  # 'LINK_CONVERTER' only rewrites links whose target ends in '.md)', and generated
  # TOC entries end in ')' directly after a '#anchor'.
  cat "${MD_FILE}" \
    | python3 -c "${TOC_PREPROCESSOR}" --mode "${TOC_MODE}" \
    | eval $LINK_CONVERTER \
    > "${PREPROCESSED_FILE}" \
    || md2x-die-runtime "TOC preprocessing failed for '${INPUT_LABEL}'."

  pandoc \
    $( [[ "${OUTPUT_FORMAT}" != 'pdf' ]] || echo "--pdf-engine=${WEASYPRINT_BIN}" ) \
    ${INCLUDE_BODY_ARGS[@]+"${INCLUDE_BODY_ARGS[@]}"} \
    --quiet \
    --standalone \
    --from gfm \
    --to ${INTERMEDIDATE_FORMAT} \
    --css "${CSS_FILE}" \
    --metadata-file <(echo "${SETTINGS}") \
    "${PREPROCESSED_FILE}" \
    -o "${BASE_OUTPUT}" \
    --log "${PANDOC_LOG_FILE}" \
    1>/dev/null \
    || md2x-die-runtime "pandoc failed for '${INPUT_LABEL}'."
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
      || md2x-die-runtime "pdftk failed for '${INPUT_LABEL}'."
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
    FOOTER_STRING="/Helvetica findfont \
      ${HF_FONT_SIZE} scalefont setfont \
      1 1  ${PAGE_COUNT} {      \
      /PageNo exch def          \
      ${PG_NUMBER_X_OFFSET} ${FOOTER_Y_OFFSET} moveto \
      (Page ) show              \
      PageNo 3 string cvs       \
      show                      \
      ( of ${PAGE_COUNT}) show  "

    if [[ -n "${INFER_VERSION}" ]]; then
      FOOTER_STRING="${FOOTER_STRING}${VERSION_X_OFFSET} ${FOOTER_Y_OFFSET} moveto \
      ( Version: ${VERSION} ) show "
    fi

    FOOTER_STRING="${FOOTER_STRING}PageNo 1 gt \
      { /Helvetica-Oblique findfont \
        ${HF_FONT_SIZE} scalefont setfont \
        ${TITLE_X_OFFSET} ${HEADER_Y_OFFSET} moveto \
        ( "${TITLE}" ) show \
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
      || md2x-die-runtime "gs failed for '${INPUT_LABEL}'."

    pdftk "${BASE_OUTPUT}" multistamp "${OVERLAY_FILE}" output "${STAMPED_FILE}" \
      || md2x-die-runtime "pdftk failed for '${INPUT_LABEL}'."
    mv "${STAMPED_FILE}" "${BASE_OUTPUT}"
  fi

  if [[ -n "${TO_STDOUT}" ]]; then
    cat "${BASE_OUTPUT}"
  fi
  
  [[ -n "${QUIET}" ]] || {
    [[ -n "${LIST_FILES}" ]] && echo "${BASE_OUTPUT}" || echo "Created ${BASE_OUTPUT}"
  }
}

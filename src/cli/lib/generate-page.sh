generate-page() {
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
  # slurp in default CSS
  CSS=$(cat <<'EOF'
source ./github.css # bash-rollup-no-recur
EOF
)

  # matches a linky thing; captures from '[...](' in $1, skips './' if present, and captures rest up but excluding '.md'
  #                   [....]      link not abs or ext                       add './' back in place
  #     link opening  vvvvvv       vvvvvvvvvvvvvvvv                           vv
  # perl -pe 's/(\[[^\]]+\]\()(?!\/|https?:\/\/)(?:\.\/)?(.*)\.md\s*\)$/$1.\/$2.docx)/g'
  LINK_CONVERTER='perl -pe '"'"'s/(\[[^\]]+\]\()(?!\/|https?:\/\/)(?:\.\/)?(.*)\.md\s*\)$/$1.\/$2.'${OUTPUT_FORMAT}")/g'"

  # WeasyPrint (the pinned '--pdf-engine') MIME-sniffs '--css' from its path extension,
  # so it needs a real file ending in '.css' rather than a process-substitution
  # '/dev/fd/N' path. macOS's native (BSD) 'mktemp' -- unlike GNU coreutils' -- only
  # randomizes a *trailing* run of 'X's: a template with a literal suffix after the
  # 'X's (e.g. 'md2x-css.XXXXXX.css') is returned verbatim, unrandomized, so a second
  # call collides with the first call's still-open file. Create the file with a
  # trailing-only template, then rename it to add the '.css' suffix.
  CSS_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-css.XXXXXX")"
  mv "${CSS_TMP_FILE}" "${CSS_TMP_FILE}.css"
  CSS_TMP_FILE="${CSS_TMP_FILE}.css"
  printf '%s' "${CSS}" > "${CSS_TMP_FILE}"

  if [[ -z "${INPUT}" ]]; then
    pandoc \
      $( [[ "${OUTPUT_FORMAT}" == 'docx' ]] || [[ -n "${NO_TOC}" ]] || echo '--toc' ) \
      $( [[ "${OUTPUT_FORMAT}" != 'pdf' ]] || echo "--pdf-engine=${WEASYPRINT_BIN}" ) \
      --quiet \
      --standalone \
      --from gfm \
      --to ${INTERMEDIDATE_FORMAT} \
      --css "${CSS_TMP_FILE}" \
      --metadata-file <(echo "${SETTINGS}") \
      <(cat "${MD_FILE}" | eval $LINK_CONVERTER) \
      -o "${BASE_OUTPUT}" \
      --log 'pandoc-log.log' \
      1>/dev/null
    # Pandoc's own stdout is inert when '-o <file>' is given; the explicit redirect
    # guarantees stdout purity for '--to-stdout'/'--list-files' by construction rather
    # than by relying on that behavior. Stderr is left untouched: WeasyPrint runs as a
    # Pandoc subprocess and inherits Pandoc's stderr fd, so its warning/progress chatter
    # (and any real fatal error) flows straight to the CLI's own real stderr, where
    # 'errexit' still catches a non-zero Pandoc exit since nothing pipes or masks it.
  else
    pandoc \
      $( [[ "${OUTPUT_FORMAT}" == 'docx' ]] || [[ -n "${NO_TOC}" ]] || echo '--toc' ) \
      $( [[ "${OUTPUT_FORMAT}" != 'pdf' ]] || echo "--pdf-engine=${WEASYPRINT_BIN}" ) \
      --quiet \
      --standalone \
      --from gfm \
      --to ${INTERMEDIDATE_FORMAT} \
      --css "${CSS_TMP_FILE}" \
      --metadata-file <(echo "${SETTINGS}") \
      <(echo "${INPUT}" | eval $LINK_CONVERTER) \
      -o "${BASE_OUTPUT}" \
      --log 'pandoc-log.log' \
      1>/dev/null
  fi
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm pandoc-log.log
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${CSS_TMP_FILE}"

  if [[ "${OUTPUT_FORMAT}" == 'pdf' ]]; then
    # generate headers and footers as a separate document and overlay them.
    # Note, if we ever go back to a latex generator, you can use 'header-include' to configure to generate headers and
    # footers as part of the first run.

    DOC_DATA="$(pdftk "${BASE_OUTPUT}" dump_data)"
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
    OVERLAY_OUTPUT="${OUTPUT_PATH}/${TITLE}-overlay.pdf"
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
    gs -o "${OVERLAY_OUTPUT}"       \
      -sDEVICE=pdfwrite             \
      -g${XPAGE}0x${YPAGE}0         \
      -c "${FOOTER_STRING}"         \
      -q > /dev/null

    COMBINED_FILE="${TITLE}-combined.${OUTPUT_FORMAT}"

    pdftk "${BASE_OUTPUT}" multistamp "${OVERLAY_OUTPUT}" output "${COMBINED_FILE}"
    # mv "${COMBINED_FILE}" "${OUTPUT_PATH}/${TITLE}.${OUTPUT_FORMAT}"
    mv "${COMBINED_FILE}" "${BASE_OUTPUT}"
    [[ -n "${KEEP_INTERMEDIATE}" ]] || rm "${OVERLAY_OUTPUT}"
  fi
  
  if [[ -n "${TO_STDOUT}" ]]; then
    cat "${BASE_OUTPUT}"
  fi
  
  [[ -n "${QUIET}" ]] || {
    [[ -n "${LIST_FILES}" ]] && echo "${BASE_OUTPUT}" || echo "Created ${BASE_OUTPUT}"
  }
}

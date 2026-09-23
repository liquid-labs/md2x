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

  # matches a linky thing; captures from '[...](' in $1, skips './' if present, and captures rest up but excluding '.md'
  #                   [....]      link not abs or ext                       add './' back in place
  #     link opening  vvvvvv       vvvvvvvvvvvvvvvv                           vv
  # perl -pe 's/(\[[^\]]+\]\()(?!\/|https?:\/\/)(?:\.\/)?(.*)\.md\s*\)$/$1.\/$2.docx)/g'
  LINK_CONVERTER='perl -pe '"'"'s/(\[[^\]]+\]\()(?!\/|https?:\/\/)(?:\.\/)?(.*)\.md\s*\)$/$1.\/$2.'${OUTPUT_FORMAT}")/g'"

  # '$CSS' is static, deterministic content (github.css) that never varies across
  # 'generate-page()' calls within a single md2x invocation, but a batch/directory
  # conversion calls this function once per input file. 'CSS_TMP_FILE' is therefore
  # created once, up front, by the caller (md2x.sh) rather than here -- recreating an
  # identical file on every call would be redundant filesystem I/O (see followup QBKX).
  # This function only consumes the already-populated '${CSS_TMP_FILE}'.

  # 'github.css' scopes every rule under a bare '.markdown-body' class selector, and
  # neither Pandoc's default html5 template nor a '-V'/'--variable' metadata hook puts
  # that class anywhere in the generated document. '--include-before-body'/
  # '--include-after-body' inject literal content just inside the opening/closing
  # '<body>' tag, so wrapping the whole rendered body in this div satisfies those
  # selectors exactly as well as a class on '<body>' itself would (see task doc
  # plan/phase-01-restore-pdf-styling/004-wrap-generated-body-in-markdown-body-div.md).
  MARKDOWN_BODY_OPEN='<div class="markdown-body">'
  MARKDOWN_BODY_CLOSE='</div>'
  BODY_OPEN_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-body-open.XXXXXX")"
  BODY_CLOSE_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-body-close.XXXXXX")"
  printf '%s' "${MARKDOWN_BODY_OPEN}" > "${BODY_OPEN_TMP_FILE}"
  printf '%s' "${MARKDOWN_BODY_CLOSE}" > "${BODY_CLOSE_TMP_FILE}"

  # Passed as separate, already-quoted array elements rather than folded into an
  # unquoted command-substitution string (the pattern the other conditional flags below
  # still use): a mktemp-produced path built from a '${TMPDIR}' containing whitespace
  # would otherwise get IFS-word-split into extra, misaligned pandoc arguments instead
  # of failing loudly.
  INCLUDE_BODY_ARGS=()
  [[ "${OUTPUT_FORMAT}" == 'docx' ]] \
    || INCLUDE_BODY_ARGS=(--include-before-body "${BODY_OPEN_TMP_FILE}" --include-after-body "${BODY_CLOSE_TMP_FILE}")

  # Materialize the TOC-preprocessed, link-converted Markdown to a real temp file
  # rather than handing Pandoc a process substitution. A process substitution's exit
  # status is invisible to this script's 'errexit'/'pipefail', so a failing
  # preprocessor would otherwise hand Pandoc a truncated document and md2x would
  # report success; as a plain pipeline under 'pipefail', any stage's failure aborts
  # the conversion. '${TOC_PREPROCESSOR}' is the inlined 'toc-preprocess.py' source
  # (see 'md2x.sh'); running it via 'python3 -c' lets the document occupy stdin
  # without a fourth temp file. 'printf '%s\n'' reproduces the stdin-accumulation
  # path's previous 'echo "${INPUT}"' behavior (one trailing newline). The
  # preprocessor runs ahead of 'LINK_CONVERTER': the two do not interfere, since
  # 'LINK_CONVERTER' only rewrites links whose target ends in '.md)', and generated
  # TOC entries end in ')' directly after a '#anchor'.
  PREPROCESSED_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/md2x-preprocessed.XXXXXX")"
  if [[ -z "${INPUT}" ]]; then cat "${MD_FILE}"; else printf '%s\n' "${INPUT}"; fi \
    | python3 -c "${TOC_PREPROCESSOR}" --mode "${TOC_MODE}" \
    | eval $LINK_CONVERTER \
    > "${PREPROCESSED_TMP_FILE}"

  pandoc \
    $( [[ "${OUTPUT_FORMAT}" != 'pdf' ]] || echo "--pdf-engine=${WEASYPRINT_BIN}" ) \
    "${INCLUDE_BODY_ARGS[@]}" \
    --quiet \
    --standalone \
    --from gfm \
    --to ${INTERMEDIDATE_FORMAT} \
    --css "${CSS_TMP_FILE}" \
    --metadata-file <(echo "${SETTINGS}") \
    "${PREPROCESSED_TMP_FILE}" \
    -o "${BASE_OUTPUT}" \
    --log 'pandoc-log.log' \
    1>/dev/null
  # Pandoc's own stdout is inert when '-o <file>' is given; the explicit redirect
  # guarantees stdout purity for '--to-stdout'/'--list-files' by construction rather
  # than by relying on that behavior. Stderr is left untouched: WeasyPrint runs as a
  # Pandoc subprocess and inherits Pandoc's stderr fd, so its warning/progress chatter
  # (and any real fatal error) flows straight to the CLI's own real stderr, where
  # 'errexit' still catches a non-zero Pandoc exit since nothing pipes or masks it.
  #
  # Pandoc's own native table-of-contents flag is retired for every format: md2x now
  # generates the TOC itself, ahead of Pandoc, as ordinary Markdown content in
  # '${PREPROCESSED_TMP_FILE}' -- see 'toc-preprocess.py' and
  # 'plan/notes/toc-defaults-and-page-heuristic.md'. This is also what gives DOCX a
  # TOC for the first time: the 'docx' short-circuit that used to gate that flag is
  # gone along with the flag itself. The separate 'docx' short-circuit on
  # 'INCLUDE_BODY_ARGS' above is unrelated -- that one is about the 'markdown-body'
  # wrapper div, not the TOC.
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm pandoc-log.log
  # Ordinary-completion cleanup for this call's own body-open/body-close temp files. If
  # a Pandoc/WeasyPrint failure above aborted this function under 'errexit' instead of
  # reaching here, the caller's script-level EXIT trap (see md2x.sh) removes them -- and
  # 'CSS_TMP_FILE' -- on that path instead; see followups 9hZL/MwYH.
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${BODY_OPEN_TMP_FILE}"
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${BODY_CLOSE_TMP_FILE}"
  [[ -n "${KEEP_INTERMEDIATE}" ]] || rm -f "${PREPROCESSED_TMP_FILE}"

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

    local COMBINED_FILE="${TITLE}-combined.${OUTPUT_FORMAT}"

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

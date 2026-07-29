#!/usr/bin/env bash
#
# INTERACTIVE, MANUAL SMOKE TEST -- NOT part of 'make test'.
#
# Run it with 'make smoke-test'. It converts the tiny-doc fixture to every supported
# output format using the REAL pandoc/gs/pdftk toolchain, opens each result in a
# viewer, and then blocks on stdin until a human confirms the output looks right.
#
# It is macOS-specific ('open -Fn' to launch the viewer, 'lsof' to find the viewer's
# PID afterwards), it requires a fully working Pandoc PDF pipeline, and it cannot be
# automated. The automated suite lives in '../bats' and runs against stub external
# binaries instead; this script is the complement to it -- the "does the output
# actually look right" check that stubs can never make.

import strict

import lists

source ../../lib/parameters.sh

MD2X=./bin/md2x
TEST_OUTPUT="test-out"
TINY_DOC=./src/cli/test/tiny-doc.md

[[ -f ${MD2X} ]] || { echo "Did not find '${MD2X}'; bailing out of test."; exit 2; }

mkdir -p "${TEST_OUTPUT}"

for OUTPUT_FORMAT in ${OUTPUT_FORMATS}; do
  echo -n "Testing single file output to '${OUTPUT_FORMAT}' format: "
  FILE="$(${MD2X} --output-format ${OUTPUT_FORMAT} --output-path "${TEST_OUTPUT}" --list-files ${TINY_DOC} || {
    echo "FAIL"
    echo -e "\nThere was a problem processing '${TINY_DOC}' to format '${OUTPUT_FORMAT}'" >&2
    exit 2
  })"
  echo "pass"
  echo -n "Verifying file can be opened: "
  open -Fn "${FILE}" || {
    echo "FAIL"
    echo -e "\nThere was a problem opening '${FILE}'" >&2
    exit 2
  }
  list-add-item FILES "${FILE}"
done

echo "Please review open files and then hit enter to close..."
read -r THROW_AWAY

for FILE in ${FILES}; do
  # attempt cleanup
  PID=$(lsof -F p -- "${FILE}" | grep '^p' | cut -c2- || echo "Could not determine PID for '${FILE}'." >&2)
  [[ -z "${PID}" ]] || kill ${PID} || \
    echo "Had trouble killing app for '${TINY_DOC}' '${OUTPUT_FORMAT}', PID: ${PID}" >&2
done

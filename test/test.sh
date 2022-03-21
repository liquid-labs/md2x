#!/usr/bin/env bash

import strict

import lists

source ../src/md2x/lib/parameters.sh

MD2X=./bin/md2x
TEST_OUTPUT="test-out"
TINY_DOC=./src/md2x/test/tiny-doc.md

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

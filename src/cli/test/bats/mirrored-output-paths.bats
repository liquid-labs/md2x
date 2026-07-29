#!/usr/bin/env bats
#
# Output placement: where 'md2x' writes each converted file.
#
# Without '--flatten-dirs' the CLI mirrors the input tree under '--output-path', at the
# path each input file occupies *relative to the search root it was found under* -- the
# directory argument given on the command line, or the file's own directory when the
# file was named directly (so a directly-named file always lands directly in
# '--output-path'). With '--flatten-dirs' every output file goes straight into
# '--output-path'. '--single-page' and stdin mode bypass the mirroring branch entirely
# and always write exactly '<output-path>/<title>.<format>'; the two control cases at
# the bottom of this file pin that down.
#
# Every case here is written against the fixture tree from the mirrored-output-path
# contract -- 'docs/a.md', 'docs/guide/b.md', 'notes/c.md' -- so the assertions line up
# one-for-one with that note's worked examples.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# --- case-local helpers --------------------------------------------------------------

# The fixture tree the contract's worked examples are written against.
write_contract_tree() {
  md2x_write_doc 'docs/a.md' 'A'
  md2x_write_doc 'docs/guide/b.md' 'B'
  md2x_write_doc 'notes/c.md' 'C'
}

# tree_under <root> -- every file under <root>, as sorted paths relative to it.
tree_under() {
  local root="$1" found
  [[ -d "${root}" ]] || return 0
  (
    cd "${root}" || return 1
    find . -type f | sort | while IFS= read -r found; do
      printf '%s\n' "${found#./}"
    done
  )
}

# assert_tree_under <root> [expected-relative-path]...
# Asserts the exact set of files under <root> -- an extra file fails the case just as a
# missing one does, which is what makes these assertions regression-proof: the buggy
# implementation puts the output somewhere else rather than omitting it.
assert_tree_under() {
  local root="$1"; shift
  local expected='' actual
  (( $# == 0 )) || expected="$(printf '%s\n' "$@" | sort)"
  actual="$(tree_under "${root}")"
  if [[ "${actual}" != "${expected}" ]]; then
    md2x_fail "unexpected file tree under '${root}'" \
      'expected:' "${expected}" 'actual:' "${actual}"
  fi
}

# --- mirrored output -----------------------------------------------------------------

@test "mirrored output: a directory root mirrors paths relative to that root" {
  write_contract_tree

  md2x_run --output-path out docs

  assert_success
  assert_tree_under out 'a.pdf' 'guide/b.pdf'
  assert_output_contains 'Created out/a.pdf'
  assert_output_contains 'Created out/guide/b.pdf'
}

@test "mirrored output: a './'-prefixed root resolves the same and prints no '/./'" {
  write_contract_tree

  md2x_run --output-path out ./docs

  assert_success
  assert_tree_under out 'a.pdf' 'guide/b.pdf'
  assert_output_contains 'Created out/guide/b.pdf'
  refute_output_contains '/./'
}

@test "mirrored output: a directly named file lands directly in --output-path" {
  write_contract_tree
  mkdir -p out

  md2x_run --output-path out docs/guide/b.md

  assert_success
  assert_tree_under out 'b.pdf'
  assert_output_contains 'Created out/b.pdf'
}

@test "mirrored output: a directly named file honours the default --output-path" {
  write_contract_tree

  md2x_run docs/guide/b.md

  assert_success
  assert_file_exists './b.pdf'
  assert_file_not_exists './docs/guide/b.pdf'
  assert_output_contains 'Created ./b.pdf'
}

@test "mirrored output: a trailing slash on the root is immaterial" {
  write_contract_tree

  md2x_run --output-path out ./docs/

  assert_success
  assert_tree_under out 'a.pdf' 'guide/b.pdf'
  refute_output_contains '/./'
}

@test "mirrored output: each root of a multi-root invocation resolves against itself" {
  write_contract_tree

  md2x_run -p out docs notes

  assert_success
  assert_tree_under out 'a.pdf' 'guide/b.pdf' 'c.pdf'
}

@test "mirrored output: a root of '.' mirrors the whole visible tree" {
  write_contract_tree

  md2x_run -p out .

  assert_success
  assert_tree_under out 'docs/a.pdf' 'docs/guide/b.pdf' 'notes/c.pdf'
  refute_output_contains '/./'
}

@test "mirrored output: an absolute root resolves against itself" {
  write_contract_tree

  md2x_run -p out "${PWD}/docs"

  assert_success
  assert_tree_under out 'a.pdf' 'guide/b.pdf'
}

# --- flattened output ----------------------------------------------------------------

@test "mirrored output: --flatten-dirs discards structure and creates a missing --output-path" {
  write_contract_tree
  assert_file_not_exists 'out'

  md2x_run --output-path out --flatten-dirs docs

  assert_success
  assert_tree_under out 'a.pdf' 'b.pdf'
}

# --- controls: paths that never reach the mirroring branch ---------------------------

@test "mirrored output: --single-page still writes exactly one file into --output-path" {
  write_contract_tree
  # The single-page branch has never created '--output-path' itself, and this fix
  # deliberately leaves that alone -- see the task's requirement 5.
  mkdir -p out

  md2x_run --output-path out --single-page --title Combined docs

  assert_success
  assert_tree_under out 'Combined.pdf'
  assert_output_contains 'Created out/Combined.pdf'
}

@test "mirrored output: stdin mode still writes exactly one file into --output-path" {
  mkdir -p out

  md2x_run -p out - <<< '# Piped Heading'

  assert_success
  assert_tree_under out 'output.pdf'
  assert_output_contains 'Created out/output.pdf'
}

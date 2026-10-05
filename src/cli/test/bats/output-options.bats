#!/usr/bin/env bats
#
# The output contract: '-o, --output <file|->' with format inference, '--to-stdout' as a pure
# stream, '-p' normalization, and the pre-conversion collision check (every target is planned
# up front; a failing invocation writes nothing).

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# Fails unless the case's work directory holds exactly the listed files (relative paths).
assert_cwd_files() {
  local expected actual
  expected="$(printf '%s\n' "$@" | sort)"
  actual="$(find . -type f | sed 's|^\./||' | sort)"
  [[ "${expected}" == "${actual}" ]] \
    || md2x_fail "unexpected files in the cwd" "expected:" "${expected}" "actual:" "${actual}"
}

# --- -o ---------------------------------------------------------------------------------

@test "-o out/x.html creates out/ and infers html" {
  md2x_write_doc 'a.md'

  md2x_run -o out/x.html a.md

  assert_success
  assert_output_equals 'Created out/x.html'
  assert_file_contains 'out/x.html' 'to: html5'
}

@test "-o x.HTML infers html case-insensitively" {
  md2x_write_doc 'a.md'

  md2x_run -o x.HTML a.md

  assert_success
  assert_file_contains 'x.HTML' 'to: html5'
}

@test "-o x.pdf -F html exits 2" {
  md2x_write_doc 'a.md'

  md2x_run -o x.pdf -F html a.md

  assert_failure 2
  assert_stderr_contains 'contradicts'
  assert_cwd_files 'a.md'
}

@test "-o x.html -F HTML agrees" {
  md2x_write_doc 'a.md'

  md2x_run -o x.html -F HTML a.md

  assert_success
  assert_file_exists 'x.html'
}

@test "-o with an unrecognized extension writes the default format to the path as given" {
  md2x_write_doc 'a.md'

  md2x_run -o x a.md

  assert_success
  assert_file_exists 'x'
  assert_stub_called pdftk
  assert_cwd_files 'a.md' 'x'
}

@test "-o with two inputs exits 2 and names the output count" {
  md2x_write_doc 'a.md'
  md2x_write_doc 'b.md'

  md2x_run -o x.html a.md b.md

  assert_failure 2
  assert_stderr_contains '2 files'
  assert_cwd_files 'a.md' 'b.md'
}

@test "-o with a directory resolving to two files exits 2" {
  md2x_make_fixture_tree 'tree' >/dev/null

  md2x_run -o x.html tree

  assert_failure 2
}

@test "-o with --single-page of two inputs is allowed" {
  md2x_write_doc 'a.md'
  md2x_write_doc 'b.md'

  md2x_run -o both.html --single-page a.md b.md

  assert_success
  assert_file_exists 'both.html'
}

@test "-o with stdin is allowed" {
  md2x_run -o s.html - <<< '# Piped'

  assert_success
  assert_file_exists 's.html'
}

@test "-o together with -p exits 2" {
  md2x_write_doc 'a.md'

  md2x_run -o x.html -p out a.md

  assert_failure 2
  assert_stderr_contains '-p'
  assert_cwd_files 'a.md'
}

@test "-o together with --to-stdout <file> exits 2, but -o - with --to-stdout is allowed" {
  md2x_write_doc 'a.md'

  md2x_run -o x.html --to-stdout a.md
  assert_failure 2

  md2x_run -o - --to-stdout -F html a.md
  assert_success
  assert_output_contains 'md2x-test-stub: pandoc output'
}

@test "-o - streams to stdout and leaves no file behind" {
  md2x_write_doc 'a.md'

  md2x_run -o - -F html a.md

  assert_success
  assert_output_contains 'md2x-test-stub: pandoc output'
  refute_output_contains 'Created'
  assert_cwd_files 'a.md'
}

@test "-o path through a file exits 2 with an md2x message and no raw mkdir text" {
  md2x_write_doc 'a.md'
  : > blocker

  md2x_run -o blocker/x.html a.md

  assert_failure 2
  assert_stderr_contains 'md2x: '
  assert_stderr_contains 'blocker'
  refute_stderr_contains 'mkdir:'
}

@test "-o naming an existing directory exits 2" {
  md2x_write_doc 'a.md'
  mkdir out

  md2x_run -o out a.md

  assert_failure 2
}

@test "-o with --list-files prints the path as given" {
  md2x_write_doc 'a.md'

  md2x_run -o ./sub/x.html --list-files a.md

  assert_success
  assert_output_equals './sub/x.html'
}

@test "--title with a slash is accepted when -o is given" {
  md2x_write_doc 'a.md'

  md2x_run --title 'a/b' -o out.pdf a.md

  assert_success
  assert_file_exists 'out.pdf'
  assert_cwd_files 'a.md' 'out.pdf'
}

@test "-o <input> exits 2 and leaves the input untouched" {
  md2x_write_doc 'a.md'
  local before
  before="$(cat a.md)"

  md2x_run -F html -o a.md a.md

  assert_failure 2
  assert_stderr_contains 'overwrite'
  [[ "$(cat a.md)" == "${before}" ]]
}

@test "-o naming the input through a different spelling or case exits 2" {
  md2x_write_doc 'a.md'

  md2x_run -F html -o ./A.md a.md
  assert_failure 2

  mkdir sub
  md2x_run -F html -o sub/../a.md a.md
  assert_failure 2
}

@test "-o through a symlink to the input exits 2" {
  md2x_write_doc 'a.md'
  ln -s a.md link.html

  md2x_run -F html -o link.html a.md

  assert_failure 2
}

# --- --to-stdout ------------------------------------------------------------------------

@test "--to-stdout writes nothing to the cwd or -p, and stdout equals the converted output" {
  md2x_write_doc 'a.md' 'Streamed'

  md2x_run -F html -o ref.html a.md
  assert_success
  md2x_run --to-stdout -F html -p outdir --title 'x/y' a.md

  assert_success
  assert_cwd_files 'a.md' 'ref.html'
  [[ ! -e outdir ]]
  [[ "${output}" == "$(cat ref.html)" ]]
}

@test "--to-stdout with --keep-intermediate keeps the output only in the work directory" {
  md2x_write_doc 'a.md'

  md2x_run --to-stdout -F html --keep-intermediate a.md

  assert_success
  assert_cwd_files 'a.md'
  assert_file_exists "$(md2x_kept_work_dir)/output.html"
}

@test "--to-stdout with two inputs exits 2" {
  md2x_write_doc 'a.md'
  md2x_write_doc 'b.md'

  md2x_run --to-stdout a.md b.md

  assert_failure 2
  assert_cwd_files 'a.md' 'b.md'
}

@test "--to-stdout with --list-files exits 2" {
  md2x_write_doc 'a.md'

  md2x_run --to-stdout --list-files a.md

  assert_failure 2
}

@test "--to-stdout with --single-page of two inputs is allowed" {
  md2x_write_doc 'a.md'
  md2x_write_doc 'b.md'

  md2x_run --to-stdout -F html --single-page a.md b.md

  assert_success
  assert_cwd_files 'a.md' 'b.md'
}

# --- -p ---------------------------------------------------------------------------------

@test "-p o3/ prints a single slash" {
  md2x_write_doc 'a.md'

  md2x_run -F html -p o3/ a.md

  assert_success
  assert_output_equals 'Created o3/a.html'
}

@test "-p o3/// collapses every trailing slash" {
  md2x_write_doc 'a.md'

  md2x_run -F html -p o3/// a.md
  assert_success
  assert_output_equals 'Created o3/a.html'
}

@test "-p naming an existing file exits 2" {
  md2x_write_doc 'a.md'
  : > afile

  md2x_run -p afile a.md

  assert_failure 2
  assert_stderr_contains 'not a directory'
  refute_stderr_contains 'mkdir:'
}

@test "a mirrored subdirectory blocked by a file exits 2 before any conversion" {
  md2x_write_doc 'docs/a.md'
  md2x_write_doc 'docs/guide/b.md'
  mkdir out
  : > out/guide

  md2x_run -F html -p out docs

  assert_failure 2
  assert_stderr_contains 'out/guide'
  refute_stderr_contains 'mkdir:'
  refute_stub_called pandoc
  assert_file_not_exists 'out/a.html'
}

# --- collisions -------------------------------------------------------------------------

@test "--flatten-dirs with d1/x.md d2/x.md exits 2 naming both sources and writing nothing" {
  md2x_write_doc 'd1/x.md'
  md2x_write_doc 'd2/x.md'

  md2x_run -D -F html -p out d1 d2

  assert_failure 2
  assert_stderr_contains 'd1/x.md'
  assert_stderr_contains 'd2/x.md'
  assert_stderr_contains 'out/x.html'
  assert_file_not_exists 'out/x.html'
  refute_stub_called pandoc
}

@test "directly named d1/x.md d2/x.md exits 2" {
  md2x_write_doc 'd1/x.md'
  md2x_write_doc 'd2/x.md'

  md2x_run -F html d1/x.md d2/x.md

  assert_failure 2
  assert_stderr_contains 'd1/x.md'
  assert_stderr_contains 'd2/x.md'
  assert_file_not_exists 'x.html'
}

@test "x.md plus x.markdown in one directory exits 2" {
  md2x_write_doc 'docs/x.md'
  md2x_write_doc 'docs/x.markdown' 'x'

  md2x_run -F html -p out docs

  assert_failure 2
  assert_stderr_contains 'x.markdown'
  assert_stderr_contains 'x.md'
  refute_stub_called pandoc
}

@test "A.md and a.md flattened together collide (case-insensitive targets)" {
  md2x_write_doc 'd1/A.md'
  md2x_write_doc 'd2/a.md'

  md2x_run -D -F html -p out d1 d2

  assert_failure 2
  refute_stub_called pandoc
}

@test "overwriting an output left by an earlier run stays allowed" {
  md2x_write_doc 'a.md'

  md2x_run -F html a.md
  assert_success
  md2x_run -F html a.md
  assert_success
}

@test "an input that is also the target of another input's conversion exits 2" {
  md2x_write_doc 'a.md'
  printf '# page\n' > a.html

  md2x_run -F html a.md a.html

  assert_failure 2
  assert_stderr_contains 'a.html'
  [[ "$(cat a.html)" == '# page' ]]
}

@test "-o with a trailing slash and an absent directory exits 2 and creates nothing" {
  md2x_write_doc 'a.md'

  md2x_run -o out/ a.md

  assert_failure 2
  assert_stderr_contains "ends in '/'"
  [[ ! -e out ]]
}

# --- delivery: identity re-check and no write through the target path -----------------------

@test "an output path that is a hard link to an input exits 1 and leaves the input untouched" {
  md2x_write_doc 'a.md'
  local before
  before="$(cat a.md)"
  ln a.md link.html

  md2x_run -F html -o link.html a.md

  assert_failure 1
  assert_stderr_contains 'same file'
  [[ "$(cat a.md)" == "${before}" ]]
  [[ "$(cat link.html)" == "${before}" ]]
}

@test "an output path that is a symlink to another file replaces the symlink and spares the file" {
  md2x_write_doc 'a.md'
  printf 'precious\n' > other.txt
  ln -s other.txt out.html

  md2x_run -F html -o out.html a.md

  assert_success
  [[ ! -L out.html ]]
  assert_file_contains 'out.html' 'to: html5'
  [[ "$(cat other.txt)" == 'precious' ]]
}

@test "delivery leaves no temp file beside the output" {
  md2x_write_doc 'a.md'

  md2x_run -F html -o out/x.html a.md

  assert_success
  [[ -z "$(find out -name '.md2x-out.*')" ]]
}

# --- delivery: directory targets, option-like directories, interrupted delivery --------------

@test "-o through a symlink to an existing directory fails and writes nothing into it" {
  md2x_write_doc 'a.md'
  mkdir realdir
  ln -s realdir dirlink

  md2x_run -F html -o dirlink a.md

  assert_failure
  [[ -z "$(ls -A realdir)" ]]
  [[ -L dirlink ]]
  [[ -z "$(find . -name '.md2x-out.*')" ]]
}

@test "-o -d/out.html delivers into a relative directory whose name starts with a dash" {
  md2x_write_doc 'a.md'
  mkdir ./-d

  md2x_run -F html -o -d/out.html a.md

  assert_success
  assert_file_contains './-d/out.html' 'to: html5'
  [[ -z "$(find . -name '.md2x-out.*')" ]]
}

@test "an interrupted delivery leaves no temp file beside the output" {
  md2x_write_doc 'a.md'
  mkdir out
  # A 'cp' that terminates the running md2x between 'mktemp' and the rename.
  printf '#!/bin/sh\nkill -TERM "$PPID"\nsleep 5\n' > "${MD2X_TEST_BIN_DIR}/cp"
  chmod +x "${MD2X_TEST_BIN_DIR}/cp"

  md2x_run -F html -o out/x.html a.md

  assert_failure
  [[ -z "$(find out -name '.md2x-out.*')" ]]
  [[ ! -e out/x.html ]]
}

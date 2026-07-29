#!/usr/bin/env bash
#
# Shared bats helpers for the md2x CLI test suite.
#
# A test file loads this one file:
#
#   load '../helpers/common'
#
#   setup() { md2x_setup; }
#   teardown() { md2x_teardown; }
#
#   @test "converts a file" {
#     md2x_write_doc 'report.md'
#     md2x_run --output-format html report.md
#     assert_success
#     assert_stub_called pandoc
#   }
#
# What 'md2x_setup' establishes, and why:
#
#   * A per-case temporary working directory OUTSIDE the repository, which becomes the
#     case's cwd. This is not optional. 'src/cli/md2x.sh' probes 'git status
#     --porcelain' and 'package.json' from the cwd on every invocation to derive the
#     '--infer-version' string, so running from the repo root would make that string
#     depend on whether the working tree happens to be dirty. Outside a work tree it
#     resolves deterministically to 'working'.
#   * A minimal PATH containing only the stub 'pandoc'/'gs'/'pdftk', the handful of
#     real tools md2x shells out to, and the system directories. The real pandoc, gs
#     and pdftk are deliberately unreachable, so 'md2x_path_without' can drop a stub
#     and genuinely reproduce the missing-binary case.
#   * A stub invocation log ("${MD2X_TEST_STUB_LOG}") and capture directory
#     ("${MD2X_TEST_STUB_CAPTURE_DIR}"), both outside the case's cwd so they never
#     show up in directory listings or '*.md' searches the CLI performs.
#
# Keep every fixture and temp path free of spaces: the CLI word-splits '$SEARCH_DIRS'
# and 'find ${ROOT_DIR}' unquoted, so paths with spaces are already broken upstream.

MD2X_TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MD2X_TEST_ROOT="$(cd "${MD2X_TEST_HELPER_DIR}/.." && pwd)"
MD2X_REPO_ROOT="$(cd "${MD2X_TEST_ROOT}/../../.." && pwd)"
MD2X_STUB_DIR="${MD2X_TEST_ROOT}/stubs"
MD2X_BIN="${MD2X_REPO_ROOT}/bin/md2x"

# shellcheck source=./assertions.bash
. "${MD2X_TEST_HELPER_DIR}/assertions.bash"
# shellcheck source=./stub-log.bash
. "${MD2X_TEST_HELPER_DIR}/stub-log.bash"

# The external binaries md2x preflights and shells out to, all of them stubbed.
MD2X_TEST_STUB_NAMES='pandoc gs pdftk'
# Real tools md2x (or the bash it runs under) needs that are not in the system
# directories below. Symlinked into the case's PATH directory from the ambient PATH.
# 'brew' is in the list because the rolled-in bash-toolkit option parser resolves GNU
# getopt via 'brew --prefix gnu-getopt' on macOS; 'bash' is there so the CLI's
# '#!/usr/bin/env bash' finds the same interpreter a developer would, rather than
# whatever older bash happens to sit in /bin.
MD2X_TEST_PASSTHROUGH_TOOLS='bash brew git jq perl'
# Deliberately minimal: none of pandoc, gs or pdftk live here.
MD2X_TEST_SYSTEM_PATH='/usr/bin:/bin:/usr/sbin:/sbin'

# Absolute path of the built CLI. Tests cd away from the repository, so a relative
# path will not resolve.
md2x_bin() {
  printf '%s\n' "${MD2X_BIN}"
}

# Absolute path of 'src/cli/test', where the checked-in fixtures live.
md2x_test_root() {
  printf '%s\n' "${MD2X_TEST_ROOT}"
}

# --- per-case setup / teardown -----------------------------------------------------

md2x_setup() {
  if ! [[ -x "${MD2X_BIN}" ]]; then
    md2x_fail "built CLI not found at '${MD2X_BIN}'" \
      "run 'make all' (or 'make test', which depends on it) before running bats directly"
    return 1
  fi

  MD2X_TEST_ORIGINAL_PATH="${PATH}"
  MD2X_TEST_ORIGINAL_DIR="${PWD}"

  local tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  MD2X_TEST_TMPDIR="$(mktemp -d "${tmp_root}/md2x-test.XXXXXX")"

  if [[ "${MD2X_TEST_TMPDIR}" == *' '* ]]; then
    md2x_fail "temporary directory path contains a space: ${MD2X_TEST_TMPDIR}" \
      'the CLI word-splits paths unquoted; set TMPDIR to a space-free location'
    return 1
  fi
  if [[ "${MD2X_TEST_TMPDIR}" == "${MD2X_REPO_ROOT}"/* ]]; then
    md2x_fail "temporary directory is inside the repository: ${MD2X_TEST_TMPDIR}" \
      'the version probe would then read the repository git state; set TMPDIR elsewhere'
    return 1
  fi

  MD2X_TEST_WORK_DIR="${MD2X_TEST_TMPDIR}/work"
  MD2X_TEST_BIN_DIR="${MD2X_TEST_TMPDIR}/bin"
  MD2X_TEST_STUB_LOG="${MD2X_TEST_TMPDIR}/stub-invocations.log"
  MD2X_TEST_STUB_CAPTURE_DIR="${MD2X_TEST_TMPDIR}/captures"
  export MD2X_TEST_STUB_LOG MD2X_TEST_STUB_CAPTURE_DIR

  mkdir -p "${MD2X_TEST_WORK_DIR}" "${MD2X_TEST_STUB_CAPTURE_DIR}"
  : > "${MD2X_TEST_STUB_LOG}"

  md2x_use_stub_path
  cd "${MD2X_TEST_WORK_DIR}"
}

md2x_teardown() {
  cd "${MD2X_TEST_ORIGINAL_DIR:-/}" 2>/dev/null || cd /
  if [[ -n "${MD2X_TEST_TMPDIR:-}" ]] \
     && [[ "${MD2X_TEST_TMPDIR}" == */md2x-test.* ]] \
     && [[ -d "${MD2X_TEST_TMPDIR}" ]]; then
    rm -rf "${MD2X_TEST_TMPDIR}"
  fi
  if [[ -n "${MD2X_TEST_ORIGINAL_PATH:-}" ]]; then
    PATH="${MD2X_TEST_ORIGINAL_PATH}"
    export PATH
    hash -r 2>/dev/null || true
  fi
  unset MD2X_TEST_STUB_LOG MD2X_TEST_STUB_CAPTURE_DIR MD2X_TEST_TMPDIR
}

# --- PATH control ------------------------------------------------------------------

# md2x_use_stub_path [stub-to-omit]...
# (Re)builds the case's PATH directory and points PATH at it. Named stubs are left
# out; everything else md2x needs stays reachable.
md2x_use_stub_path() {
  local omitted=" $* "
  local name real

  rm -rf "${MD2X_TEST_BIN_DIR}"
  mkdir -p "${MD2X_TEST_BIN_DIR}"

  for name in ${MD2X_TEST_STUB_NAMES}; do
    [[ "${omitted}" != *" ${name} "* ]] || continue
    ln -s "${MD2X_STUB_DIR}/${name}" "${MD2X_TEST_BIN_DIR}/${name}"
  done

  # Passthrough tools get an exec wrapper rather than a symlink: some of them derive
  # their own installation prefix from argv[0] ('brew --prefix gnu-getopt' would
  # otherwise report the temp directory), and shadowing 'bash' with a symlink to
  # itself is fine but shadowing it with a '#!/usr/bin/env bash' wrapper would recurse.
  for name in ${MD2X_TEST_PASSTHROUGH_TOOLS}; do
    real="$(PATH="${MD2X_TEST_ORIGINAL_PATH}" command -v "${name}" 2>/dev/null || true)"
    [[ -n "${real}" ]] && [[ -x "${real}" ]] || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "'${real}'" > "${MD2X_TEST_BIN_DIR}/${name}"
    chmod +x "${MD2X_TEST_BIN_DIR}/${name}"
  done

  PATH="${MD2X_TEST_BIN_DIR}:${MD2X_TEST_SYSTEM_PATH}"
  export PATH
  hash -r 2>/dev/null || true
}

# md2x_path_without <binary>...
# Rebuilds PATH so the named binaries are not resolvable at all -- the case md2x's
# preflight reports with exit status 2. Fails loudly if one is still reachable, since
# a silently-satisfied preflight would make such a test vacuously pass.
md2x_path_without() {
  md2x_use_stub_path "$@"
  local name
  for name in "$@"; do
    if command -v "${name}" >/dev/null 2>&1; then
      md2x_fail "'${name}' is still on PATH after being excluded: $(command -v "${name}")" \
        'add its directory to the exclusions or narrow MD2X_TEST_SYSTEM_PATH'
      return 1
    fi
  done
}

# --- running the CLI ---------------------------------------------------------------

# Strip environment noise the CLI cannot avoid emitting, so a test can assert on
# stderr. The version probe on 'src/cli/md2x.sh' line 135 runs 'git status --porcelain'
# unconditionally; outside a work tree -- which is exactly where the harness puts every
# case -- git writes a 'fatal: not a git repository' line to stderr and the probe falls
# back to the literal 'working'. That line is expected, not a failure.
md2x_filter_env_noise() {
  grep -v '^fatal: not a git repository' || true
}

# md2x_run [args]...
# Runs the built CLI with the given arguments and sets, like bats' own 'run':
#   $status  exit status
#   $output  stdout only (bats' 'run' merges stderr into it; this wrapper does not)
#   $lines   $output split on newlines
#   $stderr  stderr, with the expected environment noise filtered out
# Never fails the case itself -- assert on the captured values. stdin is inherited, so
# the CLI's '-' (read from stdin) mode is driven with a here-string or a redirect:
# 'md2x_run - <<< "# Heading"'.
md2x_run() {
  local stdout_file="${MD2X_TEST_TMPDIR}/md2x-stdout" \
        stderr_file="${MD2X_TEST_TMPDIR}/md2x-stderr"

  status=0
  "${MD2X_BIN}" "$@" > "${stdout_file}" 2> "${stderr_file}" || status=$?

  output="$(cat -- "${stdout_file}")"
  stderr="$(md2x_filter_env_noise < "${stderr_file}")"

  lines=()
  local line
  while IFS= read -r line; do
    lines+=("${line}")
  done <<< "${output}"
}

# --- fixtures ----------------------------------------------------------------------

# md2x_write_doc <relative-path> [heading]
# Writes a small Markdown document at the given path inside the case's working
# directory, creating parent directories as needed. The heading defaults to the file's
# base name.
md2x_write_doc() {
  local rel="$1" heading="${2:-}"
  [[ -n "${heading}" ]] || heading="$(basename "${rel}" .md)"

  local dir
  dir="$(dirname "${rel}")"
  [[ "${dir}" == '.' ]] || mkdir -p "${dir}"

  cat > "${rel}" <<EOF
# ${heading}

Body text for ${heading}.
EOF
}

# md2x_copy_fixture <fixture-name> [destination]
# Copies a checked-in fixture from 'src/cli/test' (e.g. 'tiny-doc.md') into the case's
# working directory.
md2x_copy_fixture() {
  local name="$1" destination="${2:-.}"
  cp "${MD2X_TEST_ROOT}/${name}" "${destination}"
}

# md2x_make_fixture_tree [root]
# Builds a small nested source tree inside the case's working directory:
#
#   <root>/alpha.md
#   <root>/nested/beta.md
#
# and prints <root> (default 'tree'). Deliberately shallow and space-free.
md2x_make_fixture_tree() {
  local root="${1:-tree}"
  md2x_write_doc "${root}/alpha.md" 'Alpha'
  md2x_write_doc "${root}/nested/beta.md" 'Beta'
  printf '%s\n' "${root}"
}

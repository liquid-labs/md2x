#!/usr/bin/env bats
#
# '--infer-version' and the dependency preflight around it: the version is computed lazily,
# only with the flag, against the git repository of the first input (the cwd for stdin);
# 'git' and 'jq' are needed only for the flag; and pandoc below the minimum version is
# refused. The version reaches the footer through the stub 'gs's '-c' PostScript argument.
#
# The git cases build real throwaway repositories (git and jq are real here, the
# conversion tools are stubs), and skip when git or jq is not installed.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

# The oldest pandoc md2x accepts; keep in step with MD2X_PANDOC_MIN_VERSION in
# 'src/cli/lib/preflight.sh'.
PANDOC_FLOOR='2.0'

require_git_and_jq() {
  PATH="${MD2X_TEST_ORIGINAL_PATH}" command -v git >/dev/null 2>&1 || skip "real 'git' not found"
  PATH="${MD2X_TEST_ORIGINAL_PATH}" command -v jq >/dev/null 2>&1 || skip "real 'jq' not found"
}

# make_repo <dir> <package.json content or ''>: a git repository with one commit holding
# 'doc.md' and, when given, 'package.json'.
make_repo() {
  local dir="${1}" pkg="${2}"
  mkdir -p "${dir}"
  md2x_write_doc "${dir}/doc.md"
  [[ -z "${pkg}" ]] || printf '%s\n' "${pkg}" > "${dir}/package.json"
  (
    cd "${dir}"
    git init -q .
    git add -A
    git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
  )
}

# --- laziness: without the flag nothing touches git, jq or package.json ---------------------

@test "without --infer-version, a cwd with no package.json or git repo gives clean stderr" {
  md2x_write_doc 'report.md'

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  [[ -z "${stderr}" ]] || md2x_fail "unexpected stderr: ${stderr}"
  refute_stderr_contains 'cat:'
  refute_stderr_contains 'jq'
  refute_stderr_contains 'fatal:'
}

@test "without --infer-version, a PATH with no jq (and no git) still succeeds" {
  md2x_write_doc 'report.md'
  md2x_path_without jq git

  md2x_run --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  [[ -z "${stderr}" ]] || md2x_fail "unexpected stderr: ${stderr}"
}

# --- conditional dependencies -------------------------------------------------------------

@test "--infer-version without jq exits 3 naming jq and the flag" {
  md2x_write_doc 'report.md'
  md2x_path_without jq

  md2x_run --infer-version --flatten-dirs --output-path . report.md

  assert_failure 3
  assert_stderr_contains "Required executable 'jq' not found"
  assert_stderr_contains "only for '--infer-version'"
  refute_stub_called pandoc
}

@test "--infer-version without git exits 3 naming git and the flag" {
  md2x_write_doc 'report.md'
  md2x_path_without git

  md2x_run --infer-version --flatten-dirs --output-path . report.md

  assert_failure 3
  assert_stderr_contains "Required executable 'git' not found"
  assert_stderr_contains "only for '--infer-version'"
  refute_stub_called pandoc
}

# --- the inferred version -----------------------------------------------------------------

@test "--infer-version on a clean repository prints the package.json version, unquoted" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_success
  [[ -z "${stderr}" ]] || md2x_fail "unexpected stderr: ${stderr}"
  assert_any_call_contains gs 'Version: 2.3.4'
  refute_any_call_contains gs '"2.3.4"'
}

@test "--infer-version on a dirty repository prints 'working'" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  printf 'edit\n' >> repo/doc.md

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_success
  assert_any_call_contains gs 'Version: working'
  refute_any_call_contains gs '2.3.4'
}

@test "--infer-version uses the first input's repository, not the cwd's" {
  require_git_and_jq
  make_repo cwd-repo '{"name":"a","version":"9.9.9"}'
  make_repo input-repo '{"name":"b","version":"2.3.4"}'

  cd cwd-repo
  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path ../out ../input-repo/doc.md

  assert_success
  assert_any_call_contains gs 'Version: 2.3.4'
  refute_any_call_contains gs '9.9.9'
}

@test "--infer-version on stdin uses the cwd's repository" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'

  cd repo
  md2x_run --infer-version --output-format pdf --output-path ../out - <<< '# Heading'

  assert_success
  assert_any_call_contains gs 'Version: 2.3.4'
}

@test "--infer-version on an input outside any repository warns once and still succeeds" {
  require_git_and_jq
  md2x_write_doc 'report.md'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path . report.md

  assert_success
  assert_stderr_contains 'md2x: warning: --infer-version:'
  assert_stderr_contains 'not inside a git work tree'
  [[ "$(printf '%s\n' "${stderr}" | wc -l | tr -d ' ')" == 1 ]] || md2x_fail "expected exactly one stderr line: ${stderr}"
  refute_any_call_contains gs 'Version:'
}

@test "--infer-version with no package.json warns and omits the version" {
  require_git_and_jq
  make_repo repo ''

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_success
  assert_stderr_contains 'md2x: warning:'
  assert_stderr_contains 'no package.json'
  refute_any_call_contains gs 'Version:'
}

@test "--infer-version with a package.json that has no version warns and omits the version" {
  require_git_and_jq
  make_repo repo '{"name":"x"}'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_success
  assert_stderr_contains 'md2x: warning:'
  assert_stderr_contains 'could not read a version'
  refute_any_call_contains gs 'Version:'
}

@test "--infer-version passes a version with PostScript specials through the escaping" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"1.0)(\\x"}'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_success
  assert_any_call_contains gs 'Version: 1.0\)\(\\x'
}

# --- the pandoc minimum version -----------------------------------------------------------

@test "pandoc below the floor exits 3 with the version message" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_VERSION='pandoc 1.19.2.4'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_failure 3
  assert_stderr_contains "md2x: pandoc 1.19.2.4 is too old; md2x requires pandoc >= ${PANDOC_FLOOR}"
  refute_stub_called pandoc
}

@test "pandoc just below the floor's last component exits 3" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_VERSION='pandoc 1.99.9'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_failure 3
  assert_stderr_contains 'is too old'
}

@test "pandoc exactly at the floor passes" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_VERSION="pandoc ${PANDOC_FLOOR}"

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
  assert_stub_called pandoc
}

@test "pandoc versions compare numerically per component, not as strings" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_VERSION='pandoc 10.0.1-nightly'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_success
}

@test "an unparseable pandoc --version exits 3 with an md2x message" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_VERSION='pandoc, the converter'

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_failure 3
  assert_stderr_contains 'md2x: could not determine the pandoc version'
}

@test "a failing pandoc --version exits 3 with an md2x message" {
  md2x_write_doc 'report.md'
  export MD2X_TEST_STUB_VERSION_EXIT_CODE=1

  md2x_run --output-format html --flatten-dirs --output-path . report.md

  assert_failure 3
  assert_stderr_contains "md2x: could not run 'pandoc --version'"
}

@test "an absent pandoc exits 3 with the md2x message and no raw 'type' text" {
  md2x_write_doc 'report.md'
  md2x_path_without pandoc

  md2x_run report.md

  assert_failure 3
  assert_stderr_contains "Required executable 'pandoc' not found"
  [[ "$(printf '%s\n' "${stderr}" | wc -l | tr -d ' ')" == 1 ]] || md2x_fail "expected one stderr line: ${stderr}"
  refute_stderr_contains 'type:'
}

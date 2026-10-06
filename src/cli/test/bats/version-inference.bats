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

# --- repository config that can run commands --------------------------------------------
#
# A repository's own config is untrusted input: before any 'git status', 'md2x-infer-version'
# reads the config key names and, on any key outside a short allowlist of harmless ones,
# warns once and omits the version. 'git status' itself also runs with submodules ignored.

# assert_version_omitted: the last 'md2x_run' warned about the refusal, still succeeded, and
# the footer carries no 'Version'.
assert_version_omitted() {
  assert_success
  assert_stderr_contains 'md2x: warning: --infer-version: not running git in'
  assert_stderr_contains 'no version in the footer'
  refute_any_call_contains gs 'Version'
}

@test "--infer-version does not run a command named by the repository's core.fsmonitor" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  local sentinel="${PWD}/fsmonitor-ran"
  rm -f "${sentinel}"
  git -C repo config core.fsmonitor "touch '${sentinel}'; true"

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  [[ ! -e "${sentinel}" ]] || md2x_fail "the repository's core.fsmonitor command ran"
  assert_version_omitted
  assert_stderr_contains "'core.fsmonitor'"
}

@test "--infer-version does not run a clean filter configured in the repository, even for a stat-dirty file" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  local sentinel="${PWD}/filter-ran"
  rm -f "${sentinel}"
  # The attributes file is committed; the filter command is added only after the commit so
  # the commit itself does not run it.
  printf '* filter=x\n' > repo/.gitattributes
  git -C repo add .gitattributes
  git -C repo -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m attrs
  git -C repo config filter.x.clean "touch '${sentinel}'; cat"
  # Same content, different mtime: status must re-run the clean filter to find out it is clean.
  touch -t 200001010000 repo/package.json repo/doc.md

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  [[ ! -e "${sentinel}" ]] || md2x_fail "the repository's clean filter ran"
  assert_version_omitted
  assert_stderr_contains "'filter.x.clean'"
}

@test "--infer-version refuses a repository whose config has an include.path key" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  git -C repo config include.path "${PWD}/other-config"

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_version_omitted
  assert_stderr_contains "'include.path'"
}

@test "--infer-version refuses a repository whose config has an includeIf key" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  git -C repo config 'includeIf.gitdir:/nowhere/.path' "${PWD}/other-config"

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_version_omitted
  assert_stderr_contains "'includeif.gitdir:/nowhere/.path'"
}

@test "--infer-version matches command-bearing config keys case-insensitively" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  git -C repo config 'Diff.Foo.TextConv' 'cat'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_version_omitted
}

@test "--infer-version refuses a command-bearing key in the per-worktree config" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  git -C repo config extensions.worktreeConfig true
  git -C repo config --worktree 'diff.foo.command' 'true'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_version_omitted
  assert_stderr_contains "'diff.foo.command'"
}

@test "--infer-version keeps working when the repository config has only ordinary keys" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  git -C repo remote add origin https://example.com/x.git
  git -C repo config branch.main.remote origin
  git -C repo config user.name someone
  git -C repo config extensions.worktreeConfig true

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_success
  [[ -z "${stderr}" ]] || md2x_fail "unexpected stderr: ${stderr}"
  assert_any_call_contains gs 'Version: 2.3.4'

  printf 'edit\n' >> repo/doc.md
  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out2 repo/doc.md
  assert_success
  assert_any_call_contains gs 'Version: working'
}

# --- the allowlist: keys that can make git run something ----------------------------------

# add_config_keys <repo> <raw config text>: appends the text to the repository's own config
# file, bypassing 'git config' so any key and ordering can be written.
add_config_keys() {
  printf '%s\n' "${2}" >> "${1}/.git/config"
}

# make_promisor_repo <repo> <sentinel> [<url>]: a repository whose 'old.md' blob is missing
# locally, with a staged similar 'new.md', so a rename-detecting 'git status' must fetch the
# blob from the promisor remote. The remote's 'uploadpack' command writes the sentinel. The
# remote is only ever a local path or an 'ext::' command: nothing touches the network.
make_promisor_repo() {
  local repo="${1}" sentinel="${2}" url="${3:-${PWD}/no-such-remote}" oid
  mkdir -p "${repo}"
  seq 1 400 > "${repo}/old.md"
  md2x_write_doc "${repo}/doc.md"
  printf '%s\n' '{"name":"x","version":"2.3.4"}' > "${repo}/package.json"
  (
    cd "${repo}"
    git init -q .
    git add -A
    git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
    oid="$(git rev-parse HEAD:old.md)"
    git config core.repositoryformatversion 1
    git config remote.origin.url "${url}"
    git config remote.origin.uploadpack "touch '${sentinel}'; false #"
    git config remote.origin.promisor true
    git config remote.origin.partialclonefilter blob:none
    git config extensions.partialclone origin
    seq 1 399 > new.md
    git add new.md
    git rm -q old.md
    rm -f ".git/objects/${oid:0:2}/${oid:2}"
  )
}

@test "--infer-version does not run a partial-clone remote's uploadpack command to fetch a missing blob" {
  require_git_and_jq
  local sentinel="${PWD}/uploadpack-ran"
  rm -f "${sentinel}"
  make_promisor_repo repo "${sentinel}"

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  [[ ! -e "${sentinel}" ]] || md2x_fail "the remote's uploadpack command ran"
  assert_version_omitted
}

@test "--infer-version does not run an ext:: remote URL command, even with protocol.ext.allow=always" {
  require_git_and_jq
  local sentinel="${PWD}/ext-ran"
  rm -f "${sentinel}"
  printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "${sentinel}" > ext-command.sh
  chmod +x ext-command.sh
  make_promisor_repo repo "${PWD}/uploadpack-ran" "ext::${PWD}/ext-command.sh"
  git -C repo config protocol.ext.allow always

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  [[ ! -e "${sentinel}" ]] || md2x_fail "the ext:: remote command ran"
  [[ ! -e "${PWD}/uploadpack-ran" ]] || md2x_fail "the remote's uploadpack command ran"
  assert_version_omitted
}

@test "--infer-version does not run a clean filter from a submodule's own config" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  local sentinel="${PWD}/submodule-filter-ran" sha
  rm -f "${sentinel}"
  # A committed gitlink with a checked-out submodule, but nothing about it in the outer config.
  mkdir -p repo/sub
  (
    cd repo/sub
    git init -q .
    printf 'a\n' > f.txt
    printf '* filter=x\n' > .gitattributes
    git add -A
    git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m sub
  )
  sha="$(git -C repo/sub rev-parse HEAD)"
  git -C repo update-index --add --cacheinfo "160000,${sha},sub"
  printf '[submodule "sub"]\n\tpath = sub\n\turl = ./sub\n' > repo/.gitmodules
  git -C repo add .gitmodules
  git -C repo -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m gitlink
  git -C repo/sub config filter.x.clean "touch '${sentinel}'; cat"
  touch -t 200001010000 repo/sub/f.txt

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  [[ ! -e "${sentinel}" ]] || md2x_fail "the submodule's clean filter ran"
  assert_success
}

@test "--infer-version still refuses the per-worktree config after more than 64 KB of ordinary keys" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  local sentinel="${PWD}/worktree-filter-ran"
  rm -f "${sentinel}"
  printf '* filter=x\n' > repo/.gitattributes
  git -C repo add .gitattributes
  git -C repo -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m attrs
  # 'extensions.worktreeConfig' comes first, then a key list larger than a pipe buffer.
  add_config_keys repo "$(printf '[extensions]\n\tworktreeConfig = true\n[user]\n'
    awk 'BEGIN { for (i = 0; i < 1200; i++) printf "\tpad-%04d-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx = 1\n", i }')"
  printf '[filter "x"]\n\tclean = touch '"'%s'"'; cat\n' "${sentinel}" > repo/.git/config.worktree
  touch -t 200001010000 repo/package.json repo/doc.md

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  [[ ! -e "${sentinel}" ]] || md2x_fail "the per-worktree clean filter ran"
  assert_version_omitted
  assert_stderr_contains "'filter.x.clean'"
}

# assert_key_refused <config key> <value>: a repository with that one extra key is refused.
assert_key_refused() {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  git -C repo config "${1}" "${2}"

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_version_omitted
}

@test "--infer-version refuses remote.<n>.uploadpack" {
  assert_key_refused remote.origin.uploadpack 'true'
  assert_stderr_contains "'remote.origin.uploadpack'"
}

@test "--infer-version refuses remote.<n>.receivepack, vcs, proxy, promisor and partialclonefilter" {
  assert_key_refused remote.origin.receivepack 'true'
  local key
  for key in vcs proxy promisor partialclonefilter; do
    git -C repo config --unset-all remote.origin.receivepack || true
    git -C repo config "remote.origin.${key}" x
    md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md
    assert_version_omitted
    git -C repo config --unset "remote.origin.${key}"
  done
}

@test "--infer-version refuses protocol.*, url.<base>.insteadOf and every extensions.* but worktreeConfig" {
  assert_key_refused protocol.ext.allow always
  git -C repo config --unset protocol.ext.allow
  git -C repo config 'url.https://example.com/.insteadOf' 'x:'
  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md
  assert_version_omitted
  git -C repo config --unset 'url.https://example.com/.insteadOf'
  git -C repo config extensions.partialClone origin
  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md
  assert_version_omitted
  git -C repo config --unset extensions.partialClone
  git -C repo config submodule.sub.url ./sub
  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md
  assert_version_omitted
}

@test "--infer-version matches the allowlist case-insensitively, so odd casing cannot slip a key through" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  add_config_keys repo '[ReMoTe "origin"]
	UploadPack = true'

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_version_omitted
  assert_stderr_contains "'remote.origin.uploadpack'"
}

@test "--infer-version allows a remote with only url, pushurl and fetch" {
  require_git_and_jq
  make_repo repo '{"name":"x","version":"2.3.4"}'
  git -C repo remote add origin https://example.com/x.git
  git -C repo config remote.origin.pushurl https://example.com/push.git
  git -C repo config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
  git -C repo config user.email someone@example.com
  git -C repo config branch.main.merge refs/heads/main

  md2x_run --infer-version --output-format pdf --flatten-dirs --output-path out repo/doc.md

  assert_success
  [[ -z "${stderr}" ]] || md2x_fail "unexpected stderr: ${stderr}"
  assert_any_call_contains gs 'Version: 2.3.4'
}

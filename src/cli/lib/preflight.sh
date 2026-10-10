# md2x dependency preflight and version-inference helpers. Sourced-only library: defining
# the functions below has no side effects at source time. Kept compatible with bash 3.2
# (no namerefs, no '${var,,}', no 'sort -V').
#
# Every failure goes through the helpers in 'errors.sh' (exit 3 for a dependency problem),
# so a tool's own raw error text never reaches the user.

# The oldest pandoc md2x supports, and why. md2x supports only the weasyprint PDF engine,
# and weasyprint became pandoc's default HTML-to-PDF engine in pandoc 3.4. md2x relies on
# that default, so 3.4 is the floor; an older pandoc would pick a different default engine.
# The floor follows from the pandoc changelog, not from a test run on 3.4: only pandoc
# 3.10.1 has been exercised by hand. Raise the floor here if a newer release is found to be
# required.
MD2X_PANDOC_MIN_VERSION='3.4'

# md2x-version-at-least <found> <floor>
# Returns 0 when dotted-numeric version <found> is greater than or equal to <floor>,
# comparing component by component as base-10 integers (missing components count as 0).
# Both arguments must be dotted digits; the caller validates <found>.
md2x-version-at-least() {
  local FOUND="${1}" FLOOR="${2}" FOUND_PART FLOOR_PART
  while [[ -n "${FOUND}" ]] || [[ -n "${FLOOR}" ]]; do
    FOUND_PART="${FOUND%%.*}"
    FLOOR_PART="${FLOOR%%.*}"
    [[ "${FOUND}" == *.* ]] && FOUND="${FOUND#*.}" || FOUND=''
    [[ "${FLOOR}" == *.* ]] && FLOOR="${FLOOR#*.}" || FLOOR=''
    FOUND_PART=$(( 10#${FOUND_PART:-0} ))
    FLOOR_PART=$(( 10#${FLOOR_PART:-0} ))
    (( FOUND_PART == FLOOR_PART )) && continue
    (( FOUND_PART > FLOOR_PART )) && return 0
    return 1
  done
  return 0
}

# md2x-check-pandoc-version
# Exits 3 when 'pandoc --version' cannot be run or parsed, or reports a version below
# 'MD2X_PANDOC_MIN_VERSION'. The first output line reads 'pandoc 3.10.1' (or, for a
# development build, 'pandoc 3.10.1-nightly'); anything after the leading dotted digits of
# the second word is ignored.
md2x-check-pandoc-version() {
  local VERSION_OUTPUT VERSION_LINE PROGRAM FOUND
  VERSION_OUTPUT="$(pandoc --version 2>/dev/null)" \
    || md2x-die-dependency "could not run 'pandoc --version'; md2x requires pandoc >= ${MD2X_PANDOC_MIN_VERSION}."
  VERSION_LINE="${VERSION_OUTPUT%%$'\n'*}"
  FOUND=''
  read -r PROGRAM FOUND _ <<< "${VERSION_LINE}" || true
  FOUND="${FOUND%%[!0-9.]*}"
  case "${FOUND}" in
    ''|.*|*..*|*.) md2x-die-dependency "could not determine the pandoc version from" \
      "'$(md2x-title-display "${VERSION_LINE}")'; md2x requires pandoc >= ${MD2X_PANDOC_MIN_VERSION}.";;
  esac
  md2x-version-at-least "${FOUND}" "${MD2X_PANDOC_MIN_VERSION}" \
    || md2x-die-dependency "pandoc ${FOUND} is too old; md2x requires pandoc >= ${MD2X_PANDOC_MIN_VERSION}"
}

# md2x-require-infer-version-tools
# '--infer-version' needs 'git' and 'jq'; they are checked only when the flag is given.
md2x-require-infer-version-tools() {
  local TOOL
  for TOOL in git jq; do
    command -v "${TOOL}" >/dev/null 2>&1 \
      || md2x-die-dependency "Required executable '${TOOL}' not found; it is needed only for '--infer-version'. Add to 'PATH' or install, or drop '--infer-version'."
  done
}

# md2x-infer-git <git args...>
# Runs 'git' with the repository-local configuration partly neutralized: the directory comes
# from the inputs, and its '.git/config' is untrusted (a core.fsmonitor, a 'filter.<name>.clean',
# a 'remote.<name>.uploadpack', a 'protocol.ext.allow', ... can all make git run a command).
# The wrapper drops the system and global config, switches off fsmonitor and hooks, forbids
# every transport (protocol.allow=never) and lazy fetching, and takes the optional locks
# away. That is only the second line of defence: 'md2x-infer-version' first refuses, via
# 'md2x-infer-config-refusal', every repository whose local config holds a key outside a
# short allowlist, and it never runs 'git status' in one. 'GIT_NO_LAZY_FETCH' and
# 'GIT_CONFIG_GLOBAL' are ignored by a git too old to know them.
md2x-infer-git() {
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_LAZY_FETCH=1 \
    git --no-optional-locks -c core.fsmonitor= -c core.hooksPath=/dev/null \
      -c protocol.allow=never "$@"
}

# md2x-infer-key-allowed <lowercased config key>
# Returns 0 only for a key known to be benign: plain repository settings, 'user.*',
# 'branch.*', and the 'url', 'pushurl' and 'fetch' variables of a remote. Everything else
# ('remote.<n>.uploadpack', 'protocol.*', 'url.*', 'filter.*', 'submodule.*', every other
# 'extensions.*', ...) is outside the allowlist. The key's last dotted component is the
# variable name; any earlier part is the section and subsection.
md2x-infer-key-allowed() {
  case "${1}" in
    core.repositoryformatversion|core.filemode|core.bare|core.logallrefupdates) return 0;;
    core.ignorecase|core.precomposeunicode|core.symlinks) return 0;;
    extensions.worktreeconfig) return 0;;
    user.*|branch.*) return 0;;
    remote.*.url|remote.*.pushurl|remote.*.fetch) return 0;;
  esac
  return 1
}

# md2x-infer-config-keys <toplevel> <git config scope option>
# Prints the names (never the values) of the keys in one local config file, one per line,
# through 'md2x-infer-git', without '--includes' so nothing is followed. Needs git >= 2.22
# ('--name-only'); an older git fails here, which the caller treats as fail closed.
# The keys are read NUL-delimited ('-z'): a subsection name may hold a tab or any other
# control character, and only NUL is certain not to occur in a key. A bash variable cannot
# hold NUL, so 'tr' turns each NUL into the newline that separates the output lines, and a
# newline inside a key into the control character \001, the way input discovery handles
# 'find -print0'; 'md2x-infer-scan-keys' then refuses any key holding a control character.
# A git failure is the pipeline's failure under 'pipefail'; without it the list comes back
# empty, which the caller also treats as fail closed.
md2x-infer-config-keys() {
  md2x-infer-git -C "${1}" config "${2}" -z --list --name-only 2>/dev/null \
    | LC_ALL=C tr '\000\012' '\012\001'
}

# md2x-infer-scan-keys <key list, one per line>
# Checks every key against 'md2x-infer-key-allowed', case-insensitively: the list is
# lowercased once, so a warning names the lowercased key. A key holding a control
# character (see 'md2x-infer-config-keys') cannot be shown or matched safely and is
# refused as unparseable. Returns 0 when every key is allowed; returns 1 after
# setting 'REASON' in the caller's scope (the caller declares it 'local'). Sets the
# caller's 'WORKTREE_CONFIG' to 1 when 'extensions.worktreeConfig' is present. Uses
# only a here-string and a 'case', never a pipe, so a long list cannot take a
# SIGPIPE under 'pipefail' and slip through.
md2x-infer-scan-keys() {
  local LKEYS LKEY CLEAN
  LKEYS="$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "${1}")"
  # One 'tr' over the whole list (not one check per key): drop every control character but
  # the newline separator, and refuse the list if that changed anything. The trailing 'x'
  # keeps '$(...)' from trimming a final newline off the comparison.
  CLEAN="$(LC_ALL=C tr -d '\001-\011\013-\037\177' <<< "${LKEYS}"; printf x)"
  if [[ "${CLEAN}" != "${LKEYS}"$'\n'x ]]; then
    REASON='its local git config could not be parsed'
    return 1
  fi
  while IFS= read -r LKEY; do
    [[ -n "${LKEY}" ]] || continue
    case "${LKEY}" in
      *.*) ;;
      *) REASON='its local git config could not be parsed'; return 1;;
    esac
    if ! md2x-infer-key-allowed "${LKEY}"; then
      REASON="its local git config has the key '$(md2x-title-display "${LKEY}")', which is not on the list of keys known to be harmless"
      return 1
    fi
    [[ "${LKEY}" != extensions.worktreeconfig ]] || WORKTREE_CONFIG=1
  done <<< "${LKEYS}"
  return 0
}

# md2x-infer-config-refusal <toplevel>
# Reads the repository's own config (and the per-worktree config when
# 'extensions.worktreeConfig' is set) without running anything. Returns 0 after printing a
# one-line reason on stdout when the config holds a key outside the allowlist or cannot be
# read or parsed (fail closed); returns 1 when every key is on the allowlist.
md2x-infer-config-refusal() {
  local TOP="${1}" KEYS WKEYS WFILE REASON='' WORKTREE_CONFIG=0
  KEYS="$(md2x-infer-config-keys "${TOP}" --local)" || KEYS=''
  if [[ -z "${KEYS}" ]]; then
    printf 'its local git config could not be read (git >= 2.22 is needed)'
    return 0
  fi
  if ! md2x-infer-scan-keys "${KEYS}"; then
    printf '%s' "${REASON}"
    return 0
  fi
  if [[ "${WORKTREE_CONFIG}" == 1 ]]; then
    WFILE="$(md2x-infer-git -C "${TOP}" rev-parse --git-path config.worktree 2>/dev/null)" || WFILE=''
    if [[ -z "${WFILE}" ]]; then
      printf 'its per-worktree git config could not be located'
      return 0
    fi
    [[ "${WFILE}" == /* ]] || WFILE="${TOP}/${WFILE}"
    # No per-worktree file, or an empty one, is the ordinary case and holds no keys; a
    # non-empty file whose keys cannot be read is refused below.
    if [[ -s "${WFILE}" ]]; then
      WKEYS="$(md2x-infer-config-keys "${TOP}" --worktree)" || WKEYS=''
      if [[ -z "${WKEYS}" ]]; then
        printf 'its per-worktree git config could not be read'
        return 0
      fi
      if ! md2x-infer-scan-keys "${WKEYS}"; then
        printf '%s' "${REASON}"
        return 0
      fi
    fi
  fi
  return 1
}

# md2x-infer-gitdir-refusal <dir> <toplevel>
# Returns 0 after printing a one-line reason on stdout when the git directory git finds from
# <dir> is not the one it finds for <toplevel>, or when either cannot be resolved (fail
# closed); returns 1 when both resolve to the same directory. The other checks read the
# configuration of the repository found from <toplevel>, so they only mean something when
# that is also the repository <dir> belongs to. They differ under a 'core.worktree'
# redirect: a repository whose config points its work tree at a different, benign
# repository, so that <toplevel> is the benign one and the hostile config is never scanned.
# Refusing is the conservative answer; '-c core.worktree=' is not used to neutralize it.
md2x-infer-gitdir-refusal() {
  local INPUT_GITDIR TOP_GITDIR
  INPUT_GITDIR="$(md2x-infer-git -C "${1}" rev-parse --absolute-git-dir 2>/dev/null)" || INPUT_GITDIR=''
  TOP_GITDIR="$(md2x-infer-git -C "${2}" rev-parse --absolute-git-dir 2>/dev/null)" || TOP_GITDIR=''
  if [[ -z "${INPUT_GITDIR}" ]] || [[ -z "${TOP_GITDIR}" ]]; then
    printf 'its git directory could not be resolved'
    return 0
  fi
  if [[ "${INPUT_GITDIR}" != "${TOP_GITDIR}" ]]; then
    printf 'the git directory found from the input differs from the one for the work tree top (a core.worktree redirect?)'
    return 0
  fi
  return 1
}

# md2x-infer-version <dir>
# Prints the version string for the footer, resolved against the git repository containing
# <dir>: the 'version' of '<toplevel>/package.json', or 'working' when the work tree has
# uncommitted changes. Prints nothing, after one warning on stderr, when <dir> is not in a
# git work tree, the package.json is missing, unreadable, or has no version, or the
# repository's local config holds a key outside the allowlist (or cannot be read; no 'git status'
# runs then), or the git directory found from <dir> differs from the one for the work tree
# top; the caller omits the version from the footer and carries on. Needs 'git' and
# 'jq' (see above).
md2x-infer-version() {
  local DIR="${1}" TOP PKG STATUS VER REASON
  TOP="$(md2x-infer-git -C "${DIR}" rev-parse --show-toplevel 2>/dev/null)" || TOP=''
  if [[ -z "${TOP}" ]]; then
    md2x-warn "--infer-version: '$(md2x-title-display "${DIR}")' is not inside a git work tree; no version in the footer."
    return 0
  fi
  if REASON="$(md2x-infer-gitdir-refusal "${DIR}" "${TOP}")"; then
    md2x-warn "--infer-version: not running git in '$(md2x-title-display "${TOP}")': ${REASON}; no version in the footer."
    return 0
  fi
  PKG="${TOP}/package.json"
  if [[ ! -f "${PKG}" ]]; then
    md2x-warn "--infer-version: no package.json at the top of the git work tree '$(md2x-title-display "${TOP}")'; no version in the footer."
    return 0
  fi
  if REASON="$(md2x-infer-config-refusal "${TOP}")"; then
    md2x-warn "--infer-version: not running git in '$(md2x-title-display "${TOP}")': ${REASON}; no version in the footer."
    return 0
  fi
  # '--ignore-submodules=all' (the flag beats any config) keeps git out of submodules, whose
  # own config could run a filter; '--no-renames' skips the rename detection that can read, and
  # so lazily fetch, blobs.
  STATUS="$(md2x-infer-git -C "${TOP}" status --porcelain --ignore-submodules=all --no-renames 2>/dev/null)" || STATUS='?'
  if [[ -n "${STATUS}" ]]; then
    printf 'working'
    return 0
  fi
  VER="$(jq -r '.version // empty | tostring' "${PKG}" 2>/dev/null)" || VER=''
  if [[ -z "${VER}" ]]; then
    md2x-warn "--infer-version: could not read a version from '$(md2x-title-display "${PKG}")'; no version in the footer."
    return 0
  fi
  printf '%s' "${VER}"
}

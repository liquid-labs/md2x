#!/usr/bin/env bash
# Release md2x: bump, commit, tag, push, bun publish, GitHub release.
#
# Usage: scripts/release.sh [--dry-run] <patch|minor|major|prerelease|X.Y.Z[-pre.N]>
#        scripts/release.sh --print-dist-tag <X.Y.Z[-pre.N]>   (print the dist-tag; no side effects)
#
# Safe to re-run: pass the explicit version of a partly finished release and every step
# whose result already exists (tag, remote tag, npm version, GitHub release) is skipped.
# Secrets are never read or accepted by this script; bun prompts for any one-time code
# itself on the terminal.
#
# Tooling split: bun drives the version bump (bun pm version, which runs package.json's
# preversion hook: make all && make qa), the dry-run pack check (bun publish --dry-run), and the registry
# operations (bun pm whoami, bun info, bun publish). bun publish prompts for the 2FA
# one-time code interactively. Verification status: 1.0.0-alpha.11 was published with
# 'npm publish' (commit a21f731); the switch to 'bun publish' came afterwards, so the
# 'bun publish' path is UNVERIFIED: it has never run live. Only its dry-run form and the
# surrounding logic have been exercised. See RELEASING.md.
set -euo pipefail

DRY_RUN=0
BUMP=''
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"
REMOTE=origin

# Release-note skip list: first-parent commits whose subject matches any of these shell
# globs are bookkeeping noise and are left out of the generated GitHub release notes.
# Add a pattern here to filter more. (The "release: <version>" commit is always skipped.)
NOTES_SKIP_PATTERNS=(
  'release: *'
  'plan:*' 'plan(*' 'plan/*'             # plan bookkeeping, incl. "plan: remove followup [x]"
  'wave(*'                                # wave back-pointers
  'what-next*' 'refresh what-next*'       # what-next cache refreshes
  '*pre-merge sync*'
  "Merge branch 'plan/*"  "Merge branch 'plan-*"  'Merge plan branch*'
  'merging auto-generated release branch*'  # legacy liq release merges
)

# Map a version to its npm dist-tag. A release (no prerelease part) takes 'latest'. A prerelease
# takes its first prerelease identifier (1.0.0-rc.1 -> rc), so it never takes 'latest'. A
# prerelease with a numeric or otherwise unusable identifier (1.0.1-0) or the reserved word
# 'latest' (1.0.0-latest.1) falls back to 'next'. Build metadata (+...) is ignored.
dist_tag_for() {
  local v=${1%%+*} pre tag
  [[ "$v" == *-* ]] || { echo latest; return; }
  pre=${v#*-}; tag=${pre%%.*}
  [[ "$tag" =~ ^[A-Za-z][A-Za-z0-9-]*$ && "$tag" != latest ]] || tag=next
  echo "$tag"
}

while (( $# )); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --print-dist-tag)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] \
        || { echo "--print-dist-tag needs an explicit version (X.Y.Z[-pre.N])." >&2; exit 2; }
      dist_tag_for "$2"; exit 0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) [[ -z "$BUMP" ]] || { echo "Only one bump argument allowed." >&2; exit 2; }; BUMP="$1" ;;
  esac
  shift
done
[[ -n "$BUMP" ]] || { echo "Usage: $0 [--dry-run] <bump>" >&2; exit 2; }

cd "$(git rev-parse --show-toplevel)"
say() { echo "==> $*"; }
# Undo the local version bump. bun.lock is only restored if it is tracked and was modified.
revert_bump() {
  git checkout -- package.json
  [[ -z "$(git status --porcelain --untracked-files=no -- bun.lock)" ]] || git checkout -- bun.lock
}
act() { if (( DRY_RUN )); then echo "[dry-run] would run: $*"; else "$@"; fi; }

PKG_NAME=$(bun -p "require('./package.json').name")
CURRENT=$(bun -p "require('./package.json').version")

# --- pre-flight ---------------------------------------------------------------
say "Pre-flight"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$RELEASE_BRANCH" ]] \
  || { echo "Must be on branch '$RELEASE_BRANCH'." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean." >&2; exit 1; }
git remote get-url "$REMOTE" >/dev/null || { echo "Remote '$REMOTE' not configured." >&2; exit 1; }
# A real run needs both logins. A dry run only warns, so the rest of the rehearsal can run without
# credentials; the warning means a real run would stop here.
preflight_fail() {
  if (( DRY_RUN )); then echo "[dry-run] WARNING: $1 (a real run would stop here)" >&2; else echo "$1" >&2; exit 1; fi
}
bun pm whoami >/dev/null 2>&1 || preflight_fail "Not logged in to npm. Run 'bunx npm login' in your own terminal, then re-run."
gh auth status >/dev/null 2>&1 || preflight_fail "Not logged in to GitHub. Run 'gh auth login' in your own terminal, then re-run."
if (( ! DRY_RUN )) && [[ ! -t 0 ]]; then
  echo "bun publish may need a one-time code; run this script from an interactive terminal." >&2; exit 1
fi
# The preversion hook runs the dev tools from node_modules; install exactly what bun.lock pins
# (aborts on a lockfile/package.json mismatch) before any version bump. Remove any existing
# node_modules first so a stale or tampered tree is never reused: the hook gets a fresh install.
rm -rf node_modules
bun install --frozen-lockfile || { echo "bun install --frozen-lockfile failed; fix bun.lock/package.json and re-run." >&2; exit 1; }

# --- resolve version / resume -------------------------------------------------
RESUME=0
if [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then NEW="$BUMP"; else NEW=''; fi
if [[ "$NEW" == "$CURRENT" ]] && git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null; then
  [[ "$(git rev-parse "v$NEW^{commit}")" == "$(git rev-parse HEAD)" ]] \
    || { echo "Tag v$NEW exists but is not at HEAD." >&2; exit 1; }
  RESUME=1
  say "Resuming release of v$NEW (commit and tag already exist)"
fi

# --- bump, build, QA, commit, tag ---------------------------------
if (( ! RESUME )); then
  say "Bumping version (runs 'make all && make qa' via preversion)"
  say "Building, then running the test suite and lint; this may take some time (output streams below)..."
  bun pm version "${NEW:-$BUMP}" --no-git-tag-version   # stdout left visible so build/test progress streams
  NEW=$(bun -p "require('./package.json').version")
  TAG="v$NEW"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "Tag $TAG already exists." >&2; revert_bump; exit 1; }

  # Pack check on the bumped tree: packs the tarball and proves ESM import, CJS require, and types.
  say "Pack check (make test-pack)"
  make test-pack || { echo "make test-pack failed; reverting the version bump." >&2; revert_bump; exit 1; }

  if (( DRY_RUN )); then
    # Publish rehearsal on the bumped tree (before the revert) so it lists the new version's files.
    # Lists the files; uploads nothing and needs no credentials. The bump is reverted either way.
    say "Dry run: publish rehearsal for $NEW (bun publish --dry-run)"
    REHEARSAL_TAG=$(dist_tag_for "$NEW")
    bun publish --dry-run --access public --tag "$REHEARSAL_TAG" \
      || { echo "bun publish --dry-run failed; reverting the version bump." >&2; revert_bump; exit 1; }
    say "Dry run: build, QA, pack check and publish rehearsal passed for $NEW; reverting local edits"
    revert_bump
  else
    git add package.json
    # A version bump normally leaves bun.lock untouched; only stage it if it changed.
    [[ -z "$(git status --porcelain -- bun.lock)" ]] || git add bun.lock
    git commit -m "release: $NEW"
    git tag -a "$TAG" -m "$TAG"
  fi
fi
TAG="v$NEW"

# --- dist-tag -----------------------------------------------------------------
DIST_TAG=$(dist_tag_for "$NEW")   # 1.0.0-rc.1 -> rc; 1.0.0 -> latest
if [[ "$DIST_TAG" == latest ]]; then PRERELEASE_FLAG=(); else PRERELEASE_FLAG=(--prerelease); fi

# --- push ---------------------------------------------------------------------
say "Pushing branch and $TAG to $REMOTE"
if (( DRY_RUN )); then
  echo "[dry-run] would run: git push $REMOTE HEAD refs/tags/$TAG"
else
  git push "$REMOTE" HEAD
  git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1 \
    || git push "$REMOTE" "refs/tags/$TAG"
fi

# --- publish ------------------------------------------------------------------
say "Publishing $PKG_NAME@$NEW to npm (dist-tag: $DIST_TAG)"
if (( DRY_RUN )); then
  if (( RESUME )); then
    # Resume path: the tree is already at $NEW (commit and tag exist), so there is no bump to revert.
    say "Dry run: publish rehearsal for $NEW (bun publish --dry-run)"
    bun publish --dry-run --access public --tag "$DIST_TAG" \
      || { echo "bun publish --dry-run failed." >&2; exit 1; }
    echo "[dry-run] would run: bun publish --access public --tag $DIST_TAG (the 'bun publish --dry-run' rehearsal just ran above)"
  else
    echo "[dry-run] would run: bun publish --access public --tag $DIST_TAG (the 'bun publish --dry-run' rehearsal already ran above, on the bumped tree)"
  fi
elif [[ -n "$(bun info "$PKG_NAME@$NEW" version 2>/dev/null)" ]]; then
  echo "Already published; skipping."
else
  bun publish --access public --tag "$DIST_TAG"   # bun prompts for the OTP itself
fi

# --- GitHub release -----------------------------------------------------------
say "Creating GitHub release $TAG"
# Notes come from first-parent git history (this project merges branches with --no-ff).
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then BASE="$TAG^"; else BASE=HEAD; fi
PREV_TAG=$(git describe --tags --abbrev=0 --match 'v*' "$BASE" 2>/dev/null || true)
RANGE=${PREV_TAG:+$PREV_TAG..HEAD}
NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
{
  while read -r sha; do
    subj=$(git log -1 --format=%s "$sha")
    skip=0
    # shellcheck disable=SC2053  # the patterns are intentional shell globs
    for pat in "${NOTES_SKIP_PATTERNS[@]}"; do [[ "$subj" == $pat ]] && { skip=1; break; }; done
    (( skip )) && continue
    if [[ $(git rev-list --parents -n1 "$sha" | wc -w) -gt 2 && "$subj" =~ ^Merge\ branch\ \'([^\']+)\' ]]; then
      name=${BASH_REMATCH[1]##*/}; name=${name//[-_]/ }
      # First non-blank body line that is not a '#' comment (e.g. '# Conflicts:'), cut to ~100 chars.
      body=$(git log -1 --format=%b "$sha" | sed -E 's/^[[:space:]]+//' | grep -v -m1 -E '^(#|$)' || true)
      (( ${#body} <= 100 )) || body="${body:0:100}..."
      subj="Merged $name"
    else
      body=''
    fi
    echo "* ${subj}${body:+ - $body}"
  done < <(git rev-list --first-parent "${RANGE:-HEAD}")
  SLUG=$(git remote get-url "$REMOTE" | sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##')
  [[ -z "$PREV_TAG" ]] || printf '\n**Full changelog**: https://github.com/%s/compare/%s...%s\n' "$SLUG" "$PREV_TAG" "$TAG"
} > "$NOTES_FILE"
if (( DRY_RUN )); then
  echo "[dry-run] would run: gh release create $TAG --title $TAG --notes-file <file> --verify-tag ${PRERELEASE_FLAG[*]:-}"
  echo "[dry-run] release notes:"; cat "$NOTES_FILE"
elif gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release exists; skipping."
else
  gh release create "$TAG" --title "$TAG" --notes-file "$NOTES_FILE" --verify-tag ${PRERELEASE_FLAG[@]+"${PRERELEASE_FLAG[@]}"}
fi

say "Done$( (( DRY_RUN )) && echo " (dry run)"): $TAG"

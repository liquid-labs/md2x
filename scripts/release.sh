#!/usr/bin/env bash
# Release @liquid-labs/md2x: bump, commit, tag, push, npm publish, GitHub release.
#
# Usage: scripts/release.sh [--dry-run] <patch|minor|major|prerelease|X.Y.Z[-pre.N]>
#
# Safe to re-run: pass the explicit version of a partly finished release and every step
# whose result already exists (tag, remote tag, npm version, GitHub release) is skipped.
# Secrets are never read or accepted by this script; npm prompts for any one-time code
# itself on the terminal.
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
  '*(pre-merge sync)*'
  "Merge branch 'plan/*"  "Merge branch 'plan-*"  'Merge plan branch*'
  'merging auto-generated release branch*'  # legacy liq release merges
)

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) [[ -z "$BUMP" ]] || { echo "Only one bump argument allowed." >&2; exit 2; }; BUMP="$arg" ;;
  esac
done
[[ -n "$BUMP" ]] || { echo "Usage: $0 [--dry-run] <bump>" >&2; exit 2; }

cd "$(git rev-parse --show-toplevel)"
say() { echo "==> $*"; }
act() { if (( DRY_RUN )); then echo "[dry-run] would run: $*"; else "$@"; fi; }

PKG_NAME=$(node -p "require('./package.json').name")
CURRENT=$(node -p "require('./package.json').version")

# --- pre-flight ---------------------------------------------------------------
say "Pre-flight"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$RELEASE_BRANCH" ]] \
  || { echo "Must be on branch '$RELEASE_BRANCH'." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean." >&2; exit 1; }
git remote get-url "$REMOTE" >/dev/null || { echo "Remote '$REMOTE' not configured." >&2; exit 1; }
npm whoami >/dev/null 2>&1 || { echo "Not logged in to npm. Run 'npm login' in your own terminal, then re-run." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in to GitHub. Run 'gh auth login' in your own terminal, then re-run." >&2; exit 1; }
if (( ! DRY_RUN )) && [[ ! -t 0 ]]; then
  echo "npm publish may need a one-time code; run this script from an interactive terminal." >&2; exit 1
fi

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
  say "Bumping version (runs 'make all && make qa' via npm's preversion)"
  npm version "${NEW:-$BUMP}" --no-git-tag-version >/dev/null
  NEW=$(node -p "require('./package.json').version")
  TAG="v$NEW"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "Tag $TAG already exists." >&2; git checkout -- package.json package-lock.json; exit 1; }

  if (( DRY_RUN )); then
    say "Dry run: build and QA passed for $NEW; reverting local edits"
    git checkout -- package.json package-lock.json
  else
    git add package.json package-lock.json
    git commit -m "release: $NEW"
    git tag -a "$TAG" -m "$TAG"
  fi
fi
TAG="v$NEW"

# --- dist-tag -----------------------------------------------------------------
if [[ "$NEW" == *-* ]]; then
  PRE=${NEW#*-}; DIST_TAG=${PRE%%.*}   # 1.0.0-alpha.11 -> alpha
  PRERELEASE_FLAG=(--prerelease)
else
  DIST_TAG=latest; PRERELEASE_FLAG=()
fi

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
  echo "[dry-run] would run: npm publish --access public --tag $DIST_TAG; checking package contents"
  npm pack --dry-run >/dev/null
elif [[ -n "$(npm view "$PKG_NAME@$NEW" version 2>/dev/null)" ]]; then
  echo "Already published; skipping."
else
  npm publish --access public --tag "$DIST_TAG"   # npm prompts for the OTP itself
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
    for pat in "${NOTES_SKIP_PATTERNS[@]}"; do [[ "$subj" == $pat ]] && { skip=1; break; }; done
    (( skip )) && continue
    if [[ $(git rev-list --parents -n1 "$sha" | wc -w) -gt 2 && "$subj" =~ ^Merge\ branch\ \'([^\']+)\' ]]; then
      name=${BASH_REMATCH[1]##*/}; name=${name//[-_]/ }
      body=$(git log -1 --format=%b "$sha" | sed -n '/./{p;q;}')
      subj="Merged $name"
    else
      body=''
    fi
    echo "* ${subj}${body:+ - $body}"
  done < <(git rev-list --first-parent ${RANGE:-HEAD})
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

# Releasing md2x

The release is automated by [`scripts/release.sh`](./scripts/release.sh). Agents are the primary audience of this file; human operators can run the same script by hand. Read the script for the exact steps. **Agents never publish, push, or tag**: the publish step is user-run (it needs an interactive 2FA code), and agents stop at the dry run.

## Verification status

- `1.0.0-alpha.11` was published with `npm publish` (commit `a21f731`). That path is proven.
- The release script switched to `bun publish` **after** that release, so the `bun publish` path is **unverified**: it has never run live. Only `bun publish --dry-run` (and the script's dry-run mode, which calls it) has been exercised; a dry run does not authenticate or contact the publish endpoint, so it proves the file list and the build hook, not the real upload, the 2FA prompt, or the dist-tag assignment.
- Until a live `bun publish` has succeeded, run the throwaway prerelease in [Recommended: a throwaway prerelease first](#recommended-a-throwaway-prerelease-first) before `1.0.0`. If `bun publish` misbehaves, the fallback is `npm publish --access public --tag <dist-tag>`, the tool that published `1.0.0-alpha.11`.

## Prerequisites

- `bun` and `node` on `PATH`. bun runs the version bump, the build/QA hook, and the registry operations (`bun pm whoami`, `bun info`, `bun publish --access public --tag ...`, reading credentials from `~/.npmrc`). `npm` is used by `make test-pack` and for the post-publish checks.
- `gh` authenticated, for the GitHub release.
- Credential pre-flight: `bun pm whoami` and `gh auth status` must pass. If either fails, authenticate in your own terminal (`bunx npm login`, since bun has no login command; `gh auth login`) and re-run.
- Publishing needs an interactive one-time code (2FA). Run the script from an interactive terminal and let bun prompt. The script never accepts a code or any secret as an argument.
- Confirm the exact version and dist-tag with the user before the first non-dry run.

## Procedure

1. **Preconditions (user actions).**
   1. The working tree is clean and you are on `main` (override with `RELEASE_BRANCH`).
   2. `main` is **pushed** to `origin`. It is many commits (117+ at the time of writing) ahead of `origin`; pushing it and **observing CI green** ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml), Ubuntu and macOS) are user actions that must precede the release. The script does not check CI.
   3. For `1.0.0` (not a prerelease), [`CHANGELOG.md`](./CHANGELOG.md) has its `Unreleased` heading replaced by `1.0.0 - <date>`, committed. The release script does not edit the changelog, and its release commit holds only the `package.json` bump (plus `bun.lock` if it changed).
   4. `make qa` passes locally (the script re-runs it, but fail early).
2. **Dry run.** See [Dry run](#dry-run). Fix anything it reports.
3. **Run the release** from an interactive terminal: `scripts/release.sh <version>`. In order, the script:
   1. Pre-flight: clean tree, on the release branch, `origin` configured, `bun pm whoami`, `gh auth status`, then `rm -rf node_modules` and `bun install --frozen-lockfile` so the dev tools exactly match `bun.lock`.
   2. Version bump with `bun pm version --no-git-tag-version`, whose `preversion` hook runs `make all && make qa`.
   3. Build and pack check: `make test-pack` ([`scripts/test-pack.sh`](./scripts/test-pack.sh)) packs the tarball, installs it into a fresh temp project, and proves the ESM import, CJS require, and TypeScript types. Failure reverts the bump.
   4. Commits `release: <version>` and creates the annotated `v<version>` tag.
   5. Pushes the branch and `refs/tags/v<version>` to `origin`.
   6. Publishes with `bun publish --access public --tag <dist-tag>` (`prepack` runs `make all` again; bun prompts for the 2FA code).
   7. Creates the GitHub release with `gh release create --verify-tag` (`--prerelease` for prereleases). Notes are generated from first-parent git history since the previous `v*` tag (one entry per merged branch, plus a compare link); the curated record is `CHANGELOG.md`.
4. **Dist-tag.** See [Dist-tag handling](#dist-tag-handling). The script chooses it; confirm it in the dry-run output before the real run.
5. **Tag push.** Step 3.5 already pushes the tag. If the script was interrupted after the commit, re-run it with the same explicit version (see [Resuming](#resuming-an-interrupted-release)); it pushes whatever is missing.
6. **Post-publish verification.** Read the package name in the repo root, then work in an empty temporary directory:

   ```bash
   PKG=$(node -p "require('./package.json').name")   # run in the repo root first: the published package name
   npm view "$PKG" dist-tags                    # the expected tag points at the new version
   npm install "$PKG@<version>"
   npx md2x --version                           # prints: md2x <version>
   ```

   `npm view` can lag the publish by a short time; retry before assuming failure. Also check that the GitHub release exists and is marked prerelease only for prereleases.

## Dry run

```bash
scripts/release.sh --dry-run <version>       # e.g. 1.0.0-rc.1 or 1.0.0
scripts/release.sh --print-dist-tag <version>  # only prints the dist-tag; no side effects
npm pack --dry-run                            # what npm would put in the tarball
bun publish --dry-run --access public --tag <dist-tag>   # what bun would publish
make test-pack                                # packs and installs the tarball, checks ESM, CJS, types
```

What each proves:

| Command | Proves | Cannot prove |
| --- | --- | --- |
| `scripts/release.sh --dry-run <version>` | Pre-flight, a clean install from `bun.lock`, the version bump, `make all && make qa`, `make test-pack`, a `bun publish --dry-run --access public --tag <dist-tag>` rehearsal (on the bumped tree before the revert; when resuming a release whose commit and tag already exist, in the publish step, with nothing to revert), the computed dist-tag, and the release notes. Nothing is committed, tagged, pushed, published, or released; the bump is reverted. Missing npm or GitHub credentials are reported as warnings (a real run stops there). | That credentials work, that the push or publish succeeds, that the 2FA prompt behaves. |
| `--print-dist-tag <version>` | The dist-tag (and whether the GitHub release is a prerelease) for a version. | Anything else. |
| `npm pack --dry-run` | The exact file list and size of the tarball (`bin/*`, `dist/*`, `CHANGELOG.md`, plus the always-included `package.json`, `README.md`, `LICENSE.txt`). | That the tarball works once installed (that is `make test-pack`). |
| `bun publish --dry-run` | That bun builds the same file list (it runs `prepack`) and would send the given tag and access level. Needs no credentials. `scripts/release.sh --dry-run` runs it against the bumped version (on both the fresh and the resume path), so the file list and tag match the real publish. | Authentication, the registry's acceptance, 2FA, and tag assignment. This is the unverified part; see [Verification status](#verification-status). |
| `npm publish --dry-run` | The same for npm, the tool that published `1.0.0-alpha.11`. | The same limits. |
| `make test-pack` | The packed artifact imports under ESM and CJS and its types compile. Needs `bun install` (it uses the pinned `tsc`). | Behavior against the real registry. |

Notes:

- `npm pack --json` prints the `prepack` output (`make all`) on stdout before the JSON, so the output does not parse. Add `--ignore-scripts` for clean, parseable JSON: `npm pack --dry-run --json --ignore-scripts`.
- The version printed by `md2x --version` is not hand-maintained: the build injects it from `package.json` into `bin/md2x` (the `@MD2X_VERSION@` placeholder, see the `bin/md2x` rule in the [`Makefile`](./Makefile)), and `package.json` is a prerequisite of that rule, so a version bump rebuilds the binary. `preversion` and `prepack` both run `make all`, so the published `bin/md2x` carries the published version. A stale or hand-edited `bin/md2x` is never the source.
- The dry-run mode does the real clean install and runs the full QA, so it takes minutes and needs the network for `bun install`.

## Dist-tag handling

The script computes the dist-tag from the new version (`dist_tag_for` in `scripts/release.sh`; inspect it with `scripts/release.sh --print-dist-tag <version>`):

| Version | Dist-tag | GitHub release |
| --- | --- | --- |
| `1.0.0` (no prerelease part) | `latest` | normal |
| `1.0.0-rc.1` | `rc` | prerelease |
| `1.0.0-alpha.12` | `alpha` | prerelease |
| `1.0.1-0` (numeric first identifier) | `next` | prerelease |
| `1.0.0-latest.1` (reserved word) | `next` | prerelease |

Prerelease versions never take `latest`; `1.0.0` does. Build metadata (`+...`) is ignored. The script publishes with `--tag <dist-tag>` explicitly, so a prerelease cannot become `latest` by default. If a tag is wrong after the fact, fix it with `npm dist-tag add <package>@<version> <tag>` (a user action; needs credentials).

## Recommended: a throwaway prerelease first

Because the `bun publish` path has never run live, publish `1.0.0-rc.1` under the `rc` dist-tag before `1.0.0`. The user runs these steps:

1. Complete the preconditions above (a prerelease may ship with the changelog still under `Unreleased`).
2. `scripts/release.sh --dry-run 1.0.0-rc.1`, and confirm `dist-tag: rc`.
3. `scripts/release.sh 1.0.0-rc.1` from an interactive terminal; enter the 2FA code when bun prompts.
4. Verify as in the post-publish step: `rc` points at `1.0.0-rc.1`, and **`latest` did not move** (`npm view <package> dist-tags`).
5. Install `<package>@rc` in an empty directory and run `npx md2x --version` (expect `md2x 1.0.0-rc.1`) and a small conversion.
6. If anything is wrong, fix it, and either release `1.0.0-rc.2` or fall back to `npm publish`. Do not unpublish; npm's unpublish rules are restrictive, so a bad version is superseded instead.
7. When satisfied, date the changelog, commit, push, observe CI green, and run `scripts/release.sh 1.0.0`. This takes `latest`.

## Resuming an interrupted release

Re-run with the explicit version of the interrupted release (for example `scripts/release.sh 1.0.0`). Every step whose result already exists (tag, remote tag, registry version, GitHub release) is skipped. A tag that exists but is not at `HEAD` aborts the run.

## Manifests and artifacts

Manifests are `package.json` (primary) and `bun.lock`. The published files are `bin/md2x`, `dist/md2x.mjs` (ESM), `dist/md2x.cjs` (CommonJS), `dist/index.d.ts` (types), and `CHANGELOG.md`, plus the automatically included `package.json`, `README.md`, and `LICENSE.txt`. The tag prefix is `v`.

# Releasing md2x

The whole release is automated by [`scripts/release.sh`](./scripts/release.sh). Agents are the primary audience of this file; human operators can run the same script by hand. Read the script for the exact steps.

## What the script does

Pre-flight checks (clean tree, on `main` (override with `RELEASE_BRANCH`), `origin` configured, `bun pm whoami`, `gh auth status`, and a clean install: `node_modules` is removed, then `bun install --frozen-lockfile` reinstalls everything so the dev tools exactly match `bun.lock`), then a version bump through `bun pm version --no-git-tag-version` (whose `preversion` hook runs `make all && make qa`), a `release: <version>` commit containing only the `package.json` bump (plus `bun.lock` if it changed) and `v<version>` tag, a push of the branch and `refs/tags/v<version>` to `origin`, `bun publish --access public` under the `alpha` dist-tag for prereleases (`latest` otherwise), and `gh release create --verify-tag` (with `--prerelease` for prereleases). Release notes are generated from first-parent git history since the previous `v*` tag (one entry per merged branch, plus a compare link) and passed with `--notes-file`; there is no changelog file.

Manifests are `package.json` (primary) and `bun.lock`; the published artifacts are `bin/md2x` and `dist/md2x.js`; the tag prefix is `v`.

## Usage

```bash
scripts/release.sh --dry-run prerelease   # all checks, build and QA; no commit, push, publish, or release
scripts/release.sh prerelease             # e.g. 1.0.0-alpha.10 -> 1.0.0-alpha.11
scripts/release.sh 1.0.0-alpha.11         # explicit version; also resumes a partly finished release
```

The bump argument is any `bun pm version` argument (`patch`, `minor`, `major`, `prerelease`) or an explicit version (`X.Y.Z[-pre.N]`). Re-running with the explicit version of an interrupted release skips every step whose result already exists (tag, remote tag, npm version, GitHub release).

## Prerequisites

- `bun` and `node` on `PATH`. bun runs the version bump, the build/QA hook, the `bun pm pack --dry-run` check, and the registry operations: `bun pm whoami`, `bun info`, and `bun publish --access public --tag ...` (it reads credentials from `~/.npmrc`). This replaced npm for publishing and is unverified by a live publish until the next real release.
- Credential pre-flight: `bun pm whoami` and `gh auth status` must pass. If either fails, authenticate yourself in your own terminal (`bunx npm login`, since bun has no login command; `gh auth login`) and re-run.
- Publishing requires an interactive one-time code (2FA). The publish step is **user-run**: run the script from an interactive terminal and let bun prompt for the code. The script never accepts a code or any secret as an argument.
- Confirm the exact version and dist-tag with the user before the first non-dry run.

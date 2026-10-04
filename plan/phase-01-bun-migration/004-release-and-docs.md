# Update release.sh, RELEASING.md, and Project Docs for Bun

## Purpose and scope

Make the release script and all docs reflect bun as the standard dev runtime and install agent, with npm retained only where it is the registry client. Files: `scripts/release.sh`, `RELEASING.md`, `AGENTS.md`, `README.md`, `docs/architecture.md`, `docs/project-structure.md`, `docs/md2x-spec.md`, `.gitignore`. No hook scripts exist in this repo (no `.githooks`/`hooks`, `core.hooksPath` unset), so there is nothing to change there; re-confirm with a grep. Depends on tasks 001-003 (final tool choices are known).

## Requirements

1. `scripts/release.sh` (read it fully first):
   - Version bump: the script runs `npm version <bump> --no-git-tag-version`, whose `preversion` runs `make all && make qa`. Test empirically (in a scratch clone or with `--dry-run`, never a real release) whether `bun pm version <bump> --no-git-tag-version` runs the `preversion` hook and accepts `patch|minor|major|prerelease|X.Y.Z[-pre.N]`. Use it only if it does; otherwise keep `npm version` and say why in a comment.
   - `package-lock.json` references (`git checkout -- package.json package-lock.json`, `git add ...`) become `bun.lock`; since a version bump may not change `bun.lock`, make add/checkout robust to it being unchanged (e.g. only include it if modified).
   - `npm pack --dry-run` in the dry-run publish step becomes `bun pm pack --dry-run` (verify it works and lists the same files).
   - Registry operations stay on npm and are documented as intentional: `npm whoami`, `npm view`, `npm publish --access public --tag ...` (RELEASING.md documents that npm prompts for the OTP interactively; bun publish is not relied on). Update the header comment accordingly.
   - Optionally replace `node -p "require(...)"` with `bun -p` if it works identically; otherwise leave as `node -p`.
   - `bash -n scripts/release.sh` must pass and `scripts/release.sh --dry-run prerelease` must be exercised only up to the point it is safe: it requires branch `main`, a clean tree, and npm/gh login, so if the environment cannot satisfy pre-flight, validate the changed steps individually (the bump command and pack command) and state that limitation in the report. Never publish, push, or tag.
2. `RELEASING.md`: update the summary paragraph, manifests line (`package.json` and `bun.lock`), bump-argument wording, and prerequisites to match the script; keep the explicit note that npm remains for whoami/publish and why; add bun as a prerequisite.
3. `AGENTS.md`: `bun install`, `bun run build`, `bun test`-style commands (keep `make` targets as the primary interface); `make test-node` description becomes "bun test" with coverage; drop `test-staging/` from the outputs list; the Conventions linting bullet describes direct eslint (named config file) instead of catalyst-scripts; the RELEASING bullet no longer implies npm-only tooling; note bun and node both required on PATH.
4. `README.md`: contributor/dev-facing text moves to bun; the consumer install instructions (`npm install @liquid-labs/md2x`, `npm install -g`) stay valid, optionally add the bun equivalent (`bun add`, `bun add -g`).
5. `docs/architecture.md` (lines ~64 and ~101) and `docs/project-structure.md` (`package-lock.json` row becomes `bun.lock`, npm wording for the Makefile/package.json rows, `node_modules` comment) and `docs/md2x-spec.md` (line ~129 mentions `npm run build`; adjust to `bun run build`/`make all`): remove every catalyst-scripts mention and describe the new build (`bun build`), test (`bun test`), and lint (eslint) tooling. The `npm` distribution statements (published npm package) stay.
6. `.gitignore`: confirm `test-staging` is gone (task 002), `bun.lock` is NOT ignored, and no `package-lock.json` entry is needed. Historical `plan/plan-summary-*.md` files are records and are not edited.
7. This task also covers the architecture-doc update that the plan would otherwise defer (the change has no public API or spec-behavior impact), so no separate doc-updates phase exists.

## Validation

- `bash -n scripts/release.sh` exits 0; `grep -n "package-lock" scripts/release.sh RELEASING.md AGENTS.md docs/*.md README.md` returns nothing.
- `grep -rIn "catalyst-scripts\|test-staging" --exclude-dir=plan --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=worktrees .` returns nothing (the untracked `.flow/` assessment file is outside the tree searched).
- `grep -rIn "npm " AGENTS.md RELEASING.md README.md docs scripts` shows only intentional uses (consumer install, npm whoami/view/publish, published-package statements); each remaining use is justified in the report.
- The commands documented in AGENTS.md (`bun install`, `bun run build`, `bun test ./src/node`, `make test`, `make lint`) are each run once and succeed.

## Status

Outcome: succeeded (2026-10-04). Validation: `bash -n scripts/release.sh` ok; no `package-lock`/`catalyst-scripts`/`test-staging` hits; remaining `npm ` uses are consumer install, npm whoami/view/publish, and published-package statements; `bun install`, `bun run build`, `bun test ./src/node`, `make test`, `make lint` all succeed (log `.flow/validation-logs/04-docs-commands.log`). Empirically (scratch copy): `bun pm version` runs `preversion` and accepts prerelease/patch/X.Y.Z-pre.N, leaving `bun.lock` untouched, so release.sh uses it; `bun pm pack --dry-run` works. Full `release.sh --dry-run` not run (needs main branch, npm/gh login). Files: `scripts/release.sh`, `RELEASING.md`, `AGENTS.md`, `README.md`, `docs/architecture.md`, `docs/project-structure.md`, `docs/md2x-spec.md`.

# Package Node Library for ESM, CJS, and Types

## Purpose and scope

Ship the Node library as a dual ESM/CJS package with a hand-written `index.d.ts` and a `package.json` `exports` map, so that all of the following work from a packed tarball:

- `import { md2x, md2xAsync } from '@liquid-labs/md2x'` under native Node ESM
- `require('@liquid-labs/md2x')`
- TypeScript consumers

This is a standard implementation task; no dedicated skill applies.

Covers the packaging part of S11, R4, and the "verified from a packed tarball" phase output.

Depends on:

- `007-rewrite-node-wrapper-on-child-process`, which fixes the final API the types describe
- `001-add-version-flag-and-help-contract`, because both edit the `Makefile`

It edits the `Makefile` `NODE_DIST` recipe and targets, `package.json` (`main`, `types`, `exports`, `files`), and `src/node/` (the `.d.ts` source and ESM-safe bin resolution).

Out of scope: the other `package.json` metadata, such as `keywords`, `repository`, and `description`, plus the `prepack` script. Phase 3 owns those.

## Requirements

Follow the Packaging and Validation bullets of [Node wrapper](../notes/design-decisions.md#node-wrapper).

1. **Dual build.**
   - Build an ESM bundle and a CJS bundle from `src/node/index.js` with `bun build`, for example `dist/md2x.mjs` and `dist/md2x.cjs`. Choose names that make each format unambiguous to Node regardless of the package `type`.
   - Keep `--packages=external`; there are no runtime dependencies left.
   - Decide whether to keep the inline sourcemaps, and state the decision. They inflate the published size.
   - Remove the old `dist/md2x.js` target, or keep it as the CJS entry, so nothing stale ships.
   - `make all` builds both. `make clean` removes both.
2. **Bin resolution under ESM.**
   - `resolveBin()` uses `__dirname`, which does not exist in native ESM. In the ESM build, resolve from `import.meta.url` with `fileURLToPath`, or confirm that `bun build --format=esm` shims `__dirname` correctly. Prove it by running the packed ESM entry, not by reading the bundle.
   - It must still resolve `bin/md2x` from source (`src/node`) for `bun test`, and from `dist/` in the installed package.
3. **Types.**
   - Hand-write `index.d.ts`, either in `src/node/index.d.ts` copied to `dist/` by the build or directly as a shipped file.
   - It declares `md2x(options: Md2xOptions): string[]` and `md2xAsync(options: Md2xOptions): Promise<string[]>`.
   - `Md2xOptions` lists exactly the options task 007 accepts, with JSDoc on each, including the `markdown`/`sources` exclusivity. Use a union type if it stays readable; otherwise document it.
   - Declare an error type, or interface, carrying `exitCode?: number` and `stderr?: string`.
   - Note the newline-in-path limitation in the JSDoc.
4. **`package.json`.**
   - `main` points at the CJS bundle. `types` points at the shipped `.d.ts`.
   - `exports` has `"."` with conditions in the order `types`, `import`, `require`, and also exports `./package.json`.
   - `files` covers the new `dist` artifacts and `bin/*`.
   - Do not add `"type": "module"` unless it is needed. If added, check its effect on `eslint.config.mjs` and the tests.
5. **Verification script.**
   - Add a repeatable check, for example a `make test-pack` target or a `scripts/` helper, and wire it into `make qa` only if it runs quickly and offline. Otherwise document it as a release-time check and state which in your report.
   - The check does the following:
     1. Runs `npm pack` (or `bun pm pack`).
     2. Installs the tarball into a fresh temp project with no network access to the registry needed, using a local file install.
     3. Runs `node --input-type=module -e "import { md2x, md2xAsync } from '@liquid-labs/md2x'; …"` and a CJS `node -e "const { md2x } = require('@liquid-labs/md2x'); …"`. Each asserts both exports are functions and that a validation `TypeError` is thrown for `{}`.
     4. Runs `tsc --noEmit` on a consumer `.ts` snippet that uses both functions and the option and error types, if TypeScript is available through `bunx`/`npx` without adding a dependency. Otherwise it validates the `.d.ts` syntactically and says so.
   - Also confirm from the `npm pack --dry-run` file list that `LICENSE.txt`, `bin/md2x`, both bundles, and the `.d.ts` are present. Phase 3 rechecks `files` (D15), but this task must not ship a broken tarball.

## Validation

- `make clean && make all && make qa` passes.
- The pack verification above passes on this host for ESM import, CJS require, and the types check. Report the exact commands and output.
- The pre-task tarball fails the native ESM named import (`SyntaxError: Named export 'md2x' not found`), and the post-task tarball passes it. Your report states that this was checked.
- `node -e "require('./dist/md2x.cjs')"` (or the chosen name) and `node --input-type=module -e "await import('./dist/md2x.mjs')"` both load from the repo root.
- `git diff --stat` touches only the `Makefile`, `package.json`, `src/node/**`, and any new verification script.

## Assumptions

- Task 007 is complete: `md2x` and `md2xAsync` are exported, and there are no runtime dependencies.
- Task 001 has already changed the `CLI_BIN` recipe. Keep that change intact when editing the `Makefile`.
- Node 18 or later is the consumer baseline for `exports` and `import.meta.url`. If you find a reason to set an `engines` field, report it rather than adding it, because Phase 3 owns package metadata.

## References

- [Design decisions: Node wrapper](../notes/design-decisions.md#node-wrapper): packaging and validation.
- [Sequencing and file ownership](../notes/sequencing-and-file-ownership.md): `package.json`, `bun.lock`, and `Makefile` serialization.
- [Audit coverage](../notes/audit-coverage.md): rows S11 and R4.
- `<project_root>/.flow/audit-interface.md` S11: the reproduced ESM failure.
- `Makefile` (`NODE_DIST`), `package.json`, and `src/node/*`.

## Checkpoint hints

- After the dual build and ESM-safe bin resolution.
- After `index.d.ts` and the `package.json` `exports`.
- After the pack verification passes.

## Status

Outcome: succeeded (2026-10-05). `make clean && make all && make qa` and `make test-pack` pass. Changed: `Makefile`, `package.json`, `src/node/md2x.js`, `src/node/index.d.ts`, `scripts/test-pack.sh`, plus doc drift in `AGENTS.md` and `docs/project-structure.md`. Decisions: bundles are `dist/md2x.mjs`/`dist/md2x.cjs`, sourcemaps dropped, `dist/md2x.js` removed; `make test-pack` is a release-time check, not in `qa` (npm install plus a possible npx TypeScript fetch).

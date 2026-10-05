# Rewrite Node Wrapper on Child Process

## Purpose and scope

Rewrite `src/node/md2x.js` on `node:child_process` with argv arrays, removing `shelljs`, the shell-quoting layer, and the `shell: '/bin/bash'` requirement. The rewrite also:

- feeds `markdown` to `md2x -` on stdin
- validates options before spawning
- adds `output` and `quiet` options and an async `md2xAsync()`
- throws errors that carry `exitCode` and `stderr`

This is a standard implementation task; no dedicated skill applies.

Covers user decision 7, S11 (except packaging), the S2 Node `[]` case, R2 (staging removed), R9 (shelljs replaced), R12 (coverage), and the "Could not covert" typo from S8.

Dependencies:

- Depends on `003-add-output-option-and-collision-checks`, because the `output` option maps to the CLI's `-o`.
- Runs in parallel with `004`, `005`, and `006`. It edits only `src/node/**`, `package.json` (the `dependencies` block), and `bun.lock`.
- `008-package-node-library-for-esm-cjs-and-types` follows it.

Out of scope: dual ESM/CJS builds, `exports`, and `index.d.ts`, all in task 008. README Node docs belong to Phase 3.

## Requirements

Follow [Node wrapper](../notes/design-decisions.md#node-wrapper).

1. **Process execution.**
   - `md2x()` uses `execFileSync(binPath, argv, { input, stdio, maxBuffer, encoding })`. No shell, no string command, no `shellQuote`.
   - Set `maxBuffer` generously, for example 64 MiB. A first-run WeasyPrint install writes a lot to stderr, and the default 1 MiB would turn a successful run into an error.
   - When `markdown` is absent, the child's stdin is `'ignore'`, so the CLI can never block on an inherited stdin.
   - Keep `resolveBin()`, which never uses npx/bunx/`PATH`, and keep its error message. Its use of `__dirname` is task 008's concern. Keep it working from source and from the CJS bundle.
2. **Inputs.**
   - `markdown` (a string) is fed on stdin as `md2x - …`. There is no staging file, no `Math.random`, and no title-derived path.
   - `sources` (an array of non-empty strings) is passed as separate argv elements.
   - `sources: ['-']`, or any `'-'` entry, throws `TypeError` telling the caller to use `markdown`. This fixes the hang.
   - `sources: []` or a missing `sources` without `markdown` throws `TypeError`.
   - `markdown` together with `sources` throws `TypeError`.
3. **Option validation.** Validate before spawning, and throw `TypeError` naming the option:
   - The allowed keys are exactly `markdown`, `sources`, `format`, `flattenDirs`, `inferTitle`, `inferVersion`, `noToc`, `toc`, `outputPath`, `output`, `title`, `singlePage`, and `quiet`. Any other key, such as `keepIntermediate`, throws.
   - Booleans must be booleans. Strings must be non-empty strings.
   - `format` must be one of `pdf`, `html`, or `docx`, case-insensitively. Pass it through lowercased.
   - `toc` with `noToc`, or `output` with `outputPath`, throws.
   - `output: '-'` throws, because the wrapper returns file paths, not bytes. This is a planner choice.
   - Leave `title`-with-many-files and `-o`-with-many-outputs to the CLI's exit-2 errors, which surface as a thrown `Error`.
4. **New options.**
   - `output` maps to `-o <path>`.
   - `quiet: true` suppresses forwarding the CLI's stderr to `console.error` on success.
   - The default `title` is no longer `Report`. Omit `--title` unless the caller gives one, so the CLI default (`output`) applies.
   - State this change in your report for the Phase 3 changelog.
5. **Errors.**
   - A non-zero exit throws an `Error` with the message `md2x failed (exit <code>): <stderr>`, or similar. It carries `exitCode` (a number) and `stderr` (a string).
   - Fix the "covert" typo.
   - A spawn failure, such as a missing bin or `bash` not found, throws an `Error` whose cause is preserved, with `exitCode` undefined.
6. **Return value.**
   - Unchanged: the `--list-files` stdout lines, as an array of paths.
   - Note the known limitation that a path containing a newline mis-splits in a JSDoc comment. Phase 3 documents it.
7. **`md2xAsync()`.**
   - Takes the same options and the same validation. Validation errors reject the returned Promise rather than throwing synchronously.
   - Returns a `Promise<string[]>` with the same error shape.
   - `execFile` has no `input` option, so use `spawn`/`execFile` and write `markdown` to `child.stdin`, then end it. Handle `EPIPE` if the child exits early.
   - Share argv building and validation with `md2x()`. Do not duplicate them.
8. **Exports.** `src/node/index.js` exports `md2x` and `md2xAsync`.
9. **Dependencies.**
   - Remove `shelljs` from `package.json` `dependencies`, which leaves the package with zero runtime dependencies, and update `bun.lock` with `bun install`.
   - Do not touch `exports`, `main`, `types`, or the `Makefile`. Those belong to task 008.
10. **Tests.** Rewrite `src/node/md2x.test.js` to mock `node:child_process` instead of `shelljs`, and close the R12 gaps. Cover:
    - argv shape for every option, including `-o` and `--title` with quotes, spaces, and `$`, passed verbatim with no quoting
    - `markdown` sent as `input`, with leading spaces and a missing final newline preserved byte-exact, and `-` as the only positional argument
    - stdin `'ignore'` for sources
    - every `TypeError` case above
    - non-zero exit → `exitCode` and `stderr` on the error
    - a spawn error
    - `quiet` suppressing `console.error`
    - the `resolveBin` failure branch
    - `md2xAsync` success, failure, and validation rejection
    - Optionally, a gated integration test that runs the real `bin/md2x` on a tiny markdown string to `html` and skips when pandoc is absent.

## Validation

- `make qa` passes, including `bun test` with coverage and `eslint` on `src/node`.
- `grep -rn 'shelljs\|shell.exec\|shellQuote\|covert\|Math.random' src/node` finds nothing.
- `package.json` has no `dependencies` entries, or an empty object, and `bun install --frozen-lockfile` succeeds.
- Coverage for `src/node/md2x.js` is reported in the task report and is no lower than before. Every branch named in R12 is covered.
- Manual: `bun -e "const {md2x}=require('./src/node/index.js'); console.log(md2x({markdown:'  # Hi\n', format:'html', outputPath:'/tmp/o'}))"` prints `/tmp/o/output.html`, and the file exists.
- Each regression case (the `['-']` hang, staging, typo) fails on the pre-task code and passes after it. Your report states that this was checked.

## Assumptions

- Phase 1 is complete: byte-exact stdin, the exit codes, and a minimal Node title fix. Task 003 is complete: `-o` exists.
- Bun's `mock.module` can mock `node:child_process`. If it cannot, inject the exec functions through a small internal seam that is not exported publicly.

## References

- [Design decisions: Node wrapper](../notes/design-decisions.md#node-wrapper).
- [Design decisions: title handling](../notes/design-decisions.md#title-handling): Node sink.
- [Design decisions: exit-code contract](../notes/design-decisions.md#exit-code-contract).
- [Audit coverage](../notes/audit-coverage.md): rows S2, S11, R2, R9, and R12.
- `<project_root>/.flow/audit-interface.md` S11 and `<project_root>/.flow/audit-release.md` item 12: detailed findings.
- `src/node/md2x.js`, `src/node/index.js`, and `src/node/md2x.test.js`.

## Checkpoint hints

- After the synchronous `md2x()` rewrite with validation and the shelljs removal.
- After `md2xAsync()`.
- After the test rewrite and the coverage check.

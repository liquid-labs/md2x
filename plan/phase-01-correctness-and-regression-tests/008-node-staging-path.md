# Node Staging Path

## Purpose and scope

Apply the Phase 1 minimal fix for the Node sink of S7 and for R2. Today `md2x({ markdown, title })` stages the Markdown at `<tmp>/md2x/<Math.random digits>/${title}.md`, so a title such as `../esc` builds a path outside the staging directory. This task stages under an `fs.mkdtempSync` directory with the fixed file name `input.md`. No standard skill covers this; follow the role doc and the requirements below.

In scope: `src/node/md2x.js` and `src/node/md2x.test.js`.

Out of scope:

- Replacing `shelljs`, feeding `markdown` over stdin, option validation, and every other Node wrapper change. Phase 2 rewrites the wrapper and removes staging entirely.
- CLI-side title validation (task 007).

## Requirements

- `role_doc: plugins/flow/roles/developer-node.md`
- Create the staging directory with `fs.mkdtempSync(path.join(os.tmpdir(), 'md2x-'))`. This replaces `shell.tempdir()` plus `Math.random()` plus `shell.mkdir`.
- Write the Markdown to `path.join(stagingDir, 'input.md')`. The file name is never derived from `title`. Either `fs.writeFileSync` or the existing `ShellString(...).to(...)` is fine.
- Keep everything else unchanged:
  - Still pass `--title` (default `Report`) to the CLI, so the output file name stays the same.
  - Keep cleanup in a `finally` block. `fs.rmSync(stagingDir, { recursive: true, force: true })` or `shell.rm('-r', …)` are both fine.
  - Keep the `shellQuote` escaping of the appended staging path.
  - Keep the returned value and the error behavior.
- Update `src/node/md2x.test.js`'s "markdown staging path" tests to the new mechanism. Mock or spy on `fs.mkdtempSync` (and `fs.writeFileSync`/`fs.rmSync` if used), the way the file already spies on `fs.existsSync`.
- **Regression tests.** Each must fail on the pre-change code.
  - With `title: '../esc'`, the staging file path passed to the CLI is `<mkdtemp dir>/input.md`, and no path component is derived from the title.
  - With `title: "O'Brien"`, the staging file is still `input.md`, and the command carries `--title 'O'\''Brien'` with its escaping intact.
  - `Math.random` is not used: `grep` the source, or spy on it in a test.
- Use `node:os` and `node:path` imports, consistent with the file's existing `node:` style.

## Validation

- `make test-node` passes. `make qa` passes; this task does not touch the CLI, but run the whole gate.
- `grep -n "Math.random\|\${title}.md" src/node/md2x.js` returns nothing.
- The new tests fail against the pre-change `md2x.js` and pass after the change. Confirm this and report it.
- `bun test` coverage for `src/node/md2x.js` does not drop.

## Assumptions

- This task has no dependency on any other Phase 1 task. It can run in parallel with tasks 001 to 007, because it touches only `src/node/**`.
- `title` can still affect the output file name through the CLI. Task 007 makes the CLI reject a title that is unusable as a file name.

## References

- [Design decisions: title handling, Node sink](../notes/design-decisions.md#title-handling): the Phase 1 minimal fix and the Phase 2 replacement.
- [Audit coverage](../notes/audit-coverage.md): rows S7, S11 (P1 staging), and R2 (P1 minimal).
- `src/node/md2x.js` around line 89: the current staging code.

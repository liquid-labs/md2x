# Close Shell Injection Risk In md2x.js Command Building

## Purpose and scope

Closes followup `arUf`. `src/node/md2x.js` builds a shell command string by naively single-quoting caller-supplied values — `sourceSpec` (line ~25), `title` via `--title '${title}'` (line ~46), `outputPath` via `--output-path '${outputPath}'` (line ~52) — with no escaping of embedded single quotes, then runs the result through `shell.exec(command, { shell: '/bin/bash' })` (lines ~59, ~69). Any of `title`/`outputPath`/`sources` containing a single quote breaks out of the quoting; a crafted value can execute arbitrary shell commands with the Node process's privileges. `md2x()` is the exported library API (`@liquid-labs/md2x`), and `docs/md2x-spec.md` documents `title`/`outputPath`/`sources` as plain caller-supplied strings, so externally-influenced input reaching this path is plausible for any consuming application that embeds md2x against untrusted data.

**Chosen fix approach: escape embedded single quotes**, rather than switching to an argv-array `child_process.execFile` invocation. Rationale: the escaping fix is minimal, well-understood (the standard POSIX shell single-quote escape, `'` → `'\''`), and preserves `md2x.js`'s existing command-string architecture and the existing test suite's structure (most of it needs no changes — see Requirements). Switching to `execFile` would require reworking how the markdown-staging path invokes the command (currently `command + ' ' + stagingFile}`), how `shell.exec`'s return shape (`code`/`stderr`/`toString()`) is consumed, and essentially every existing test's mocking — a much larger, riskier change for the same security outcome. If, during implementation, you find the escaping approach cannot fully close the injection for some case not anticipated here, you may fall back to the `execFile` approach instead — but treat that as an exception requiring justification in your task report, not the default path.

## Requirements

- Add a small single-quote-escaping helper in `src/node/md2x.js`, e.g.:
  ```javascript
  const shellQuote = (value) => `'${String(value).replace(/'/g, "'\\''")}'`
  ```
  (the standard idiom: close the quote, emit an escaped literal quote, reopen the quote).
- Apply it everywhere a caller-supplied string is currently wrapped in raw `'...'` interpolation:
  - `sourceSpec` (line ~25): each entry of `sources` must be individually escaped, not just joined and wrapped once — a single quote in one source entry must not be able to affect the quoting of adjacent entries.
  - `title` (line ~46, `--title '${title}'`).
  - `outputPath` (line ~52, `--output-path '${outputPath}'`).
  - Also check the markdown-staging path (lines ~64-71): `stagingFile` is built from `fsPath.join(...)` using `title` and a random staging-dir segment, then appended to the command as `command + ' ' + stagingFile`, unquoted. If `title` can contain a single quote or other shell metacharacter, this unquoted path segment is also part of the injection surface — quote/escape it too (it's a path this code controls the containing directory of, but `title` — hence the trailing filename component — is still caller-supplied).
- Update `src/node/md2x.test.js`:
  - The existing benign-value tests (`'My Report'`, `'./out dir'`, `'a.md'`/`'b.md'`/`'c dir/d.md'`, the lone `'-'` source, the markdown-staging tests) contain no embedded single quotes, so your escaping helper should produce byte-identical output for them — these tests should need **no** assertion changes (only if their surrounding descriptive comments explicitly frame the current behavior as the vulnerability should they need a wording update; check the file's `// Manual factory mock...` header comment and any per-test comments for stale "current buggy/unsafe behavior" framing, distinct from followups `udVi`/`egcc`'s explicit "documents CURRENT buggy behavior" tests which are unrelated to this task and must not be touched).
  - Add new test case(s) proving the injection is closed: at minimum, one case with an embedded single quote in `title` (e.g. `title: "O'Brien's Report"`) and one with an embedded single quote in a `sources` entry, asserting the resulting command string is safely escaped (e.g. contains `'\''` at the right position) and that, conceptually, the value cannot break out of its quoted span. Also add a case for `outputPath` if not already covered by the same pattern.
  - If you touch the markdown-staging path's quoting per the requirement above, add a case with a single-quote-bearing `title` on that path too (verifying the staging filename argument appended to the command is safely escaped).
- Do not change `md2x()`'s public signature, return value, or error-handling behavior — this is strictly an internal command-construction fix.

## Validation

- `make test` passes, with `src/node/md2x.test.js` green and 100% node coverage maintained (per `AGENTS.md`/`make test-node`'s coverage report) — this task's new tests should keep coverage complete, not just pass.
- Manually trace (or write a throwaway local script, not committed) a case like `title: "'; touch /tmp/pwned; '"` through the fixed code and confirm the resulting command string keeps that value safely inside a single quoted span rather than terminating it.
- `grep -n "shellQuote\|replace(/'/g" src/node/md2x.js` shows the escaping helper is defined and used at every site listed in Requirements.
- `grep -rn "arUf" plan/followups.yaml` — confirm the id no longer appears after this task's report is applied (report the resolved id; removal is the manager's step via `followups_remove`).

## References

- `src/node/md2x.js` — the file to modify (lines ~25, ~46, ~52, ~59-71 are the relevant sites; exact line numbers may drift after your edits).
- `src/node/md2x.test.js` lines ~74-88 — the tests the followup calls out as needing updated framing/coverage.
- `docs/md2x-spec.md`'s Node library section — documents `title`/`outputPath`/`sources` as plain caller-supplied strings; no doc change is required by this task, but it's useful context for why externally-influenced input is plausible.
- `plan/followups.yaml` item `arUf` — full original followup text.

## Status

- **Outcome:** succeeded
- **Date:** 2026-07-30
- **Summary:** Added a `shellQuote` helper (`src/node/md2x.js`) implementing the standard POSIX single-quote escape (`'` → `'\''`) and applied it at every site that interpolates a caller-supplied value into the shell command string: each `sources` entry (individually escaped before space-joining, not joined-then-wrapped-once), `title` (`--title`), `outputPath` (`--output-path`), and the previously-unquoted staging-file path appended on the markdown-string code path. No change to `md2x()`'s public signature, return value, or error handling.
- **Tests:** `src/node/md2x.test.js` updated — three new cases proving injection is closed (embedded `'` in `title`, in `outputPath`, and in one `sources` entry without affecting adjacent entries) plus one new case for the markdown-staging path with a quote-bearing `title`. The one existing markdown-staging assertion that checked the raw (previously unquoted) staging-file path was updated to expect the now-quoted form; all other existing benign-value assertions (`'My Report'`, `'./out dir'`, `'a.md'`/`'b.md'`/`'c dir/d.md'`, the lone `'-'` source) needed no changes since `shellQuote` produces byte-identical output to the prior raw quoting for values with no embedded single quote. One stale test comment describing the old unescaped `sourceSpec` construction was updated for accuracy (same-diff self-fix, file already in the task's diff).
- **Validation:** `make test` passes in full (66 bats CLI cases + 21 Jest node tests), with `src/node/md2x.test.js` green and 100% statement/branch/function/line coverage on `md2x.js` maintained. `make lint` clean. Manual trace performed via a throwaway (not committed) script in `/private/tmp/.../scratchpad/trace.js`: `title: "'; touch /tmp/pwned; '"` run through `shellQuote` and the resulting command executed via `bash -c` with `npx md2x` swapped for a `printf` argv-probe confirmed the entire payload stays inside a single argv element (`['; touch /tmp/pwned; ']`) rather than terminating the quote and running as a separate command; no `/tmp/pwned` file was created.
- **Resolved followup:** `arUf` — reported for the manager to remove from `plan/followups.yaml` via `followups_remove`; not removed by this task agent.
- **Files touched:** `src/node/md2x.js`, `src/node/md2x.test.js`.

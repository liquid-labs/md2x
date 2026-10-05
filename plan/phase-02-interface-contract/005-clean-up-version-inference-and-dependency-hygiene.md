# Clean Up Version Inference and Dependency Hygiene

## Purpose and scope

Finish the CLI's stderr and dependency hygiene:

- version inference that runs lazily, only with `--infer-version`, resolves against the first input's repository, and prints the version unquoted
- `git` and `jq` as conditional dependencies
- a pandoc minimum-version preflight
- no raw `type`/`basename`/`dirname`/`mkdir`/`cat` error leaks
- removal of dead code and the `INTERMEDIDATE` typo

This is a standard implementation task; no dedicated skill applies.

Covers S3, the remaining S8 leak sites, N5, and N9.

The last link in Phase 2's serial chain on `src/cli/md2x.sh` and `src/cli/lib/generate-page.sh`. It depends on `004-resolve-links-and-images-with-lua-filter`, whose recorded pandoc feature requirements set the floor.

Out of scope:

- the Node "Could not covert" typo, fixed in `007-rewrite-node-wrapper-on-child-process`
- documenting the final dependency set in README and spec (Phase 3)

## Requirements

1. **Version inference (S3).** Follow [Version inference and footer](../notes/design-decisions.md#version-inference-and-footer):
   - Compute the version only when `--infer-version` is given. Without it, `git`, `jq`, and `package.json` are never touched, and nothing like `cat: package.json: No such file or directory` reaches stderr.
   - Resolve the repository from the first input's directory, or the cwd for stdin. Use `git -C <dir> rev-parse --show-toplevel`, then `<toplevel>/package.json`, read with `jq -r '.version'`.
   - The footer reads `Version: 2.3.4`, unquoted, or `Version: working` when `git status --porcelain` for that repository is non-empty.
   - Not in a git work tree, no `package.json`, or a `package.json` with no `version`: print one `md2x: warning: …` line to stderr, omit the version from the footer, and continue.
   - The version string goes through Phase 1's PostScript escaping, as `--title` does.
2. **Conditional dependencies.**
   - Remove `jq` from the always-required preflight list.
   - With `--infer-version`, check `git` and `jq` lazily with quiet `command -v`. A missing one exits 3 with an md2x message that names it and says it is needed only for `--infer-version`.
   - Confirm `perl` is in no preflight list.
3. **Pandoc floor (N9).**
   - The preflight reads `pandoc --version` and exits 3 if pandoc is below the floor: `md2x: pandoc <found> is too old; md2x requires pandoc >= <floor>`.
   - Choose the floor as the highest minimum among the features md2x uses: the Lua filter's recorded requirements from task 004, `-M`, `--include-in-header`, the `gfm` reader and writer behavior md2x relies on, and the JSON `--log`. Verify each against the pandoc changelog or manual.
   - Record the floor and its justification in a code comment, and state both in your report for Phase 3's docs.
   - Compare versions numerically in bash 3.2-safe code. Do not rely on `sort -V`, which is not portable to every BSD `sort`.
   - An unparseable `pandoc --version` exits 3 with an md2x message.
4. **Leak sites (S8 remainder).** Follow [Error output](../notes/design-decisions.md#error-output):
   - Preflight uses quiet `command -v`, never raw `type` output.
   - Every remaining `basename`/`dirname` call uses `--` or parameter expansion, so a path starting with `-` works.
   - Audit every remaining external command whose failure could print a raw tool error, such as `mkdir`, `mv`, `cat`, `rm`, `mktemp`, and `find`. Each failure that is reachable by a user is either pre-checked or reported through the md2x error helper with the right exit code.
   - List the audited sites in your report.
5. **Dead code (N5).**
   - Remove the commented gucci/`require-answer`/`import prompt` template block at the top of `src/cli/md2x.sh` and any other dead or commented-out code paths, such as the `# mv "${COMBINED_FILE}" …` line.
   - Rename `INTERMEDIDATE_FORMAT` to `INTERMEDIATE_FORMAT` everywhere.
   - Remove any now-unused bash-toolkit `import` lines.
   - Drop the `# opendocument` comment in `src/cli/lib/parameters.sh`, or turn it into an accurate one.
6. **Help text.** Update the `--infer-version` row to say the version comes from the first input's repository and that `git` and `jq` are needed only for this flag.
7. **Tests.** Add bats cases. Put the stub-based ones in `exit-codes.bats` or a new `version-inference.bats`, and gate the real-toolchain ones. Cover:
   - with no `--infer-version` and a cwd with no `package.json` or git repo, stderr has no `cat:`/`jq` noise
   - `jq` absent from `PATH` without `--infer-version` → success
   - `jq` absent with `--infer-version` → exit 3 naming `jq`; `git` absent → exit 3 naming `git`
   - `--infer-version` on an input in a clean temp git repo whose `package.json` has version `2.3.4` → the gs stub receives `Version: 2.3.4` with no quotes; a dirty tree → `working`
   - an input outside any repo → one warning and success
   - the input's repository is used, not the cwd's: run from a different repo
   - a stub pandoc reporting a version below the floor → exit 3; at the floor → passes
   - the stub's default `pandoc --version` output must be at or above the floor, so the rest of the suite is unaffected
   - absent `pandoc` → exit 3 with no raw `type` text

## Validation

- `make qa` passes, and the bats suite also passes under the Phase 1 bash 3.2 interpreter override where `/bin/bash` is 3.x.
- The S3 and N9 regression cases fail on the pre-task code and pass after it. Your report states that this was checked.
- `grep -rn 'INTERMEDIDATE\|gucci\|require-answer' src/cli` finds nothing.
- `grep -rn '\btype ' src/cli/md2x.sh src/cli/lib/*.sh` finds no preflight use of `type`.
- Real toolchain: `bin/md2x --infer-version -p /tmp/o README.md` from the project root gives a PDF whose footer shows the version without quotes. Check with `pdftotext` if available, or by visual inspection.

## Assumptions

- Tasks 001 to 004 are complete, and task 004 recorded its pandoc feature requirements in a code comment.
- Phase 1's error helper, exit code 3 for dependencies, and PostScript escaping are in place.

## References

- [Design decisions: version inference and footer](../notes/design-decisions.md#version-inference-and-footer).
- [Design decisions: dependency set and version floor](../notes/design-decisions.md#dependency-set-and-version-floor).
- [Design decisions: error output](../notes/design-decisions.md#error-output).
- [Audit coverage](../notes/audit-coverage.md): rows S3, S8, N5, and N9.
- `src/cli/md2x.sh`: preflight, `VERSION=` assignment, header comments.
- `src/cli/lib/generate-page.sh`: the footer string; `src/cli/lib/parameters.sh`.
- `src/cli/test/stubs/pandoc`: needs a configurable `--version` response.

## Checkpoint hints

- After lazy version inference and conditional `git`/`jq`.
- After the pandoc floor preflight.
- After the leak-site audit and dead-code removal.
- After the bats cases.

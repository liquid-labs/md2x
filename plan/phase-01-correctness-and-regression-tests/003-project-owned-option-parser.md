# Project-Owned Option Parser

## Purpose and scope

Replace the bash-toolkit `setSimpleOptions` parser with a project-owned option-parser module. This fixes B5 (the wrong `-s` and the hidden auto-shorts) and S9 (`brew` as a hard runtime requirement, and `--help` breaking without it). It also removes the toolkit parser's undeclared `perl` dependency, and adds friendly getopt errors with a usage hint (N2, part of S8). No standard skill covers this; follow the role doc and the requirements below.

In scope:

- a new parser module under `src/cli/lib/`
- the option-parsing block and imports in `src/cli/md2x.sh`
- harness passthrough changes in `src/cli/test/helpers/common.bash`
- new and updated bats cases

Out of scope:

- `-o/--output` and `--version`. Their table rows are added by the Phase 2 tasks that implement them. Do not register them here as unimplemented options.
- `-p` trailing-slash normalization (Phase 2).
- Help-text additions: exit codes, homepage, and `--keep-intermediate` parity (Phase 2).
- README and spec documentation of abbreviations (Phase 3).
- The `perl` link converter in `generate-page.sh`. Phase 2's Lua filter removes it, so `perl` stays a runtime dependency until then.

## Requirements

- `role_doc: plugins/flow/roles/developer-bash.md`
- **Module.** Add `src/cli/lib/parse-options.sh`, or a similar name that does not collide with the toolkit's `options` import, and source it from `src/cli/lib/index.sh`.
  - Remove `import options` and any remaining toolkit `echoerr` import from `src/cli/md2x.sh`. `import lists` may stay; it has no transitive imports.
  - After this task, `bin/md2x` contains no `brew --prefix`, no `tput`, no `setSimpleOptions`, and no `echofmt`.
- **Explicit flag table.** Define every option in one table: a single line-oriented data block or array, one row per option, giving the short form (or none), the long form, whether it takes an argument, and the variable it sets.
  - Nothing derives a short flag from a variable name.
  - Keep the table in a form a later test can read by parsing the source file. Phase 3's flag-table drift test compares it with `--help` and the README.
  - The Phase 1 table is exactly:
    - **With a short:** `-D --flatten-dirs`, `-F --output-format <format>`, `-h --help`, `-p --output-path <path>`, `-s --to-stdout`, `-t --title <title>`.
    - **Long only:** `--infer-title`, `--infer-version`, `--keep-intermediate`, `--list-files`, `--no-toc`, `--quiet`, `--single-page`, `--toc`.
    - Phase 2 adds `-o --output` and the long-only `--version` to this same table.
- **Variable compatibility.** Set the same globals the rest of `md2x.sh` reads today: `FLATTEN_DIRS`, `INFER_TITLE`, `INFER_VERSION`, `KEEP_INTERMEDIATE`, `OUTPUT_PATH`, `OUTPUT_FORMAT`, `TITLE`, `SINGLE_PAGE`, `QUIET`, `LIST_FILES`, `TO_STDOUT`, `TOC`, `NO_TOC`, `HELP`.
  - Each defaults to empty, and a flag sets it to `true`.
  - Keep the `<VAR>_SET` marker for value-taking options. `TITLE_SET` is load-bearing in the `--title` precedence gate.
  - Leave positional arguments in `"$@"` for the existing input-processing code.
- **GNU getopt resolution, without `brew`.** Probe in this order and accept the first candidate for which `<candidate> --test` exits 4:
  1. `MD2X_GETOPT`, the explicit override.
  2. `/opt/homebrew/opt/gnu-getopt/bin/getopt`
  3. `/usr/local/opt/gnu-getopt/bin/getopt`
  4. `/opt/local/bin/getopt` (MacPorts)
  5. `getopt` on `PATH`, found with `command -v`, never `which`.
  6. As a last resort, and only when `command -v brew` succeeds: `"$(brew --prefix gnu-getopt)/bin/getopt"`.

  Two more rules apply to the probe:

  - If `MD2X_GETOPT` is set but is not GNU getopt, that is a dependency error: exit 3, naming the variable. It does not fall through to other candidates. This is a planner decision, and it gives tests a deterministic no-getopt path.
  - If nothing qualifies, exit 3 with a message that names GNU getopt and gives install hints: `brew install gnu-getopt`, `port install getopt`, and util-linux on Linux.
- **Help works without getopt.** `md2x -h` and `md2x --help` exit 0 and print help when no GNU getopt is resolvable, and when `brew` is absent.
  - When getopt is resolvable, getopt's parse is authoritative. `md2x --title -h x.md` must take `-h` as the title value, not as a help request.
  - A pre-getopt scan for help is acceptable only if it preserves that behavior. One way is to resolve getopt first and fall back to a help-only argv scan when no getopt is found.
- **Friendly errors.** Capture getopt's stderr. Re-word unknown-option, missing-argument, and ambiguous-abbreviation errors as single `md2x: ` lines, for example `md2x: unrecognized option '--foo'`.
  - Then print the usage hint, through task 001's usage-error helper.
  - Exit 2.
  - No raw `getopt:` line may reach stderr.
- **Keep GNU semantics** (user decision 6):
  - unambiguous long-option prefixes (`--single` means `--single-page`; `--no` means `--no-toc`)
  - `--opt=value`
  - the attached short value (`-p=x` sets `OUTPUT_PATH` to `=x`)
  - permuted options after positional arguments, as today
  - `--` ending option parsing
- **No `perl`, no `eval` of generated case handlers.** The new module uses neither. A single `eval set -- "$(getopt …)"` on getopt's quoted output is the standard idiom and is acceptable.
- **Harness.** Remove `brew` from `MD2X_TEST_PASSTHROUGH_TOOLS` in `src/cli/test/helpers/common.bash`, and update its comment.
  - Keep `perl`: the link converter still needs it.
  - The CLI must find GNU getopt through the probe paths without `brew`. On Linux, util-linux `getopt` is on the system `PATH`.
- **Regression tests.** In a new `src/cli/test/bats/options.bats`, or similar, add these cases. Each must fail on the pre-change code where the old behavior differs.
  - `-s` writes to stdout and does not enter single-page mode. Today it creates `output.<fmt>`.
  - Each of `-D`, `-F`, `-p`, `-t`, `-h` maps to its long option.
  - `-q`, `-l`, `-n`, and `-i` are each rejected with exit 2, a `md2x: ` message, and the usage hint.
  - An unknown long option and a missing option argument exit 2 with the hint, and no `getopt:` text appears in stderr.
  - `--help` exits 0 with `brew` absent from `PATH`.
  - `--help` exits 0 with `MD2X_GETOPT` pointing at a non-GNU or nonexistent getopt.
  - A conversion with `MD2X_GETOPT` pointing at a non-GNU or nonexistent getopt exits 3 and names gnu-getopt.
  - Abbreviation behavior: `--single` works; `--no` resolves to `--no-toc`; `-p=x` sets the value `=x`; an ambiguous prefix such as `--t` exits 2.
  - `--title -h x.md` uses `-h` as the title.
- Keep all code bash 3.2-compatible. Run the suite under task 002's `MD2X_TEST_BASH=/bin/bash` override.

## Validation

- `make qa` passes, and the bats suite also passes under `MD2X_TEST_BASH=/bin/bash`.
- `grep -c "brew --prefix\|tput \|setSimpleOptions\|echofmt" bin/md2x` prints `0`.
- The only `perl` occurrence left in `bin/md2x` is the link converter.
- With `PATH=/usr/bin:/bin`, `bin/md2x --help` exits 0 on this host. There is no `brew` there, and `/usr/bin/getopt` is BSD.
- The new regression cases fail against the pre-change build where the old behavior differs (`-s`, `-q`/`-l`/`-n`/`-i`, help without `brew`, friendly errors). Confirm this and report it.
- The report includes the final flag table and lists each getopt candidate probed on this host, with its `--test` result.

## Metadata

architectural_impact: true

## Assumptions

- Tasks 001 and 002 are complete: the error helper, the exit codes, and the 3.2 override exist.
- GNU getopt is installed on this host at `/opt/homebrew/opt/gnu-getopt/bin/getopt`, and `/usr/bin/getopt` is BSD (`--test` exits 0, not 4).
- Adding `--output` in Phase 2 will make `--out` ambiguous. This is accepted, and is not this task's concern.

## References

- [Brew and getopt resolution](../notes/brew-and-getopt-resolution.md): the verified current behavior, and the probe order this task implements.
- [Design decisions: short flags](../notes/design-decisions.md#short-flags) and [option parsing](../notes/design-decisions.md#option-parsing-and-gnu-getopt).
- [Short-flag answer](../notes/short-flag-set-answer.md): the user's binding acceptance of `-D -F -h -o -p -s -t`.
- [Flag table single source](../notes/design-decisions.md#flag-table-single-source): why the table must be machine-readable.
- `node_modules/@liquid-labs/bash-toolkit/dist/cli/options.func.sh`: the parser being replaced, including its `_SET` convention.
- `.flow/audit-interface.md` B5, S9, and N2, under the project root.

## Checkpoint hints

- After the parser module and getopt probe exist, with the old call still in place.
- After `md2x.sh` is switched over and the toolkit imports are removed.
- After the harness change and `options.bats`.

## Status

- Outcome: succeeded (2026-10-04).
- Validation: `make qa` passes; the full bats suite (185 cases) passes under `MD2X_TEST_BASH=/bin/bash`; `PATH=/usr/bin:/bin bin/md2x --help` exits 0; the only non-comment `perl` in `bin/md2x` is the link converter.
- New: `src/cli/lib/parse-options.sh` (flag table `MD2X_OPTION_TABLE`, rows `short|long|flag|value|VARIABLE`, `-` for no short); `src/cli/test/bats/options.bats` (26 cases). Changed: `src/cli/md2x.sh`, `src/cli/lib/index.sh`, `src/cli/test/helpers/common.bash` (`brew` removed from passthrough), `README.md` and `AGENTS.md` (stale brew statements).
- Note: the literal `grep -c "tput "` also matches the word "output " in pdftk/pandoc comments and code, so it cannot print 0; a `\btput ` check does print no matches.

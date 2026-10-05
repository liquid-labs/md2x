# Brew and GNU Getopt Resolution

## Purpose and scope

Records the verified current behavior of md2x's dependency on Homebrew (`brew`) and GNU `getopt` on macOS, which the user asked to have checked and documented precisely, and the post-plan behavior this plan targets.

## Finding (verified 2026-10-04 against the code and a live macOS host)

The user's belief was that `brew` is optional, an install-if-missing helper. **It is not.** Today `brew` is a hard runtime requirement on macOS, for every invocation, including `--help`. md2x never installs anything through `brew`.

- md2x does not call `brew` directly. The call comes from the bash-toolkit option parser that `bash-rollup` inlines into `bin/md2x` (`import options` in `src/cli/md2x.sh`, sourced from `node_modules/@liquid-labs/bash-toolkit/dist/cli/options.func.sh`). That file runs this at top level, at script load time:

  ```bash
  if [[ $(uname) == 'Darwin' ]]; then
    GNU_GETOPT="$(brew --prefix gnu-getopt)/bin/getopt"
  else
    GNU_GETOPT="$(which getopt)"
  fi
  ```

- The code runs before md2x handles `--help`. With no `brew` on `PATH`, the failing command substitution trips `errexit`, so `md2x --help` dies with `brew: command not found` (rc 127). This also breaks the spec's promise that `--help` runs without preflight.
- `brew --prefix <formula>` prints the would-be `opt` path and exits 0 **even when that formula is not installed**. This was checked live: `brew --prefix tree` printed `/opt/homebrew/opt/tree` while `tree` was not installed. So when `brew` is present but `gnu-getopt` is missing, `GNU_GETOPT` points at a nonexistent file. The first real use then fails with a raw "No such file or directory" error, and no message names `gnu-getopt`.
- Each run also pays the `brew --prefix` startup cost, roughly 100 ms or more.
- On Linux the parser uses `which getopt`, which assumes util-linux. BusyBox `getopt` lacks long options and is untested. `which` may not exist in minimal images.
- The same toolkit parser shells out to `perl` (`perl -pe 's/\]$/)/'` while building its case handler). That makes `perl` an undeclared dependency on every invocation, in addition to the `perl` link converter in `src/cli/lib/generate-page.sh`.
- The bats harness (`src/cli/test/helpers/common.bash`, `MD2X_TEST_PASSTHROUGH_TOOLS='bash brew git jq perl'`) passes `brew` through for this reason.

## Plan decision

Phase 1 replaces the toolkit's `setSimpleOptions` with a project-owned option parser module. That module:

1. Still uses GNU `getopt`. This keeps the GNU unambiguous-prefix abbreviation behavior the user chose to keep (user decision 6).
2. Resolves GNU getopt without requiring `brew`. It probes, in order:
   - an explicit override (`MD2X_GETOPT`, optional, documented)
   - `/opt/homebrew/opt/gnu-getopt/bin/getopt`
   - `/usr/local/opt/gnu-getopt/bin/getopt`
   - `/opt/local/bin/getopt` (MacPorts)
   - `getopt` on `PATH`

   Each candidate is accepted only if `getopt --test` exits `4`, which is GNU-enhanced getopt. `brew --prefix gnu-getopt` is consulted only as a last resort, and only when `brew` is actually on `PATH`.
3. Handles `-h`/`--help` before resolving getopt at all, so help always works.
4. Fails with a clear dependency error when no GNU getopt is found: exit code per the contract in [design decisions](./design-decisions.md#exit-code-contract), with install hints (`brew install gnu-getopt`, `port install getopt`, util-linux).
5. No longer uses `perl`.

**Post-plan dependency statement for macOS:** GNU getopt is required. Homebrew is the usual way to install it but is **optional** at runtime. md2x never invokes `brew` to install anything.

The Phase 3 documentation work states this precisely in README, spec, and `--help`, alongside the rest of the final dependency set.

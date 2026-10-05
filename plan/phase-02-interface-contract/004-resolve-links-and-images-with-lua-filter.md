# Resolve Links and Images With Lua Filter

## Purpose and scope

Replace the eval-built `perl` `LINK_CONVERTER` in `src/cli/lib/generate-page.sh` with a Pandoc Lua filter that does two things:

- rewrites relative Markdown links to the output format
- resolves images against the directory of the source file that contains them, including in `--single-page` mode

Missing local images produce one md2x warning each instead of failing silently. This is a standard implementation task; no dedicated skill applies.

Covers user decision 4, S5, S6, and R7. It also removes `perl` and `eval` from the CLI.

The fourth link in Phase 2's serial chain on `src/cli/md2x.sh` and `src/cli/lib/generate-page.sh`. It depends on `003-add-output-option-and-collision-checks`, because HTML image paths are made relative to the final output file's directory, which that task computes. `005-clean-up-version-inference-and-dependency-hygiene` follows it and sets the pandoc version floor from the features this filter uses.

Out of scope:

- turning cross-file links in `--single-page` output into internal anchors
- renaming links to files converted with `--title` or `-o`
- fixing cross-directory links under `--flatten-dirs`

These three are documented limitations, which Phase 3 writes up.

## Requirements

Follow [Links and images](../notes/design-decisions.md#links-and-images), which records the 2026-10-04 spike results with pandoc 3.10.1.

1. **The filter file.**
   - Add `src/cli/lib/<name>.lua`, for example `md2x-links.lua`.
   - Inline it into `bin/md2x` through `bash-rollup` the same way `github.css` and `toc-preprocess.py` are inlined: a heredoc with `# bash-rollup-no-recur`.
   - Write it into the per-run work directory and pass it to pandoc with `--lua-filter`.
   - The `Makefile`'s `CLI_LIB_SRC` already globs `src/cli/lib`, so the file becomes a build prerequisite automatically. Confirm this.
2. **Links.**
   - A relative link target whose path ends in `.md` or `.markdown` gets that extension replaced with `.<format>`. Match the extension case-insensitively, consistent with discovery. Keep any `#fragment`, so `c.md#sec` becomes `c.html#sec`.
   - Leave alone absolute paths, URL-scheme targets (`http:`, `https:`, `mailto:`, and any `scheme:`), pure `#fragment` links, and links inside code spans and fences.
   - Apply the same rule to reference-style definitions. Pandoc resolves those to ordinary `Link` elements.
   - Keep the target's `./` prefix behavior sensible. Do not introduce `././`.
3. **Images.** Resolve each relative image target against the directory of the source file that contains it:
   - **Single file:** pass the source's absolute directory with `-M` (for example `-M md2x-source-dir=<abs dir>`) or an environment variable.
   - **stdin:** the base is the cwd.
   - **`--single-page`:** the concatenation step inserts, before each source's content, a line of the form `<!-- md2x:source-dir=<abs dir> -->` with blank lines around it.
     - The filter tracks the current base from these `RawBlock`s and removes them from the output.
     - You may carry the source file path instead of only the directory, for example `md2x:source=<abs path>`, so warnings can name the file.
     - The marker must stay a single HTML comment for any path. Encode the path, for example with percent-encoding, so a directory name containing `-->` or a newline cannot break it, and decode it in the filter.
     - The concatenation must also not let one source's unterminated fence or HTML swallow the next marker. If you cannot fully guard against that, document it as a limitation in your report.
   - **Rewrite by format:**
     - PDF and DOCX get an absolute path.
     - HTML gets a path relative from the output file's directory to the image, so the HTML works in place. The output directory comes from the target computed by `003`: under `-p` with mirroring, or the `-o` parent.
     - For `--to-stdout` HTML, make the path relative to the cwd. This is a planner choice; state it in your report.
   - Leave absolute, URL-scheme, and `data:` image targets alone.
4. **Missing images.**
   - Each relative image whose resolved file does not exist produces exactly one stderr line: `md2x: warning: could not find image '<original target>' (referenced from <source>)`. For stdin, `<source>` is `stdin`.
   - The run still succeeds with exit 0. A warning is not a failure.
   - The design suggests reading pandoc's JSON `--log` from the work directory. Pandoc only reports a missing resource when it actually fetches it, which happens for DOCX but not for plain `html5` output, and for PDF the fetch is WeasyPrint's. So verify per format which channel reports what, and make the observable behavior hold for all three formats. The filter already resolves every path, so it may check existence itself and record misses.
   - Parse any JSON with `python3`, which is always required. Do not use `jq`, which becomes conditional in task 005.
   - Avoid printing the same miss twice in md2x format. A residual WeasyPrint warning for the same image on PDF runs is acceptable; note it in your report.
5. **Remove `perl` and `eval`.** Delete `LINK_CONVERTER` and its `eval`. After this task, `grep -rn 'perl\|eval' src/cli` must find no executable use. Mentions in comments may remain only if accurate.
6. **Pandoc features used.** Record in a code comment next to the `--lua-filter` call the pandoc features the filter relies on, such as `pandoc.path`, the `RawBlock` handling, and any `PANDOC_VERSION` use, with the earliest pandoc version that provides each. Task 005 uses this to set the floor.
7. **Stub harness.**
   - `src/cli/test/stubs/pandoc` must accept and log `--lua-filter` and `-M`. Phase 1 may already have added `--include-in-header`.
   - Update the stub-based bats assertions that expected the perl-converted Markdown. Those are the `pandoc-args.bats` cases that inspect link rewriting, if any.
   - Remove `perl` from `MD2X_TEST_PASSTHROUGH_TOOLS` in `src/cli/test/helpers/common.bash` if Phase 1 has not already. That is the proof the CLI no longer needs it.
8. **Gated real-pandoc tests.**
   - Add `src/cli/test/bats/links-and-images.bats`. It skips when real pandoc is absent, using the same gating as `real-toolchain-e2e.bats`.
   - Cover each spike case: multiple links on one line, a link followed by text, `#fragment`s, a reference-style definition, links in code spans and fences left alone, absolute and URL links left alone, `.markdown` and `.MD` targets.
   - Cover images: an image in a subdirectory source resolved for each of pdf, html, and docx; an HTML relative path correct with `-p` mirroring and with `-o`; `--single-page` with two sources in different directories each resolving their own image; markers absent from the output; one warning per missing image naming the source; a source directory whose name contains spaces and `-->`.

## Validation

- `make qa` passes, and the bats suite also passes under the Phase 1 bash 3.2 interpreter override where `/bin/bash` is 3.x.
- `bats src/cli/test/bats/links-and-images.bats` runs and passes on this host, with real pandoc 3.10.1, and does not skip.
- The S5 and S6 regression cases fail on the pre-task code and pass after it. Your report states that this was checked.
- `grep -rnE '\bperl\b|\beval\b' src/cli --include='*.sh'` finds no executable use.
- `bin/md2x` built from scratch contains the Lua filter text. Check with `grep -c 'lua' bin/md2x` or a filter-specific marker.
- Manual: convert a doc with an image in a sibling directory to HTML under `-p out/`, open the HTML, and confirm the image renders.

## Metadata

architectural_impact: true

## Assumptions

- Tasks 001 to 003 are complete. Final output paths, including `-o` and `--to-stdout`, are computed before conversion.
- Phase 1's work directory and `--include-in-header` CSS are in place.
- The documented limitations above are accepted by the plan and are not bugs to fix here.

## References

- [Design decisions: links and images](../notes/design-decisions.md#links-and-images): rules and spike evidence.
- [Design decisions: dependency set and version floor](../notes/design-decisions.md#dependency-set-and-version-floor): `perl` leaves; the floor comes from the filter's features.
- [Audit coverage](../notes/audit-coverage.md): rows S5, S6, and R7.
- `src/cli/lib/generate-page.sh`: `LINK_CONVERTER`, the preprocessing pipeline, the pandoc invocation.
- `src/cli/md2x.sh`: the `--single-page` concatenation and the inlining heredocs.
- `src/cli/test/stubs/pandoc`, `src/cli/test/helpers/common.bash`, `src/cli/test/bats/real-toolchain-e2e.bats` (gating pattern).
- Pandoc Lua filter manual: `pandoc.path`, the `Link`/`Image`/`RawBlock` filters, and `PANDOC_VERSION`.

## Checkpoint hints

- After the Lua filter handles links and replaces `LINK_CONVERTER`, with the stub harness updated.
- After per-source image resolution, including single-page markers.
- After missing-image warnings.
- After the gated `links-and-images.bats`.

## Status

- Outcome: succeeded (2026-10-05).
- Added `src/cli/lib/md2x-links.lua` (inlined by `bash-rollup`, written to the work directory, passed with `--lua-filter`) and `src/cli/lib/link-filter.sh` (percent-encoding, source markers, missing-image reporting). `generate-page.sh` and `md2x.sh` no longer use `perl` or `eval` for links; `perl` is gone from `MD2X_TEST_PASSTHROUGH_TOOLS`.
- Missing images are detected by the filter itself (it already resolves every path), recorded in a work-directory file, and printed by the CLI as `md2x: warning: could not find image '<target>' (referenced from <source>)`, once per source and target, for all three formats. A residual WeasyPrint warning on PDF runs is possible.
- `--to-stdout` HTML image paths are relative to the cwd (planner choice).
- Known limitation: an unterminated code fence or raw HTML block in one `--single-page` source swallows the next source's marker. The remaining `eval set --` in `parse-options.sh` (getopt's quoted output, accepted in Phase 1) is the only `eval` left.
- Pandoc features used (also in the code comment in `generate-page.sh`): `--lua-filter`, `Pandoc` filter function, `pandoc.utils.stringify`, block `:walk`; no `pandoc.path`, no `PANDOC_VERSION`. Only 3.10.1 was exercised.
- Validation: `make qa`, the bash 3.2 override run, and `links-and-images.bats` (17 cases, none skipped); the new cases fail on the pre-task code (checked in a pre-task checkout).

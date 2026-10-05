# Pass Sources After End-Of-Options And Correct Node Type Docs

## Purpose and scope

Fixes findings Xylz and YkUH from the Phase 2 review. The work targets the plan branch `plan/golden-release-hardening` and lands through the ordinary per-task loop. It runs after the bundle-resolution remediation task because both edit `src/node/md2x.js`.

## Requirements

1. `buildInvocation` places `--` before the source arguments, so a source like `-weird.md` is treated as a file. Confirm that the CLI parser treats `-` after `--` as stdin; if it does not, keep the markdown/stdin path working another way, for example by prefixing dash-leading relative sources with `./`.
2. The JSDoc for `inferTitle`, `inferVersion` and `singlePage` in `src/node/index.d.ts` matches the CLI `--help` wording: the title comes from `--title` or the filename, the version from the git repository's `package.json`, and single-page concatenates all inputs into one document.

## Validation

1. A Node test converts a source named `-weird.md` (sync and async) successfully.
2. The existing markdown-over-stdin Node tests still pass.
3. The `scripts/test-pack.sh` TypeScript check passes, and the `.d.ts` wording agrees with `md2x --help`.
4. `make qa` is green.

## References

- Finding Xylz, in this plan's `plan/findings.yaml`.
- Finding YkUH, in this plan's `plan/findings.yaml`.
- Files: `src/node/md2x.js`, `src/node/index.d.ts`, `src/node/md2x.test.js`.

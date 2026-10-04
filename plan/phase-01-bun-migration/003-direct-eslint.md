# Replace catalyst-scripts Lint with Direct ESLint

## Purpose and scope

Replace `catalyst-scripts lint` / `lint-fix` with a direct `eslint` invocation driven by a repo-owned config that preserves the custom rules catalyst-scripts shipped. Files: `package.json` (devDependencies), `eslint.config.js` (or `.eslintrc.cjs`), `Makefile` (`lint`, `lint-fix`, `qa`). Lints `src/node` only (bash sources are not linted). Depends on task 002 (the migrated test file is linted too).

## Requirements

1. Verify `bun --version`; halt if absent.
2. Source of truth for the existing rules: the catalyst config at `/Users/zane/playground/liquid-labs/md2x/node_modules/@liquid-labs/catalyst-scripts/config/eslintrc.js` (read it before it disappears; if gone, the rules are: extends `standard` + `eslint:recommended`; `brace-style` stroustrup with `allowSingleLine`; `curly` multi-line; `import/export` warn; `indent` 2 with `FunctionDeclaration {body:1, parameters:2}`; `key-spacing` singleLine strict with `beforeColon: true, afterColon: true`, multiLine `beforeColon/afterColon: true, align: colon`; `operator-linebreak` before with `=` override after; `prefer-const`, `prefer-spread`; `space-before-function-paren` never; `array-callback-return`, `guard-for-in`, `no-caller`, `no-extra-bind`, `no-multi-spaces`, `no-new-wrappers`, `no-throw-literal`, `no-unexpected-multiline`, `no-with`, `yoda` all error; `import/extensions` never except `mjs`/`json` always; parser sourceType module, env es6). Ignore the React branch (not applicable).
3. Preferred approach: ESLint 9 flat config with `neostandard` (or `eslint-config-standard` equivalents) plus `@stylistic/eslint-plugin` rules for the formatting rules above (in ESLint 9 these formatting rules live in `@stylistic`, e.g. `@stylistic/key-spacing`, `@stylistic/brace-style`, `@stylistic/indent`, `@stylistic/operator-linebreak`, `@stylistic/space-before-function-paren`). Use no Babel parser: `ecmaVersion: 'latest', sourceType: 'module'`, with a `bun:test`-compatible setup (no globals needed since tests import from `bun:test`). Fallback, only if the flat-config port cannot reproduce the rules without churn: `eslint@^8` + `eslint-config-standard` with the rules block copied verbatim into `.eslintrc.cjs` (note ESLint 8 is EOL and flag it in the report).
4. Add devDependencies via `bun add -d` (current versions) so `bun.lock` updates; do not add babel packages.
5. Makefile: `lint` runs `$(BUNX) eslint $(NODE_SRC)`; `lint-fix` runs `$(BUNX) eslint --fix $(NODE_SRC)`; no `JS_LINT_TARGET`. Keep `qa: test lint`.
6. Zero lint errors on the existing source and test files with the new config, achieved by config tuning first; edit source only for style fixes the new config genuinely requires via `make lint-fix`, and report every changed line (no behavior change; do not alter strings that tests assert on). The styled-colon alignment convention (`{ shell : '/bin/bash' }`) must continue to pass.
7. Add `dist`, `coverage`, `node_modules` to the config's ignores.

## Validation

- `make lint` exits 0; `make lint-fix` exits 0 and leaves `git diff --stat src/` unchanged on a clean tree.
- Rule-preservation check: temporarily introduce violations (a space before function paren, `if (x)\n{`, an unaligned `key:value` in a multi-line object, a leading-operator violation) in a scratch copy of the source and confirm `eslint` flags each; revert.
- `grep -rn "catalyst\|JS_LINT_TARGET" Makefile package.json eslint.config.js .eslintrc.cjs 2>/dev/null` returns nothing.
- `make qa` passes end to end.

## Status

Outcome: succeeded (2026-10-04). Direct ESLint 9 flat config in `eslint.config.mjs` (neostandard + eslint-plugin-import-x + the catalyst custom rules via `@stylistic`); `Makefile` lint/lint-fix use `$(BUNX) eslint`. Validation: `make lint` 0, `make lint-fix` leaves src unchanged, rule-preservation scratch check flagged all four violations, grep clean, `make qa` passes. No source files changed. ESLint pinned to ^9 because neostandard 0.13's bundled @stylistic crashes under ESLint 10. Config named `.mjs` to avoid the typeless-package ESM warning.

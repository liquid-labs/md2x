# Audit Coverage

## Purpose and scope

Maps every itemized finding in the three 1.0 audits, plus the folded-in followups and user decisions, to the phase that addresses it. The user made every blocker, should-fix, and nice-to-have item in scope, then deferred N4 and N8's feature parts during planning. Phase-decomposition agents must make sure each row lands in some task. The final phase's verification should walk this table.

Source audits (gitignored, per-machine, in `<project_root>/.flow/`): `audit-interface.md` (B/S/N), `audit-docs.md` (D1–D20), and `audit-release.md` (R1–R12). Phases: P1 is correctness and regression tests, P2 is the interface contract, and P3 is docs, CI, and release readiness.

Every bug fix carries a regression test (bats for the CLI, `bun test` for Node) in the task that fixes it.

## Interface audit

| ID | Finding | Phase | Notes |
| --- | --- | --- | --- |
| B1 | `--single-page -t X` deletes the user's `X.md` | P1 | Per-run work directory with a fixed concatenation name |
| B2 | stdin corrupts the document; empty stdin exits 0 | P1 | Byte-exact copy; empty input is exit 2 |
| B3 | HTML links a deleted `TMPDIR` CSS file | P1 | Inline `<style>` |
| B4 | bash 3.2 'bad substitution' exits 0 with no output | P1 | Support 3.2, sh guard, harness override |
| B5 | `-s` means single-page; hidden `-q`/`-l`/`-n`/`-i` | P1 | Explicit short table; set `-D -F -h -o -p -s -t` confirmed by user answer |
| S1 | No `--version` | P2 | Build-time injection from `package.json` |
| S2 | No args, empty dir, empty stdin, or Node `[]` all exit 0 silently | P1 (stdin), P2 (rest) | |
| S3 | Unconditional git/jq; `cat: package.json` noise; quoted version | P2 | Lazy, `jq -r`, conditional dependencies |
| S4 | Output-name collisions overwrite silently | P2 | Pre-flight duplicate-target check |
| S5 | Link rewriting only works at end of line | P2 | Lua filter |
| S6 | Images resolve against the cwd; failures are silent | P2 | Per-source base directory; surfaced warnings |
| S7 | `--title` unsanitized in four sinks | P1 | Filename, metadata, PostScript, Node |
| S8 | ANSI off-TTY, raw error leaks, exit-code scheme, Node typo | P1 (helper and codes), P2 (leak sites, typo) | Codes 0/1/2/3 confirmed by user answer |
| S9 | `brew` required; `--help` breaks without it | P1 | Project-owned parser with getopt probing |
| S10 | getopt abbreviations, `-p=x`, trailing `/` | P1 (keep and test), P2 (`-p` normalization), P3 (document) | User decision 6 |
| S11 | Node: ESM named import, types, sync only, `['-']` hang, staging, validation, stderr | P1 (staging), P2 (rest) | |
| S12 | WeasyPrint CSS warning flood | P2 | Prune `github.css` |
| S13 | `pandoc-log.log` and combined file in the cwd | P1 | Work directory |
| S14 | `--to-stdout` writes a file too; multi-output concatenation | P2 | Pure stream, one output only |
| S15 | Only lowercase `*.md`; duplicates; `-` mixing | P2 | |
| S16 | Doc/code drift: dependency list, "other formats", `-s`, `--help` preflight | P1 (`-s`, help), P2 (help text), P3 (docs) | User decision 3 |
| N1 | Case-sensitive `--output-format` | P2 | |
| N2 | No usage hint on bad usage | P1 | |
| N3 | Format error does not list the valid formats | P2 | |
| N4 | No progress output; no `--jobs` | Deferred | User answer; followup `1wy6` |
| N5 | Dead template code; `INTERMEDIDATE` typo | P2 | |
| N6 | `--keep-intermediate` does not print all paths | P1 | Prints the work directory |
| N7 | Binary or invalid-UTF-8 input accepted | P2 | |
| N8 | Header/footer limits; non-Latin titles | P1 (robustness), deferred (features) | Non-ASCII and PostScript-special titles must not crash `gs`; features deferred to followup `1wy6`; limitation documented in P3 |
| N9 | No tool version checks | P2 | pandoc floor |
| N10 | Confirm prepack rebuild | P3 | |

## Docs audit

| ID | Finding | Phase |
| --- | --- | --- |
| D1 | Spec and architecture omit `jq` (dependency count) | P3 (final dependency set) |
| D2 | Spec omits the macOS gnu-getopt requirement | P3 |
| D3 | README lacks a `-h` row | P3 |
| D4 | README TOC rows should link to the TOC section | P3 |
| D5 | Exit-code table and troubleshooting; exit codes in help | P1 (contract), P2 (help), P3 (README) |
| D6 | `--version` | P2 |
| D7 | README Node option reference | P3 |
| D8 | Quickstart sample output; first-run note | P3 |
| D9 | CHANGELOG; org casing | P3 |
| D10 | CONTRIBUTING, SECURITY, SSRF caveat in README | P3 |
| D11 | RELEASING.md fixes | P3 |
| D12 | README: npm vs bun | P3 |
| D13 | "Mardown" typo | P3 |
| D14 | `keywords` | P3 |
| D15 | `files` and LICENSE (verify the pack) | P3 |
| D16 | Help footer: homepage and exit codes | P2 |
| D17 | Help `--keep-intermediate` parity | P2 |
| D18 | README features: stdin and `--to-stdout` | P3 |
| D19 | Prerequisite one-liners; pdftk-java link | P3 |
| D20 | Single-source the flag table | P3 |

## Release audit

| ID | Finding | Phase |
| --- | --- | --- |
| R1 | No CI | P3 |
| R2 | Node `title` path traversal; `Math.random` | P1 (minimal), P2 (removed by the stdin approach) |
| R3 | `package.json` metadata | P3 |
| R4 | `exports` and types; verify a packed `require` | P2 |
| R5 | `bun publish` unverified; dry run; 1.0.0 to `latest` path | P3 |
| R6 | Platform matrix | P3 |
| R7 | eval `LINK_CONVERTER` | P2 (removed by the Lua filter) |
| R8 | Followups zwH4 and psgq | zwH4 fixed in `35c8d54` and closed; psgq in P3 |
| R9 | shelljs 0.10 | P2 (shelljs replaced) |
| R10 | `eslint .` fails; ESLint 10 | P3 |
| R11 | Push 117 commits; `git+https` | P3 (`git+https`); the push is a user action |
| R12 | Node coverage gaps | P2 |

## Out of scope, filed as followups

- epub, odt, and latex formats
- custom CSS and styling options
- a config file and env namespace
- a self-contained HTML option
- N4 and N8's feature parts (followup `1wy6`)

# Pdf Css Styling

## Purpose and scope

Fix followup `TNLq`: PDF output currently ships with **no** GitHub-markdown CSS styling. Root cause — `generate-page()` in `src/cli/lib/generate-page.sh` delivers the bundled stylesheet to Pandoc via `--css <(echo "${CSS}")`, a process-substitution path (`/dev/fd/N`) with no `.css` extension. WeasyPrint (the pinned `--pdf-engine` since the `pdf-engine-weasyprint` plan) cannot MIME-sniff a stylesheet from that path and silently drops it, only surfacing an "Unsupported stylesheet type" warning on stderr — which the current code merges onto stdout via `pandoc ... 2>&1 | grep -vE ... | ...` and then greps away. That grep only patches over the symptom (a stray warning line); it does not restore actual styling. HTML and DOCX output are unaffected — Pandoc's own `--css` handling doesn't care about file-descriptor paths the way WeasyPrint's MIME sniffing does.

This plan:

1. Replaces the process-substitution `--css` delivery with a real `mktemp`-created temp file ending in `.css`, written from the existing `$CSS` content, in both code paths of `generate-page()` (the file-input loop branch and the `$INPUT`/stdin/single-page branch) — cleaned up afterward respecting the existing `KEEP_INTERMEDIATE` convention (the same pattern already used for `pandoc-log.log` and the PDF overlay file).
2. Restructures how Pandoc/WeasyPrint's combined stderr chatter is handled. Once WeasyPrint actually loads the stylesheet, it emits roughly ten non-fatal, multi-line `WARNING` lines per PDF conversion (per followup `TNLq`'s own investigation) with no reliable machine-parseable boundary for safe `grep`-based filtering — pattern-matching around them risks either leaking noise onto stdout (breaking `--to-stdout`/`--list-files` purity) or swallowing a genuinely fatal error. Per the structural note in followup `rndR`, the fix stops merging the pdf-engine's stderr into the CLI's real stdout at all, rather than continuing to pattern-match around it.
3. Adds a visual verification step — extending the existing `make smoke-test` mechanism (`src/cli/test/manual/visual-smoke-test.sh`), per AGENTS.md — that a human reviewer uses to confirm GitHub CSS styling actually renders in real PDF output (fonts, code blocks, tables, headings). None of the `pdf-engine-weasyprint` plan's eight Validation checks caught this gap because they were all exit-code/stub-based; this plan does not repeat that mistake for its own fix.
4. Corrects the three doc locations that describe the current (broken) or soon-to-be-stale state: README.md's Features bullet (explicitly calls out followup `TNLq`), docs/architecture.md's "Bundled stylesheet" section (describes the process-substitution mechanism being replaced), and a review pass over docs/md2x-spec.md's "Consistent styling" bullet / UC1 outcome text (followup `LUhO`) — see [task 003](./phase-01-restore-pdf-styling/003-update-stale-pdf-styling-docs.md) for what was actually found there; the fix does not necessarily require an edit to that file's wording.

**Out of scope** (adjacent followups, explicitly not folded in per the manager's request): `egW0` (WeasyPrint preflight re-verification), `Kjs2` (WeasyPrint SSRF doc-only decision), `efJF`/`zjG5` (bats harness cold-install / stale e2e skip guard). This plan does not touch `plan/followups.yaml` — followup resolution is the manager's job after task reports land.

## Current status

Plan freshly created; no tasks started. Phase 1 (`restore-pdf-styling`) is the plan's only phase and begins with task 001 (`fix-css-delivery-and-stream-handling`), which tasks 002 and 003 both depend on.

## Overview

Single phase: **Phase 1 — Restore Pdf Styling** (`plan/phase-01-restore-pdf-styling/`).

- **001 — Fix Css Delivery And Stream Handling** (`sonnet-high`). The core fix: replace `--css <(echo "${CSS}")` with a real `mktemp`-created `.css` temp file in both `generate-page()` branches, respecting `KEEP_INTERMEDIATE`; remove the `2>&1 | grep -vE ...` construct so Pandoc/WeasyPrint's stderr never merges onto the CLI's real stdout, while a genuine fatal failure still propagates as a non-zero exit under `set -o errexit`/`pipefail`. Adds automated `bats` coverage (extending the `pandoc` test stub with controllable stderr/exit-code injection) proving stdout purity, real-failure propagation, and `.css`-suffixed delivery. No dependency on any other task — this is the critical path.
- **002 — Extend Visual Smoke Test For Css** (`sonnet-med`). Depends on 001. Extends `src/cli/test/manual/visual-smoke-test.sh` (the `make smoke-test` target) with an explicit reviewer checklist confirming GitHub CSS styling actually renders (fonts, code blocks, tables, headings) in real PDF output, and enriches the shared `tiny-doc.md` fixture with the markdown elements needed to exercise that styling.
- **003 — Update Stale Pdf Styling Docs** (`sonnet-med`). Depends on 001. Updates README.md and docs/architecture.md to describe the fixed behavior and new CSS-delivery mechanism, and reviews docs/md2x-spec.md's styling claims for continued accuracy now that the bug is fixed.

**Parallel-eligible:** tasks 002 and 003 can run concurrently once 001 lands; neither depends on the other.

**Critical path:** 001 → (002 and 003 in parallel).

No architectural-implications `doc-updates` phase is added: this fix restores previously-documented (spec-stated) behavior rather than changing spec-defined behavior, introduces no new subsystem, and touches no public API boundary or tracked state. Task 003 already covers the doc corrections the manager's request called for directly.

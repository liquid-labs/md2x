# Update Stale Pdf Styling Docs

## Purpose and scope

Now that `phase-01-restore-pdf-styling/001-fix-css-delivery-and-stream-handling.md` has restored real GitHub CSS styling to PDF output, correct the project docs that describe the old (broken) mechanism or the old (broken) behavior. Depends on task 001 landing first — the doc text this task writes must describe the actual, now-true behavior, not an aspiration.

Scope is three files: `README.md`, `docs/architecture.md`, and a review pass over `docs/md2x-spec.md`. Apply the Flow plugin's Markdown style standards (`markdown-style-standards.md` — non-functional style conventions: sentence-case section headings, language-tagged code blocks, and so on) where relevant to any prose you touch, matching the existing conventions already used in these three files (do not introduce a new style).

## Requirements

### 1. `README.md` — Features bullet (definite edit)

The "Features" list (around line 62) currently reads:

> Consistent GitHub-style CSS applied to every HTML page (PDF output is not currently styled — see followup `TNLq`).

This is the one doc location that accurately described the *bug*, and it needs to change now that the bug is fixed. Update it to state that PDF output is styled consistently with HTML, dropping the parenthetical caveat and the `TNLq` followup reference (the followup itself is resolved by this plan's implementation, not by this doc edit — do not edit `plan/followups.yaml`; followup resolution is the manager's job after task reports land, not a task agent's). Keep the sentence's placement and the surrounding bullet list's style consistent with the rest of the Features section.

### 2. `docs/architecture.md` — "Bundled stylesheet" section (definite edit)

The "Bundled stylesheet" section (around line 81-83, under "Major components") currently reads:

> `src/cli/lib/github.css` is embedded inline into every Pandoc invocation via process substitution (`--css <(echo "$CSS")`), so styling has no external file dependency at runtime — the CSS travels with the built CLI rather than being read from disk at conversion time.

This describes the mechanism task 001 replaced. Update it to describe the new mechanism accurately: the CSS content is still embedded into the built CLI at build time (via the `bash-rollup`-processed heredoc — this part is unchanged and still true, don't lose it), but at conversion time `generate-page()` now writes that content to a `mktemp`-created, `.css`-suffixed temporary file and passes that file's path to Pandoc's `--css`, rather than a process-substitution file descriptor — because WeasyPrint (the pinned PDF-rendering engine) needs a real path with a recognizable extension to MIME-sniff the stylesheet type. Check `src/cli/lib/generate-page.sh` as task 001 left it for the exact mechanism (temp file location, cleanup timing relative to `KEEP_INTERMEDIATE`) before writing this description, so the doc matches what actually shipped rather than what this task document anticipated.

Also check whether the "System overview" Mermaid diagram or its accompanying explanatory paragraph (both earlier in the same file) reference the CSS-delivery mechanism specifically — a quick read suggests they don't (the diagram's `Pandoc` node just says "gfm to html5 intermediate + GitHub CSS + optional TOC", which remains accurate regardless of delivery mechanism), but confirm this rather than assuming it.

### 3. `docs/md2x-spec.md` — review, edit only if still inaccurate

Followup `LUhO` flags this file's "Consistent styling" General features bullet and UC1's outcome description as both claiming PDF output gets the built-in GitHub CSS. Read both passages carefully before editing:

- The "Consistent styling" bullet (General features section): "Every HTML or PDF output is rendered with a single, built-in GitHub-flavored CSS stylesheet. There is no per-invocation styling configuration."
- UC1's outcome (Key use cases section): "...styled with the built-in GitHub-style CSS, with an automatic page footer and header."

As of this plan's investigation, both of these sentences already state that PDF gets the CSS — they do not currently claim PDF *lacks* it. That claim was **false** before task 001's fix (this is exactly what followup `LUhO` is flagging: the spec was describing an aspirational/intended behavior that the implementation didn't actually deliver) and becomes **true** once task 001 lands. If, after re-reading both passages against the current file state, they still accurately describe the now-fixed behavior with no remaining false or hedged claim, no textual edit is needed to this file for this specific issue — record that finding explicitly in your task report rather than silently skipping it, since the manager's original request characterized this file as needing a correction and a "no change needed, verified accurate" outcome should be visible, not just inferred from a lack of diff.

If your own re-read finds a genuine inaccuracy this description missed (e.g. wording elsewhere in the file that still implies PDF lacks styling, or something task 001's actual implementation changed that the spec should now reflect, such as a caveat about the temp-file mechanism that belongs at the spec level rather than only in architecture.md), fix it and note what you found and why in your report.

## Validation

- `git diff README.md` shows the Features bullet updated: no remaining reference to "not currently styled" or `TNLq` for PDF output.
- `git diff docs/architecture.md` shows the "Bundled stylesheet" section describing the `mktemp`-based `.css` temp-file mechanism, not process substitution.
- `docs/md2x-spec.md` — either `git diff docs/md2x-spec.md` is empty with the task report explaining why (verified already accurate), or it shows a specific, justified correction.
- `grep -rn "TNLq" README.md docs/md2x-spec.md docs/architecture.md` returns no matches (the followup ID itself should not appear in any of these three docs once this task is done, per the project's convention that followup IDs are ephemeral session artifacts, not permanent doc content — cross-check this convention against how other followup references were previously scrubbed from these same docs if any doubt, e.g. via `git log -p` on these files).
- Re-read all three edited/reviewed passages once more after editing to confirm they're internally consistent with each other and with `docs/architecture.md`'s "Page generation / conversion pipeline" component description (no requirement to edit that section, just confirm no new contradiction was introduced).

## Assumptions

- Task 001 has landed and its exact implementation choices (temp file location pattern, `KEEP_INTERMEDIATE` gating decision for the CSS temp file) are visible in `src/cli/lib/generate-page.sh` by the time this task executes — read that file fresh rather than relying solely on task 001's task document, since the actual landed code is the source of truth for what to describe.
- This task does not need to touch `docs/project-structure.md` or `AGENTS.md` — neither was named in the manager's request, and neither currently makes a false claim about PDF styling (confirm this holds if you happen to read either file, but no proactive edit is expected).

## References

- `plan/followups.yaml` (project root), items `TNLq` and `LUhO` — the two followups motivating this task's doc corrections.
- `src/cli/lib/generate-page.sh` as landed by task 001 — the source of truth for what `docs/architecture.md`'s "Bundled stylesheet" section should now say.
- Flow plugin's Markdown Style Guide (`markdown-style-standards.md`) — non-functional formatting conventions (heading case, code-block language tags) to preserve when editing prose in these three files.

## Metadata

architectural_impact: false

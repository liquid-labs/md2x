# Update Architecture Docs

## Purpose and scope

Bring `docs/architecture.md` and `docs/md2x-spec.md` into line with the architectural changes landed in Phase 01, which introduced a self-managed WeasyPrint PDF engine and, with it, a genuine change to md2x's documented product principles.

Both documents currently assert things that Phase 01 makes false:

- `docs/md2x-spec.md` — "md2x does not install these dependencies itself" (Constraints and assumptions) and "md2x does not manage or install its external binary dependencies (`pandoc`, `gs`, `pdftk`) — it verifies their presence and fails fast if one is missing, but installation is the operator's responsibility" (Non-goals).
- `docs/architecture.md` — the *Minimal, mature external dependency set* key decision makes the same claim, and the *Tech stack* section states "No datastore. md2x is a stateless, single-pass batch conversion tool operating directly on the filesystem; it holds no state between invocations" — contradicted by the persistent per-user `~/.md2x/venv` cache.

These must be **corrected to state the new, accurate contract**, not silently left contradicting the implementation. This is the explicit purpose of the task.

Follow the `update-architecture-docs` task-procedure at `/Users/zane/playground/sdlcforge/flow/plugins/flow/task-procedures/update-architecture-docs/SKILL.md`.

## Requirements

role_doc: `/Users/zane/playground/sdlcforge/flow/plugins/flow/references/roles/architect-backend.md` — the implications are component- and dependency-boundary changes within the CLI (a new internal component, a changed preflight contract, new persistent local state), not data-model, cloud-topology, or frontend concerns.

### Task documents that surfaced these architectural implications

Both have completed by the time this task runs:

- `plan/phase-01-weasyprint-pdf-engine/001-bootstrap-weasyprint-and-pin-engine.md` — added `src/cli/lib/ensure-weasyprint.sh`, added `python3` to the binary preflight check, and pinned Pandoc's `--pdf-engine` to `~/.md2x/venv/bin/weasyprint`.
- `plan/phase-01-weasyprint-pdf-engine/002-update-consumer-and-contributor-docs.md` — updated `README.md`, `AGENTS.md`, and `docs/project-structure.md`; the architecture and spec documents were deliberately deferred to this task.

Read the merged Phase 01 source changes directly before writing; document what shipped, not what was planned.

### Files to review and update

**`docs/architecture.md`**

- **System overview + Mermaid diagram.** The preflight decision node reads `pandoc, gs, pdftk on PATH?` and must include `python3`. Add the WeasyPrint bootstrap as a component in the flow — a PDF-output-only step between preflight and the Pandoc call, reading/creating `~/.md2x/venv` — and show the Pandoc node using the pinned engine. Keep the diagram legible; do not let it sprawl.
- **The prose walkthrough that follows the diagram.** The document carries an explicit note that the diagram is explained in the following paragraph for AI agents and non-visual readers, so the numbered sequence (steps 1-4) must be updated in step with the diagram — including the new bootstrap step and its PDF-only gating. Keep that accessibility contract intact.
- **Tech stack.** Correct the "No datastore ... holds no state between invocations" claim: md2x now maintains exactly one piece of persistent local state, the per-user `~/.md2x/venv` dependency cache, which is a bootstrap artifact rather than document or user data. Also update the external-binaries bullet to cover `python3` and to distinguish operator-installed binaries from the md2x-managed engine.
- **Major components.** Add a component subsection for the bootstrap (`src/cli/lib/ensure-weasyprint.sh`): what it owns, the cheap `-x` warm-path check, the cold-path `venv` + `ensurepip` + `pip install` sequence, its stderr-only output discipline, and its exit-`2` failure contract. Update the *CLI entry point and argument parsing* and *Page generation / conversion pipeline* subsections where they describe the preflight check and the Pandoc invocation.
- **Key decisions.** Rewrite *Minimal, mature external dependency set* honestly, and add (or fold in) the rationale for the asymmetry: `pandoc`, `gs`, `pdftk`, and `python3` are operator-installed and preflight-verified; WeasyPrint alone is md2x-managed in an isolated venv. State the reason — WeasyPrint is a Pandoc *implementation detail* the user never invokes directly and, before this change, an undocumented hidden requirement that broke PDF output outright when Pandoc 3.4 changed its default engine — and state the trade-offs taken on: a `python3` runtime requirement, first-run latency and a network dependency, persistent per-user state, and md2x owning an install path it must now keep working. Also check the *HTML5 intermediate instead of a LaTeX engine* decision, whose "shrinking the dependency footprint to three widely-available binaries" rationale is now numerically and substantively stale.
- **Table of contents** — update if any heading is added or renamed.

**`docs/md2x-spec.md`** (the project's single `docs/*-spec.md`)

- **General features → Binary preflight check.** Add `python3` to the verified set, preserving the exit-`2`, name-the-first-missing-binary contract.
- **General features.** State the WeasyPrint bootstrap as spec-level behavior: on the first PDF conversion, md2x installs WeasyPrint into `~/.md2x/venv` if it is not already there, emitting a one-time notice on stderr; a failure to do so exits `2` naming the failing step. Note that stdout stays clean (`--list-files` and `--to-stdout` contracts are unaffected) and that `--quiet` does not suppress the notice.
- **API definition → CLI → Exit behavior.** Extend the exit-`2` description to cover both a missing required binary and a failed WeasyPrint bootstrap.
- **Node library.** The "Requires the same external binaries (`pandoc`, `gs`, `pdftk`) on `PATH`" bullet must include `python3` and note the automatic WeasyPrint bootstrap applies equally through the wrapper.
- **Constraints and assumptions.** Replace "md2x does not install these dependencies itself" with the accurate split contract, and note the `~/.md2x/venv` per-user location (not project-relative, not XDG) and that a first PDF conversion requires network access.
- **Non-goals.** Correct the dependency-management non-goal so it states what remains true — md2x does not install `pandoc`, `gs`, `pdftk`, or `python3`; those remain the operator's responsibility — while acknowledging the single deliberate exception. Do not delete the non-goal outright; the principle still holds for four of the five dependencies, and the exception is worth naming precisely.
- **Purpose-and-scope / Pointers.** Both sections still describe `docs/architecture.md` as "a future" document that "does not yet exist" (it does), and the General features section says the overlay mechanism belongs "in a future `docs/architecture.md`". These are pre-existing staleness rather than something Phase 01 caused. Fix them if the fix is a small in-place correction of the surrounding sentences being edited anyway; leave them and flag them otherwise. Do not let this expand into a broad spec revision.

### Boundaries

- Do not change `README.md`, `AGENTS.md`, or `docs/project-structure.md` — Phase 01 task 002 owns those. If they contradict what is written here, flag the discrepancy rather than silently editing them.
- Do not change anything under `src/`. This is a documentation task; a documentation change that reveals an implementation defect is a flag, not a fix.
- Do not re-litigate the design. The `~/.md2x/venv` location, the absence of a staleness check, the stderr-not-`--quiet` decision, and the unaddressed concurrency limitation are settled; document them, including the limitation, as decisions with stated trade-offs.

## Validation

1. **No surviving false claim.** `grep -n 'does not install these dependencies\|installation is the operator' docs/md2x-spec.md` and `grep -n 'holds no state between invocations\|three widely-available binaries\|Three external binaries' docs/architecture.md` return either no hits or only hits whose surrounding text is now accurate under the new contract.
2. **`python3` present in every dependency statement.** `grep -n 'pdftk' docs/architecture.md docs/md2x-spec.md` — every enumeration of required binaries includes `python3`; none is left at three.
3. **Diagram and prose agree.** The Mermaid diagram's nodes and the numbered prose walkthrough below it describe the same sequence, including the bootstrap step and its PDF-only gating. The Mermaid block parses (no syntax error; render or lint it).
4. **Claims check out against the source.** Every path, exit code, and behavioral claim added to either document is verifiable in the merged Phase 01 sources (`src/cli/lib/ensure-weasyprint.sh`, `src/cli/md2x.sh`, `src/cli/lib/generate-page.sh`).
5. **Consistency with Phase 01 documentation.** `README.md`, `AGENTS.md`, and `docs/project-structure.md` are not contradicted by the new text — prerequisite lists, the `~/.md2x/venv` path, and the "WeasyPrint is not a manual prerequisite" framing all agree across all five documents.
6. **Structure intact.** Each document's table of contents matches its headings after the edits; internal anchor links still resolve; cross-document relative links (`./md2x-spec.md`, `../AGENTS.md`, `./project-structure.md`) are unbroken.
7. **Scope check.** `git diff --name-only` lists exactly `docs/architecture.md` and `docs/md2x-spec.md`.

## Assumptions

- All Phase 01 tasks have completed and merged; their source and documentation changes are readable in this task's starting state.
- `docs/architecture.md` exists (it does, despite spec text that still calls it "future"), and `docs/md2x-spec.md` is the sole `docs/*-spec.md` match.
- The environment can run a PDF conversion if the writer wants to observe actual behavior; `rm -rf ~/.md2x` restores cold state, and a first conversion needs network access.

## References

- `/Users/zane/playground/sdlcforge/flow/plugins/flow/task-procedures/update-architecture-docs/SKILL.md` — the task-procedure to follow.
- `/Users/zane/playground/sdlcforge/flow/plugins/flow/references/roles/architect-backend.md` — the role doc for this task.
- [Plan overview](../overview.md) — the full change scope and an explicit statement of the documented-principle shift.
- [WeasyPrint bootstrap design notes](../notes/weasyprint-bootstrap-design.md) — the decisions and trade-offs to document, including the concurrency limitation and the absent staleness check.
- [Phase 01 task 001](../phase-01-weasyprint-pdf-engine/001-bootstrap-weasyprint-and-pin-engine.md) and [task 002](../phase-01-weasyprint-pdf-engine/002-update-consumer-and-contributor-docs.md) — the implementation and consumer-doc tasks that surfaced these implications.
- `docs/architecture.md` — System overview (diagram ~lines 21-53), Tech stack (~lines 55-60), Major components (~lines 62-82), Key decisions (~lines 84-90).
- `docs/md2x-spec.md` — General features (~lines 56-65), Exit behavior (~line 93), Node library requirements (~line 116), Constraints and assumptions (~lines 120-126), Non-goals (~lines 128-132).

## Checkpoint hints

- After updating `docs/architecture.md`'s system overview (diagram plus the numbered prose walkthrough).
- After updating `docs/architecture.md`'s tech stack, components, and key decisions.
- After updating `docs/md2x-spec.md`.

## Status

**Outcome: succeeded.** Implemented 2026-07-29.

Both `docs/architecture.md` and `docs/md2x-spec.md` now state the accurate, asymmetric dependency
contract: `pandoc`, `gs`, `pdftk`, and `python3` are operator-installed and preflight-verified;
WeasyPrint alone is md2x-managed in `~/.md2x/venv`. `git diff --name-only` shows exactly these two
files.

**`docs/architecture.md`:**
- Mermaid diagram: preflight node now lists all four binaries; added a `PdfCheck`/`Bootstrap` branch
  between preflight and the link-rewrite step, gated on PDF output, showing the `ensure-weasyprint`
  cheap-check-then-install sequence; the Pandoc node now notes the pinned `--pdf-engine`. Rendered
  successfully with `mmdc` (Chrome via `PUPPETEER_EXECUTABLE_PATH`) — no syntax errors.
- Prose walkthrough renumbered to 5 steps, adding the bootstrap step in lockstep with the diagram.
- Tech stack: replaced the "holds no state between invocations" claim with an accurate statement of
  the one persistent artifact (`~/.md2x/venv`); added `python3` to the operator-installed binaries
  bullet and a new bullet distinguishing WeasyPrint as the sole md2x-managed dependency.
- Major components: added a new `### WeasyPrint bootstrap` subsection (what it owns, warm/cold path,
  stderr-only discipline, exit-`2` contract, pinned `weasyprint==69.0`); updated *CLI entry point* and
  *Page generation* to reference the preflight/bootstrap/pin.
- Key decisions: rewrote *Minimal, mature external dependency set* with the asymmetry rationale and
  stated trade-offs (python3 requirement, first-run latency/network, persistent state, an install path
  md2x must maintain); fixed the now-stale "three widely-available binaries" / "three external
  binaries" numeric claims in the *HTML5 intermediate* and *Bash + bash-rollup* bullets (the latter
  wasn't named explicitly in Requirements but is the same class of staleness, fixed as a same-diff
  self-fix within the Key decisions section already being edited).
- Purpose and scope: corrected the "three external tools" framing to name all four operator binaries
  plus the self-managed WeasyPrint install.
- Table of contents: unchanged — no `##`-level headings were added or renamed (the new subsection is
  `###`, matching the existing pattern of not listing `###` headings in the TOC).

**`docs/md2x-spec.md`:**
- Binary preflight check bullet: added `python3`.
- Added a new **Automatic WeasyPrint bootstrap (PDF output only)** bullet to General features, stating
  the spec-level behavior (install on first PDF conversion, stderr notice, exit `2` on failure, stdout
  purity, `--quiet` does not suppress it).
- Exit behavior: extended to cover a failed WeasyPrint bootstrap alongside a missing binary.
- Node library: `Requires` bullet now lists `python3` and notes the bootstrap applies through the
  wrapper.
- Constraints and assumptions: replaced "md2x does not install these dependencies itself" with the
  accurate split contract, the `~/.md2x/venv` per-user (not project-relative, not XDG) location, and
  the network-access note for the first PDF conversion.
- Non-goals: corrected to name `pandoc`/`gs`/`pdftk`/`python3` as the operator's responsibility while
  naming the single WeasyPrint exception; the non-goal is preserved, not deleted, per the task's
  explicit instruction.
- Purpose-and-scope / Pointers: fixed the "future `docs/architecture.md`, not yet written" /
  "does not yet exist" claims in place (small in-place corrections in sentences already being touched
  for other reasons) and converted the dangling Pointers paragraph into a proper pointer bullet.

**Validation summary** (all against the merged Phase 01 sources — `src/cli/lib/ensure-weasyprint.sh`,
`src/cli/md2x.sh`, `src/cli/lib/generate-page.sh` — and the already-merged Phase 01 docs):

1. Passed — `grep -n 'does not install these dependencies\|installation is the operator'
   docs/md2x-spec.md` and `grep -n 'holds no state between invocations\|three widely-available
   binaries\|Three external binaries' docs/architecture.md` both return no hits.
2. Passed — every `pdftk`-containing line that enumerates required binaries also names `python3`; the
   remaining `pdftk` hits (the PDF header/footer overlay mechanism specifically) don't claim to
   enumerate the full binary set and are unchanged/accurate as scoped statements about `gs`+`pdftk`.
3. Passed — diagram and the 5-step prose agree; `mmdc` rendered the diagram to SVG with no errors
   (Chrome resolved via `PUPPETEER_EXECUTABLE_PATH` since the cached `chrome-headless-shell` version
   mismatched what this `mmdc` install expected).
4. Passed — every path (`~/.md2x/venv`, `~/.md2x/venv/bin/weasyprint`), exit code (`2`), pinned version
   (`weasyprint==69.0`), and behavioral claim (stderr-only output, gated on PDF format, `-x` warm-path
   check, `rm -rf` cleanup on failure) was checked directly against the three named source files.
5. Passed — cross-checked `python3`/`pdftk` prerequisite lists and the `~/.md2x/venv` path and
   "not a manual prerequisite" framing against `README.md` and `AGENTS.md`; no contradictions found.
6. Passed — both documents' tables of contents are unchanged and still match their `##` headings; all
   in-document anchor links (verified programmatically by slugifying every heading and checking every
   `(#...)` link resolves) and cross-document relative links (`./md2x-spec.md`, `./architecture.md`,
   `../AGENTS.md`, `./project-structure.md`) resolve.
7. Passed — `git status --porcelain` shows only `docs/architecture.md` and `docs/md2x-spec.md` modified.

**Assumptions applied:** the three `## Assumptions` in this task doc all held as stated — Phase 01 was
merged and readable, `docs/architecture.md` exists despite spec text calling it "future," and
`docs/md2x-spec.md` is the sole `docs/*-spec.md` file. No PDF conversion was run to observe live
behavior; all behavioral claims were verified by reading the merged source directly (the Phase 01 task
docs' own `## Status` sections record that the wording and behavior were already observed live during
Phase 01, and this task quotes/paraphrases from the shipped source rather than re-deriving it).

**Flagged for manager (not fixed here, out of this task's scope):**
- `docs/architecture.md`'s own Pointers section still calls `docs/project-structure.md` "(planned)"
  even though the file exists. This predates Phase 01/the WeasyPrint plan entirely (unrelated to the
  documented-principle shift this task addresses) and isn't in the task doc's `## Requirements` list of
  sections to touch, so left as-is per the "smallest correct change" / "do not re-litigate" guidance.
- `AGENTS.md` (line ~48, ~67) and `docs/project-structure.md` (line ~57) both still describe
  `docs/architecture.md` as "(planned)" / not yet existing, even though it does. Per this task's
  Boundaries section ("Do not change README.md, AGENTS.md, or docs/project-structure.md ... If they
  contradict what is written here, flag the discrepancy rather than silently editing them"), this is
  flagged rather than fixed — it's Phase 01 task 002's file set, and the staleness predates this plan.
- `docs/md2x-spec.md`'s "Consistent styling" General features bullet and UC1's outcome description both
  still claim PDF output receives the built-in GitHub CSS. Per phase-01 task 001's `## Status`, WeasyPrint
  currently rejects the `--css` process-substitution delivery, so **PDF output currently has no CSS
  styling applied** (already documented accurately in the merged `README.md` Features list, alongside
  followup `TNLq`). This spec-level claim is stale for the same underlying reason, but fixing the CSS
  gap itself is explicitly out of scope (`TNLq`), and neither the "Consistent styling" bullet nor UC1 was
  named in this task's `## Requirements` file list, so it was left unedited and is flagged here rather
  than fixed.

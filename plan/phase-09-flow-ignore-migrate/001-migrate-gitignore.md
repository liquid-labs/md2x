# Migrate Gitignore To Single Flow Entry

## Purpose and scope

Wave 2 of wave plan flow-ignore-canonicalization (plan-group migrate-liquid-labs), project `md2x`. Make `.gitignore` ignore Flow's per-machine state with exactly one `.flow/` entry and remove any `.flow` content from the git index.

## Requirements

1. Work only inside the task worktree; never edit files in the main checkout.
2. In `.gitignore`, remove every flow-related ignore line or comment block that the single entry supersedes, and add exactly one `.flow/` line preceded by the one-line comment `# Flow per-machine runtime state; durable state lives in plan/ and flow/.`. Keep every unrelated line untouched; create `.gitignore` if absent. Inventory for this project: lines 15 `.flow/*`, 16 `!.flow/plans`, 17 `!.flow/project-analysis.json` and 18 `!.flow/what-next-cache.json` are superseded and must be removed (together with any comment immediately describing them)
3. Tracked `.flow` content: the inventory lists 1 tracked path, `.flow/what-next-cache.json`; run `git rm -r --cached .flow` and include the removal in the commit. If the inventory lists tracked `.flow` paths (or `git ls-files .flow` is non-empty in the worktree), run `git rm -r --cached .flow` (files stay on disk) and include the removals in the same commit.
4. Commit only `.gitignore` and the `.flow` untracking, with message `chore: ignore .flow/ via a single canonical entry` (add a note that `.flow` was untracked with `git rm --cached` if applicable), following the project's normal commit conventions. Do not change any other file.

## Validation

- `git check-ignore -v .flow/x` reports a match on the `.gitignore` line `.flow/`.
- `git ls-files .flow` is empty.
- `git diff <base>..HEAD --stat` lists only `.gitignore` (and removed `.flow/*` paths); no other file changed.
- If the project has fast checks relevant to `.gitignore` (none expected), they still pass.

## Assumptions

- The Flow release containing the `.flow/` enforcement (wave 1) is installed.
- The main checkout's uncommitted work is untouched because the task runs in an isolated worktree.
- The main checkout is clean, so close-out should merge without owner action.

## References

- Wave plan: flow-ignore-canonicalization (wave-2-migration, plan-group migrate-liquid-labs), lead project sdlcforge/flow.
- Inventory: /Users/zane/playground/.flow/flow-ignore-migration-inventory.md (row `liquid-labs/md2x`).

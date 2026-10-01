# Migrate md2x to a single .flow/ ignore entry

## Purpose and scope

This is wave 2 (wave-2-migration) of the wave plan flow-ignore-canonicalization, delivered as the plan-group migrate-liquid-labs. Flow now treats `.flow/` as fully git-ignored; this plan migrates the `md2x` project to match. It is a single-project, single-task plan.

## Overview

Replace every flow-related ignore line in `.gitignore` with one canonical `.flow/` entry and untrack any `.flow` content that is currently tracked (`git rm -r --cached .flow`, files stay on disk). The work is a single small commit touching only `.gitignore` and the `.flow` untracking. Current state: lines 15 `.flow/*`, 16 `!.flow/plans`, 17 `!.flow/project-analysis.json` and 18 `!.flow/what-next-cache.json` are superseded and must be removed (together with any comment immediately describing them); the inventory lists 1 tracked path, `.flow/what-next-cache.json`; run `git rm -r --cached .flow` and include the removal in the commit.

## Phases

| Phase | Slug | Task | Tier |
|-------|------|------|------|
| 9 | flow-ignore-migrate | migrate-gitignore | sonnet-low |

## Risks

The main checkout is clean, so close-out should merge without owner action.

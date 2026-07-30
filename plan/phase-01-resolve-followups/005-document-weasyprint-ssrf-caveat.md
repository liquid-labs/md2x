# Document WeasyPrint SSRF Caveat For Library Consumers

## Purpose and scope

Closes followup `Kjs2`. WeasyPrint (the pinned `--pdf-engine`, reachable via the library API `src/node/md2x.js`) fetches external resources referenced in rendered HTML — `img src`, CSS `url()`/`@import` (including `file://` URLs) — with no built-in allowlist. Run as a CLI against a user's own documents this is low risk, but `md2x()` is also published as an npm library (`@liquid-labs/md2x`) that a consuming application could embed to render externally-supplied Markdown, in which case resource references in that content could be used for SSRF or local-file disclosure via WeasyPrint's default fetch behavior.

This is a **documentation-only** task: add a caveat to `docs/md2x-spec.md`'s Node library section (and, at your discretion, a short pointer in `README.md`'s Node library section too) noting that callers embedding md2x against externally-authored/untrusted Markdown via the library API should apply the same precautions as any other SSRF-capable rendering path — network egress restrictions, or a WeasyPrint URL-fetcher override. No code change.

## Requirements

- In `docs/md2x-spec.md`, add a short caveat to the `### Node library` subsection (under `## API definition`) — a new bullet alongside the existing "Returns"/"Throws"/"Requires" bullets, or a short paragraph immediately after them, is a good fit. State plainly:
  - WeasyPrint (the PDF rendering engine, reached via the CLI this library shells out to) fetches external resources referenced in converted HTML/CSS (image `src`, CSS `url()`/`@import`, including `file://` URLs) with no built-in allowlist.
  - A consuming application that embeds `md2x()` to render externally-authored or otherwise untrusted Markdown should treat this the same as any other SSRF-capable rendering path: apply network egress restrictions around the process, or supply a WeasyPrint URL-fetcher override, rather than assuming the library sandboxes resource fetches on the caller's behalf.
- Optionally, add a shorter pointer sentence in `README.md`'s "As a Node library" section (or its "Features" list) linking to the fuller caveat in `docs/md2x-spec.md` — your call whether this adds enough value to be worth the extra line; the spec is the canonical, required location.
- Do not touch `docs/architecture.md`'s WeasyPrint-bootstrap prose — that document is the *how* layer (design/mechanism) per its own purpose-and-scope statement, and this caveat is a *usage/risk* statement that belongs in the spec's API-surface documentation, not the architecture doc. If you judge a one-line cross-reference from `docs/architecture.md` would help a reader, that's an acceptable addition but not required.

## Validation

- `docs/md2x-spec.md`'s Node library section contains the new caveat text; re-read it once written to confirm it reads clearly in context alongside the existing "Returns"/"Throws"/"Requires" bullets.
- `make test` still passes (this task makes no code changes, so this is a sanity check that nothing else regressed while your worktree was in flight).
- `grep -rn "Kjs2" plan/followups.yaml` — confirm the id no longer appears after this task's report is applied (report the resolved id; removal is the manager's step via `followups_remove`).

## References

- `docs/md2x-spec.md`'s `### Node library` subsection (under `## API definition`) — the primary edit location.
- `README.md`'s "As a Node library" section — optional secondary pointer.
- `plan/followups.yaml` item `Kjs2` — full original followup text.

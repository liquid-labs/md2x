# Pandoc GFM Auto-Identifier Algorithm

## Purpose and scope

The verified, reproducible specification of the heading-identifier ("slug") algorithm md2x's
TOC generator must replicate exactly, so that a hand-written `[Heading](#slug)` Markdown link
resolves against the anchor Pandoc actually emits. Derived by differential testing against
Pandoc 3.10.1 on 2026-07-30, not from documentation. Read this before implementing
`src/cli/lib/toc-preprocess.py`.

## The reader, not the writer, mints identifiers — and md2x reads `gfm`

`src/cli/lib/generate-page.sh` passes `--from gfm`. Pandoc's `gfm` reader enables the
`gfm_auto_identifiers` extension, **not** the classic `auto_identifiers` used by the plain
`markdown` reader. The two differ materially, and getting this wrong silently produces broken
anchors. Measured differences (same input, `--to html5`):

| Heading text | `--from gfm` | `--from markdown` |
| --- | --- | --- |
| `1. Numbered Section` | `1-numbered-section` | `numbered-section` |
| `2026 Roadmap` | `2026-roadmap` | `roadmap` |
| `-- leading dashes` | `---leading-dashes` | `leading-dashes` |
| `A/B testing & "quotes"` | `ab-testing--quotes` | `ab-testing-quotes` |
| `Emoji 🎉 party` | `emoji-tada-party` | `emoji-party` |

The `gfm` column is what md2x must reproduce. Note in particular that **leading digits are
kept** and **empty tokens collapse to consecutive hyphens** — both the opposite of the classic
algorithm. Any description of the algorithm that says "drop leading digits" or "collapse
whitespace" is describing the wrong reader.

## The algorithm

Pandoc computes the identifier from the heading's *parsed inline sequence*, mapping each
`Space` inline to a single `-` and stripping disallowed characters from each `Str`. The
following source-text approximation reproduces it exactly across the corpus below.

1. **Flatten inline markup** in the raw heading text, in this order:
   - remove HTML comments and inline HTML tags (`<!-- ... -->`, `</?tag ...>`);
   - `![alt](url)` → `alt`;
   - `[text](url)` → `text`; `[text][ref]` → `text`;
   - `<https://…>` / `<mailto:…>` autolinks → the URL text;
   - matched underscore emphasis → its content: replace `(?<![0-9A-Za-z_])_+([^_]+?)_+(?![0-9A-Za-z_])`
     with the captured group. Asterisk emphasis needs no pre-pass — `*` is stripped as
     punctuation in step 3 anyway. Backticks likewise need no pre-pass.
2. **Split on whitespace runs** (`\s+`) into tokens, after trimming. An all-whitespace heading
   yields a single empty token.
3. **Filter each token** to the characters where `ch.isalnum() or ch in '_-'` (Python's
   Unicode-aware `isalnum`, which matches Pandoc's Unicode `isAlphaNum`), then lowercase with
   Python's Unicode-aware `str.lower()`.
4. **Join the filtered tokens with `-`.** A token that filters to the empty string still
   contributes its join separator — this is what produces `ab-testing--quotes` and
   `c--c-notes`.

Do **not** ASCII-fold: `Café Déjà-Vu` → `café-déjà-vu`, accents intact.

### Deduplication

Pandoc keeps a set of already-used identifiers and, on collision, appends `-1`, `-2`, … until
free. Implement the same: track a per-document counter keyed on the base slug, and on each
collision try `base-N` for increasing `N`, skipping any candidate already in the used set (so a
document that literally contains a heading named to collide with a generated `-1` still comes
out right).

The counter runs over the **whole document Pandoc sees**. For `--single-page`, that is the
fully concatenated stream, so the preprocessor must run after concatenation (it does — see
[pipeline verification](./pipeline-verification.md)).

### Empty identifiers

A heading whose slug is the empty string (`!!!`, `...`, an all-whitespace ATX heading) is
emitted by Pandoc **without an `id` attribute at all** — `<h2>!!!</h2>` — so it is not
linkable. It nonetheless consumes a dedup slot: three such headings in a row produce ``, `-1`,
`-2`. The TOC generator must therefore **omit empty-slug headings from the emitted TOC** while
still counting them in the dedup state.

## Verified corpus

29 headings run through Pandoc 3.10.1 (`--from gfm --to html5`) and through the reference
implementation of the algorithm above; output was identical for all 29.

| Heading text | Identifier |
| --- | --- |
| `Simple Heading` | `simple-heading` |
| `1. Numbered Section` | `1-numbered-section` |
| `Hello, World! (Again)` | `hello-world-again` |
| `Hello, World! (Again)` (repeat) | `hello-world-again-1` |
| `Café Déjà-Vu` | `café-déjà-vu` |
| `snake_case and dash-case` | `snake_case-and-dash-case` |
| `A/B testing & "quotes"` | `ab-testing--quotes` |
| `2026 Roadmap` | `2026-roadmap` |
| `Multi   internal   spaces` | `multi-internal-spaces` |
| `` `code` in heading `` | `code-in-heading` |
| `**bold** and _em_` | `bold-and-em` |
| `-- leading dashes` | `---leading-dashes` |
| `Simple Heading` (repeat) | `simple-heading-1` |
| `Heading with [a link](http://x.com) inside` | `heading-with-a-link-inside` |
| `C++ & C# notes` | `c--c-notes` |
| `50% off — dashes and em-dash` | `50-off--dashes-and-em-dash` |
| `foo.bar.baz` | `foobarbaz` |
| ``The `--no-toc` flag`` | `the---no-toc-flag` |
| `Ünïcödé Ⅻ Roman` | `ünïcödé-ⅻ-roman` |
| `!!!` | *(no id emitted)* |
| `...` | `-1` |
| *(all whitespace)* | `-2` |
| `under_score_only` | `under_score_only` |
| `_leading emphasis_ text` | `leading-emphasis-text` |
| `trailing text _emph_` | `trailing-text-emph` |
| `API (v2.0) — Reference` | `api-v20--reference` |
| `Tab<TAB>separated` | `tab-separated` |
| `"Quoted Heading"` | `quoted-heading` |
| `$variable and #hash` | `variable-and-hash` |

## Known, accepted divergences

Two cases where the source-text approximation cannot match Pandoc without a full CommonMark
parser. Both are documented limitations, not defects to chase:

- **Emoji.** The `gfm` reader's `emoji` extension turns `🎉` into the name `tada`, so Pandoc
  yields `emoji-tada-party`; the approximation yields `emoji--party`. A heading containing an
  emoji character therefore gets a TOC entry whose link does not resolve. Acceptable: the
  entry still renders as text, and emoji in headings is rare in the documents md2x targets.
- **Unpaired boundary underscore.** `_private` with no closing `_` is literal text to
  CommonMark, so Pandoc keeps `_private`. The step-1 emphasis pre-pass only strips *matched*
  pairs, so this case is handled correctly; but a heading mixing paired and unpaired
  underscores in unusual ways may still diverge.

Both belong in the user-facing limitation note the docs task adds, not in the implementation.

## Heading recognition

Verified against Pandoc 3.10.1 with `--from gfm`:

| Construct | Is a heading? |
| --- | --- |
| `# ATX` (1–6 `#` then space) | yes |
| `####### Seven hashes` | no |
| `#NoSpaceHash` | no |
| `## Trailing hashes ##` | yes; trailing `#` run stripped from the text |
| Setext (`Text` then `===` or `---`) | yes |
| Inside a fenced code block | no |
| Inside a 4-space-indented code block | no |
| Inside an HTML comment | no |
| Inside a blockquote (`> ## X`) | yes — Pandoc mints an identifier for it |
| Inside a list item (`- ## X`) | yes — Pandoc mints an identifier for it |

Blockquote- and list-nested headings are **out of scope** for md2x's scanner (recognizing them
correctly requires block-structure parsing). The consequence is bounded and benign: such a
heading is missing from the TOC and, because it silently consumes a Pandoc dedup slot that the
scanner does not model, a later same-titled top-level heading's generated link can point at the
nested one instead. Document the limitation; do not build a block parser.

## Reproducing this

```bash
pandoc --from gfm --to html5 headings.md | grep -o 'id="[^"]*"'
```

Run the same corpus through the implementation and `diff` the two identifier streams. That
comparison is the acceptance test for the slug algorithm, and it is cheap enough to keep as a
checked-in `real-toolchain-e2e.bats` case gated on `pandoc` being present.

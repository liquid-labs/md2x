#!/usr/bin/env python3
"""Markdown-in / Markdown-out TOC preprocessing stage for md2x.

Scans headings in a Markdown document, replicates Pandoc's ``gfm_auto_identifiers``
slug algorithm exactly (see 'plan/notes/pandoc-gfm-slug-algorithm.md'), decides
whether a table of contents is warranted (see
'plan/notes/toc-defaults-and-page-heuristic.md'), and emits a nested
'[Heading](#slug)' bullet list at the '<!-- md2x:toc -->' marker or at a default
position.

Usage: toc-preprocess.py --mode on|off|auto

Reads the whole document from stdin, writes the transformed document to stdout.
stdout carries document bytes exclusively; every diagnostic goes to stderr,
prefixed 'md2x: ' to match the CLI's existing message style (see
'src/cli/lib/ensure-weasyprint.sh'). Python 3 standard library only; targets the
ambient system 'python3' the CLI preflight-checks (avoid syntax newer than 3.8).
"""

import math
import re
import sys

# --- calibrated estimator constants -------------------------------------------------
#
# Calibrated against the real toolchain (Pandoc 3.10.1, WeasyPrint, github.css); see
# 'plan/notes/toc-defaults-and-page-heuristic.md' for the calibration table and the
# derivation of both values. Do not change without re-deriving the calibration.
CHARS_PER_RENDERED_LINE = 85
RENDERED_LINES_PER_PAGE = 45

# --- recognition patterns -------------------------------------------------------------
#
# Every pattern below implements a rule from
# 'plan/notes/pandoc-gfm-slug-algorithm.md' (heading recognition) or
# 'plan/notes/toc-defaults-and-page-heuristic.md' (marker recognition).

MARKER_RE = re.compile(r'^ {0,3}<!--[ \t]*md2x:toc[ \t]*-->[ \t]*$')

ATX_RE = re.compile(r'^ {0,3}(#{1,6})(?:[ \t]+(.*)|())$')
SETEXT_EQ_RE = re.compile(r'^ {0,3}=+[ \t]*$')
SETEXT_DASH_RE = re.compile(r'^ {0,3}-+[ \t]*$')
BLANK_RE = re.compile(r'^[ \t]*$')
BLOCKQUOTE_RE = re.compile(r'^ {0,3}>')
LIST_ITEM_RE = re.compile(r'^ {0,3}(?:[-*+][ \t]|\d+[.)][ \t])')
INDENTED_CODE_RE = re.compile(r'^ {4,}\S')

FENCE_OPEN_RE = re.compile(r'^ {0,3}(`{3,}|~{3,})(.*)$')
FENCE_CLOSE_RE = re.compile(r'^ {0,3}(`+|~+)[ \t]*$')

LINE_ENDING_RE = re.compile(r'(\r\n|\r|\n)$')

# --- inline-markup flattening (slug algorithm step 1) ---------------------------------

COMMENT_RE = re.compile(r'<!--.*?-->')
# Only matches a genuine HTML tag shape (letter tag-name immediately followed by
# whitespace, '/' or '>'); an autolink like '<https://...>' has a ':' immediately
# after the scheme name, which fails the lookahead, so autolinks fall through to
# AUTOLINK_RE untouched.
TAG_RE = re.compile(r'</?[A-Za-z][A-Za-z0-9-]*(?=[\s/>])[^<>]*>')
IMAGE_RE = re.compile(r'!\[([^\]]*)\]\([^)]*\)')
LINK_RE = re.compile(r'\[([^\]]*)\]\([^)]*\)')
REFLINK_RE = re.compile(r'\[([^\]]*)\]\[[^\]]*\]')
AUTOLINK_RE = re.compile(r'<((?:https?|mailto):[^<>]*)>')
EMPHASIS_RE = re.compile(r'(?<![0-9A-Za-z_])_+([^_]+?)_+(?![0-9A-Za-z_])')


def flatten_inline(text):
    """Step 1 of the slug algorithm: flatten inline markup, in the note's order."""
    t = COMMENT_RE.sub('', text)
    t = TAG_RE.sub('', t)
    t = IMAGE_RE.sub(r'\1', t)
    t = LINK_RE.sub(r'\1', t)
    t = REFLINK_RE.sub(r'\1', t)
    t = AUTOLINK_RE.sub(r'\1', t)
    t = EMPHASIS_RE.sub(r'\1', t)
    return t


def slugify(raw_text):
    """Reproduces Pandoc's 'gfm_auto_identifiers' slug algorithm exactly.

    Four steps, per 'plan/notes/pandoc-gfm-slug-algorithm.md': flatten inline
    markup, split on whitespace runs, filter+lowercase each token, join with '-'.
    Does not apply deduplication -- that is the caller's job (see 'allocate_slug'),
    since it depends on document-wide state.
    """
    flattened = flatten_inline(raw_text)
    stripped = flattened.strip()
    tokens = [''] if stripped == '' else re.split(r'\s+', stripped)
    filtered_tokens = []
    for token in tokens:
        kept = ''.join(ch for ch in token if ch.isalnum() or ch in '_-')
        filtered_tokens.append(kept.lower())
    return '-'.join(filtered_tokens)


def allocate_slug(base, used):
    """Allocates a deduplicated identifier for 'base', recording it into 'used'.

    Mirrors Pandoc: on collision, try 'base-1', 'base-2', ... skipping any
    candidate already in 'used'. Works uniformly for empty and non-empty bases --
    an empty base collides into '-1', '-2', ... exactly like the corpus in
    'plan/notes/pandoc-gfm-slug-algorithm.md' describes.
    """
    if base not in used:
        used.add(base)
        return base
    n = 1
    while True:
        candidate = f'{base}-{n}'
        if candidate not in used:
            used.add(candidate)
            return candidate
        n += 1


def toc_link_text(raw_text):
    """TOC entry text: Markdown links flattened, residual '[' / ']' escaped.

    Unlike 'slugify', other inline markup (emphasis, code spans) is preserved --
    only link syntax is flattened, per
    'plan/notes/toc-defaults-and-page-heuristic.md'.
    """
    t = LINK_RE.sub(r'\1', raw_text)
    t = REFLINK_RE.sub(r'\1', t)
    t = t.replace('[', '\\[').replace(']', '\\]')
    return t


# --- ATX trailing-hash stripping -------------------------------------------------------

def strip_atx_trailing_hashes(text_after_hashes):
    """Strips an ATX heading's optional closing '#' run (and preceding whitespace).

    'text_after_hashes' is the raw text following the mandatory whitespace after
    the opening '#' run (already known to exist, or '' if the line ended there).
    """
    t = text_after_hashes.rstrip(' \t')
    if not t:
        return ''
    if set(t) == {'#'}:
        # The entire remaining text is a hash run; it is a closing sequence
        # because it is preceded by the whitespace already consumed to reach here.
        return ''
    m = re.match(r'^(.*)[ \t]#+$', t)
    if m:
        return m.group(1).rstrip(' \t')
    return t


# --- line-ending handling ---------------------------------------------------------------

def split_line(line):
    """Splits a 'splitlines(keepends=True)' line into (content, eol)."""
    m = LINE_ENDING_RE.search(line)
    if m:
        return line[:m.start()], m.group(1)
    return line, ''


# --- block-state helpers (fence / setext) ------------------------------------------------

def match_fence_open(line):
    """Returns (char, run_length) if 'line' opens a fenced code block, else None."""
    m = FENCE_OPEN_RE.match(line)
    if not m:
        return None
    run, info = m.groups()
    ch = run[0]
    if ch == '`' and '`' in info:
        # A backtick opener's info string may not contain a backtick.
        return None
    return ch, len(run)


def match_fence_close(line, ch, min_len):
    """True if 'line' closes a fence opened with 'ch' repeated at least 'min_len'."""
    m = FENCE_CLOSE_RE.match(line)
    if not m:
        return False
    run = m.group(1)
    return run[0] == ch and len(run) >= min_len


def is_setext_text_candidate(line):
    """True if 'line' could be the text line of a setext heading.

    Callers only reach this after confirming the line is not an ATX heading and
    not inside a fence; this covers the remaining exclusions (blank, blockquote,
    list item, and 4+-space indented code -- a line indented 4 or more spaces is
    CommonMark/GFM indented code, not paragraph text, and can never be setext
    heading text).
    """
    if BLANK_RE.match(line):
        return False
    if BLOCKQUOTE_RE.match(line):
        return False
    if LIST_ITEM_RE.match(line):
        return False
    if INDENTED_CODE_RE.match(line):
        return False
    return True


def next_comment_state(line, in_comment):
    """Advances the multi-line HTML-comment state across one line.

    A line containing '<!--' with no matching '-->' after it opens the state; the
    state closes on the line containing '-->'. A single-line '<!-- ... -->' never
    enters the state.
    """
    if in_comment:
        return '-->' not in line
    idx = line.find('<!--')
    if idx == -1:
        return False
    close_idx = line.find('-->', idx + len('<!--'))
    return close_idx == -1


# --- document scanner ---------------------------------------------------------------------

def scan_document(contents):
    """Scans the document's lines (no line endings) for headings and markers.

    Tracks exactly three block states, in this order per line: fenced-code state,
    then the marker/heading check, then multi-line HTML-comment state -- per
    'plan/phase-01-markdown-toc-generation/002-add-toc-preprocessor-script.md'.
    Headings and markers nested inside blockquotes or list items are deliberately
    out of scope (see 'plan/notes/pandoc-gfm-slug-algorithm.md').

    Returns (headings, marker_indices, in_fence_for_line):
      headings -- list of {'level', 'text', 'start', 'end'} in document order.
      marker_indices -- 0-indexed line numbers of recognized markers, in order.
      in_fence_for_line -- list[bool], one per line, true for every line that is
        part of a fenced code block (including its delimiters).
    """
    n = len(contents)
    headings = []
    marker_indices = []
    in_fence_for_line = [False] * n

    fence_state = None  # None, or (char, min_len)
    in_comment = False
    i = 0
    while i < n:
        line = contents[i]

        if fence_state is not None:
            in_fence_for_line[i] = True
            if match_fence_close(line, *fence_state):
                fence_state = None
            i += 1
            continue

        opened = match_fence_open(line)
        if opened is not None:
            in_fence_for_line[i] = True
            fence_state = opened
            i += 1
            continue

        eligible = not in_comment
        consumed_extra = False

        if eligible and MARKER_RE.match(line):
            marker_indices.append(i)
        elif eligible:
            m = ATX_RE.match(line)
            if m:
                hashes, text_with_ws, text_empty = m.groups()
                raw = text_with_ws if text_with_ws is not None else text_empty
                headings.append({
                    'level': len(hashes),
                    'text': strip_atx_trailing_hashes(raw),
                    'start': i,
                    'end': i,
                })
            elif i + 1 < n and is_setext_text_candidate(line):
                underline = contents[i + 1]
                if SETEXT_EQ_RE.match(underline):
                    headings.append({
                        'level': 1, 'text': line.strip(' \t'), 'start': i, 'end': i + 1,
                    })
                    consumed_extra = True
                elif SETEXT_DASH_RE.match(underline):
                    headings.append({
                        'level': 2, 'text': line.strip(' \t'), 'start': i, 'end': i + 1,
                    })
                    consumed_extra = True

        in_comment = next_comment_state(line, in_comment)
        if consumed_extra:
            in_comment = next_comment_state(contents[i + 1], in_comment)

        i += 2 if consumed_extra else 1

    return headings, marker_indices, in_fence_for_line


# --- document title / section counting (toc-defaults note) ---------------------------------

def compute_title_index(headings):
    """Index of the document-title heading, or None. See toc-defaults-and-page-heuristic.md."""
    if not headings:
        return None
    shallowest = min(h['level'] for h in headings)
    count_at_shallowest = sum(1 for h in headings if h['level'] == shallowest)
    if count_at_shallowest == 1 and headings[0]['level'] == shallowest:
        return 0
    return None


def compute_top_level_sections(headings, title_index):
    """Top-level section count, per the four-step rule in the toc-defaults note."""
    remainder = headings[1:] if title_index == 0 else list(headings)
    if not remainder:
        return 0
    level = min(h['level'] for h in remainder)
    return sum(1 for h in remainder if h['level'] == level)


# --- page estimator --------------------------------------------------------------------------

def estimate_pages(contents, in_fence_for_line):
    """Estimated rendered page count, per the calibrated estimator in the toc-defaults note.

    Callers must pass lines with any recognized marker line already removed, and
    must call this before injecting the TOC -- neither feeds back into the estimate.
    """
    total = 0
    for line, in_fence in zip(contents, in_fence_for_line):
        stripped = line.strip()
        if stripped == '' or in_fence:
            total += 1
        else:
            total += max(1, math.ceil(len(stripped) / CHARS_PER_RENDERED_LINE))
    return math.ceil(total / RENDERED_LINES_PER_PAGE) if total else 0


# --- TOC decision and construction ------------------------------------------------------------

def should_attempt_toc(mode, has_marker, estimated_pages, section_count):
    """Resolves '--toc'/'--no-toc'/neither into a yes/no, per the toc-defaults note.

    'mode' is already the shell caller's resolution of the flags into on/off/auto;
    this script never sees '--toc'/'--no-toc' directly.
    """
    if mode == 'off':
        return False
    if mode == 'on':
        return True
    # auto: an explicit marker overrides the small-document default-off.
    if has_marker:
        return True
    return estimated_pages > 2 and section_count >= 4


def build_toc_entries(headings, slugs, title_index):
    """Builds the rendered TOC bullet-list lines (no surrounding blank lines).

    Absolute levels 1-3 only, minus the document title, minus empty-slug headings;
    2-space indent per level below the shallowest included level.
    """
    included = []
    for idx, heading in enumerate(headings):
        if idx == title_index:
            continue
        if heading['level'] > 3:
            continue
        if slugs[idx] == '':
            continue
        included.append((heading, slugs[idx]))

    if not included:
        return []

    shallowest = min(heading['level'] for heading, _ in included)
    lines = []
    for heading, slug in included:
        indent = '  ' * (heading['level'] - shallowest)
        text = toc_link_text(heading['text'])
        lines.append(f'{indent}- [{text}](#{slug})')
    return lines


# --- output assembly ---------------------------------------------------------------------------

def build_output(contents, eols, headings, marker_indices, in_fence_for_line, mode):
    """Builds the full output as a list of (content, eol) tuples.

    'mode == off' can never produce TOC entries ('should_attempt_toc' always
    returns False), so it skips the slug-allocation, section-count, and
    page-estimate passes entirely -- any recognized marker is still stripped
    from the output, just with nothing inserted in its place. 'mode == on'
    still needs slugs for the TOC entries it will emit, but -- like 'off' --
    never reads 'section_count'/'estimated_pages' (both feed only the 'auto'
    heuristic in 'should_attempt_toc'), so it skips those two passes as well.
    """
    n = len(contents)
    marker_set = set(marker_indices)

    if mode == 'off':
        entries = []
    else:
        title_index = compute_title_index(headings)
        used_slugs = set()
        slugs = [allocate_slug(slugify(h['text']), used_slugs) for h in headings]

        if mode == 'auto':
            section_count = compute_top_level_sections(headings, title_index)
            estimator_contents = [contents[i] for i in range(n) if i not in marker_set]
            estimator_fence = [in_fence_for_line[i] for i in range(n) if i not in marker_set]
            estimated_pages = estimate_pages(estimator_contents, estimator_fence)
        else:
            section_count = 0
            estimated_pages = 0

        attempt = should_attempt_toc(mode, bool(marker_indices), estimated_pages, section_count)
        entries = build_toc_entries(headings, slugs, title_index) if attempt else []

    toc_block = [('', '\n')] + [(line, '\n') for line in entries] + [('', '\n')] if entries else []

    if marker_indices:
        first = marker_indices[0]
        output = []
        for i in range(n):
            if i in marker_set:
                if i == first and toc_block:
                    output.extend(toc_block)
                continue
            output.append((contents[i], eols[i]))
        return output

    if toc_block:
        if title_index is not None:
            insert_after = headings[title_index]['end']
            return (
                [(contents[i], eols[i]) for i in range(insert_after + 1)]
                + toc_block
                + [(contents[i], eols[i]) for i in range(insert_after + 1, n)]
            )
        return toc_block + [(contents[i], eols[i]) for i in range(n)]

    return [(contents[i], eols[i]) for i in range(n)]


# --- CLI entry point ----------------------------------------------------------------------------

def parse_args(argv):
    """Parses '--mode on|off|auto'; exits with an 'md2x: ' usage message otherwise."""
    if len(argv) == 2 and argv[0] == '--mode' and argv[1] in ('on', 'off', 'auto'):
        return argv[1]
    sys.stderr.write("md2x: usage: toc-preprocess.py --mode on|off|auto\n")
    sys.exit(1)


def run(mode):
    sys.stdin.reconfigure(encoding='utf-8', errors='surrogateescape')
    sys.stdout.reconfigure(encoding='utf-8', errors='surrogateescape')

    data = sys.stdin.read()
    if data == '':
        return

    lines = data.splitlines(keepends=True)
    contents = []
    eols = []
    for line in lines:
        content, eol = split_line(line)
        contents.append(content)
        eols.append(eol)

    headings, marker_indices, in_fence_for_line = scan_document(contents)

    if len(marker_indices) >= 2:
        sys.stderr.write(
            f"md2x: found {len(marker_indices)} 'md2x:toc' markers; "
            "expanded the first and removed the rest.\n"
        )

    output = build_output(contents, eols, headings, marker_indices, in_fence_for_line, mode)
    sys.stdout.write(''.join(content + eol for content, eol in output))


def main(argv):
    mode = parse_args(argv)
    try:
        run(mode)
    except Exception as exc:  # noqa: BLE001 -- top-level guard: never fail silently or partially.
        sys.stderr.write(f'md2x: toc-preprocess.py failed: {exc}\n')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

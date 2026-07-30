#!/usr/bin/env bats
#
# Deliberate convention deviation: every other bats file in this suite exercises the
# built 'bin/md2x' (see 'harness-smoke.bats' and friends). This file invokes the
# checked-in 'src/cli/lib/toc-preprocess.py' directly with the system 'python3'
# instead, because the slug algorithm needs case-level coverage (a 29-row corpus,
# heading-recognition edge cases, block-state tracking) that would be unreadable and
# slow driven through a full CLI conversion. Integration through the CLI -- wiring
# this script into 'generate-page.sh' -- is
# 'plan/phase-01-markdown-toc-generation/004-wire-preprocessor-into-generate-page.md's
# concern, not this file's.
#
# This intentionally does NOT call 'md2x_setup' (it installs stub pandoc/gs/pdftk on a
# restricted PATH this file has no use for). Local setup/teardown below, in the style
# of 'real-toolchain-e2e.bats''s 'e2e_setup', gives each case a private temp working
# directory outside the repository while leaving the ambient PATH (and its system
# 'python3') untouched -- see this task's '## Assumptions' for why that is expected to
# resolve 'python3' on both macOS and Linux.
#
# Fixture texts throughout are drawn from, and checked against,
# 'plan/notes/pandoc-gfm-slug-algorithm.md' (the slug corpus and heading-recognition
# table) and 'plan/notes/toc-defaults-and-page-heuristic.md' (marker syntax,
# placement, the document-title/section-count rules, and the calibrated estimator).

load '../helpers/common'

TOC_SCRIPT="${MD2X_REPO_ROOT}/src/cli/lib/toc-preprocess.py"

setup() {
  toc_setup
}

teardown() {
  toc_teardown
}

# --- local setup/teardown -------------------------------------------------------------

toc_setup() {
  if ! [[ -f "${TOC_SCRIPT}" ]]; then
    md2x_fail "toc-preprocess.py not found at '${TOC_SCRIPT}'"
    return 1
  fi

  TOC_TEST_ORIGINAL_DIR="${PWD}"

  local tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  TOC_TEST_TMPDIR="$(mktemp -d "${tmp_root}/md2x-toc-test.XXXXXX")"
  cd "${TOC_TEST_TMPDIR}"
}

toc_teardown() {
  cd "${TOC_TEST_ORIGINAL_DIR:-/}" 2>/dev/null || cd /
  if [[ -n "${TOC_TEST_TMPDIR:-}" ]] \
     && [[ "${TOC_TEST_TMPDIR}" == */md2x-toc-test.* ]] \
     && [[ -d "${TOC_TEST_TMPDIR}" ]]; then
    rm -rf "${TOC_TEST_TMPDIR}"
  fi
  unset TOC_TEST_TMPDIR TOC_TEST_ORIGINAL_DIR
}

# --- running the script ----------------------------------------------------------------

# toc_run <mode> <<'EOF' ... EOF
# Runs 'toc-preprocess.py --mode <mode>', feeding stdin from whatever the caller
# attaches to the invocation (a here-doc, in every case below). Sets $status,
# $output and $stderr like 'common.bash''s 'md2x_run'. $output has any trailing
# newline stripped by command substitution -- fine for the substring/ordering
# assertions used throughout, but NOT for exact byte-identity checks (see
# 'toc_run_file' and the pass-through fidelity case, which compare files directly).
toc_run() {
  local mode="$1" stdout_file stderr_file
  stdout_file="${TOC_TEST_TMPDIR}/toc-stdout"
  stderr_file="${TOC_TEST_TMPDIR}/toc-stderr"

  status=0
  python3 "${TOC_SCRIPT}" --mode "${mode}" > "${stdout_file}" 2> "${stderr_file}" || status=$?

  output="$(cat -- "${stdout_file}")"
  stderr="$(cat -- "${stderr_file}")"
}

# toc_run_file <mode> <input-file>
# Same as 'toc_run', but reads stdin from a file instead of an attached here-doc --
# used when the fixture is built programmatically (the slug corpus, and documents
# padded to an exact line count for the page-estimate boundary cases).
toc_run_file() {
  local mode="$1" input_file="$2" stdout_file stderr_file
  stdout_file="${TOC_TEST_TMPDIR}/toc-stdout"
  stderr_file="${TOC_TEST_TMPDIR}/toc-stderr"

  status=0
  python3 "${TOC_SCRIPT}" --mode "${mode}" < "${input_file}" > "${stdout_file}" 2> "${stderr_file}" \
    || status=$?

  output="$(cat -- "${stdout_file}")"
  stderr="$(cat -- "${stderr_file}")"
}

# toc_write_padded_doc <filler-blank-lines> <path>
# Writes a 4-section document (10 non-filler lines: title + 4 x heading/blank pairs)
# padded with the given number of trailing blank lines, for exercising the
# page-estimate line-count boundary precisely (each blank line contributes exactly 1
# to the estimator's line total -- see 'plan/notes/toc-defaults-and-page-heuristic.md').
toc_write_padded_doc() {
  local filler="$1" path="$2"
  {
    printf '# Doc Title\n\n'
    local n
    for n in 0 1 2 3; do
      printf '## Section %s\n\n' "${n}"
    done
    local i
    for ((i = 0; i < filler; i++)); do
      printf '\n'
    done
  } > "${path}"
}

# toc_line_of <needle>
# Prints the 1-based line number of the first line in $output containing <needle>
# literally, for placement-ordering assertions.
toc_line_of() {
  printf '%s\n' "${output}" | grep -n -F -- "$1" | head -n1 | cut -d: -f1
}

# --- 1. slug corpus ----------------------------------------------------------------------

@test "toc: slug corpus reproduces the 29-row identifier table in order, TOC forced on" {
  # Verbatim from 'plan/notes/pandoc-gfm-slug-algorithm.md''s "Verified corpus" table.
  local -a headings=(
    'Simple Heading'
    '1. Numbered Section'
    'Hello, World! (Again)'
    'Hello, World! (Again)'
    'Café Déjà-Vu'
    'snake_case and dash-case'
    'A/B testing & "quotes"'
    '2026 Roadmap'
    'Multi   internal   spaces'
    '`code` in heading'
    '**bold** and _em_'
    '-- leading dashes'
    'Simple Heading'
    'Heading with [a link](http://x.com) inside'
    'C++ & C# notes'
    '50% off — dashes and em-dash'
    'foo.bar.baz'
    'The `--no-toc` flag'
    'Ünïcödé Ⅻ Roman'
    '!!!'
    '...'
    '   '
    'under_score_only'
    '_leading emphasis_ text'
    'trailing text _emph_'
    'API (v2.0) — Reference'
    "$(printf 'Tab\tseparated')"
    '"Quoted Heading"'
    '$variable and #hash'
  )
  local -a expected=(
    'simple-heading'
    '1-numbered-section'
    'hello-world-again'
    'hello-world-again-1'
    'café-déjà-vu'
    'snake_case-and-dash-case'
    'ab-testing--quotes'
    '2026-roadmap'
    'multi-internal-spaces'
    'code-in-heading'
    'bold-and-em'
    '---leading-dashes'
    'simple-heading-1'
    'heading-with-a-link-inside'
    'c--c-notes'
    '50-off--dashes-and-em-dash'
    'foobarbaz'
    'the---no-toc-flag'
    'ünïcödé-ⅻ-roman'
    ''
    '-1'
    '-2'
    'under_score_only'
    'leading-emphasis-text'
    'trailing-text-emph'
    'api-v20--reference'
    'tab-separated'
    'quoted-heading'
    'variable-and-hash'
  )

  local doc_file="${TOC_TEST_TMPDIR}/corpus.md"
  {
    printf '# Corpus\n\n'
    local h
    for h in "${headings[@]}"; do
      printf '## %s\n\n' "${h}"
    done
  } > "${doc_file}"

  toc_run_file on "${doc_file}"
  assert_success

  # The 20th row ('!!!') is the only one whose final slug is empty -- omitted from the
  # TOC entirely, per 'plan/notes/pandoc-gfm-slug-algorithm.md''s "Empty identifiers".
  local -a want=()
  local i
  for i in "${!expected[@]}"; do
    [[ -n "${expected[i]}" ]] && want+=("${expected[i]}")
  done

  local -a got=()
  local line
  while IFS= read -r line; do
    got+=("${line}")
  done < <(printf '%s\n' "${output}" | grep -oE '\]\(#[^)]*\)' | sed -E 's/^\]\(#//; s/\)$//')

  assert_equal "${#got[@]}" "${#want[@]}" 'TOC entry count'
  for i in "${!want[@]}"; do
    assert_equal "${got[i]:-<missing>}" "${want[i]}" "entry ${i} ('${headings[i]}')"
  done
}

# --- 2. recognition table -----------------------------------------------------------------

@test "toc: recognition - a heading-like line inside a fenced code block is not a heading" {
  toc_run on <<'EOF'
# Doc Title

## Real Section

```
## Not A Real Heading
```
EOF
  assert_success
  assert_output_contains '- [Real Section](#real-section)'
  refute_output_contains '(#not-a-real-heading)'
  assert_output_contains '## Not A Real Heading'
}

@test "toc: recognition - a heading-like line indented 4+ spaces is not a heading" {
  toc_run on <<'EOF'
# Doc Title

## Real Section

    ## Not A Real Heading

## Another Section
EOF
  assert_success
  assert_output_contains '- [Real Section](#real-section)'
  assert_output_contains '- [Another Section](#another-section)'
  refute_output_contains '(#not-a-real-heading)'
  assert_output_contains '    ## Not A Real Heading'
}

@test "toc: recognition - '#NoSpaceHash' (no space after the hash run) is not a heading" {
  toc_run on <<'EOF'
# Doc Title

## Real Section

#NoSpaceHash

## Another Section
EOF
  assert_success
  refute_output_contains '(#nospacehash)'
  assert_output_contains '#NoSpaceHash'
}

@test "toc: recognition - seven '#' characters is not a heading" {
  toc_run on <<'EOF'
# Doc Title

## Real Section

####### Seven Hashes

## Another Section
EOF
  assert_success
  refute_output_contains '(#seven-hashes)'
  assert_output_contains '####### Seven Hashes'
}

@test "toc: recognition - a trailing '#' run is stripped from the heading text" {
  toc_run on <<'EOF'
# Doc Title

## Trailing hashes ##
EOF
  assert_success
  assert_output_contains '- [Trailing hashes](#trailing-hashes)'
}

@test "toc: recognition - a setext '=' heading (level 1) is recognized" {
  toc_run on <<'EOF'
Section One
===========

Section Two
===========
EOF
  assert_success
  assert_output_contains '- [Section One](#section-one)'
  assert_output_contains '- [Section Two](#section-two)'
}

@test "toc: recognition - a setext '-' heading (level 2) is recognized" {
  toc_run on <<'EOF'
# Doc Title

Section One
-----------

Body text.
EOF
  assert_success
  refute_output_contains '- [Doc Title]'
  assert_output_contains '- [Section One](#section-one)'
}

@test "toc: recognition - a heading-like line inside a multi-line HTML comment is not a heading" {
  toc_run on <<'EOF'
# Doc Title

<!--
## Hidden Heading
-->

## Visible Section
EOF
  assert_success
  refute_output_contains '(#hidden-heading)'
  assert_output_contains '- [Visible Section](#visible-section)'
  assert_output_contains '## Hidden Heading'
}

# --- 3. marker handling --------------------------------------------------------------------

@test "toc: marker - a single marker is expanded in place" {
  toc_run on <<'EOF'
# Doc Title

## Section One

<!-- md2x:toc -->

## Section Two
EOF
  assert_success
  assert_output_contains '- [Section One](#section-one)'
  refute_output_contains 'md2x:toc'
}

@test "toc: marker - a second marker is removed and a stderr notice is printed" {
  toc_run on <<'EOF'
# Doc Title

<!-- md2x:toc -->

## Section One

<!-- md2x:toc -->

## Section Two
EOF
  assert_success
  refute_output_contains 'md2x:toc'
  assert_stderr_contains "found 2 'md2x:toc' markers; expanded the first and removed the rest."
}

@test "toc: marker - a marker inside a code fence is left untouched and not an insertion point" {
  toc_run on <<'EOF'
# Doc Title

```
<!-- md2x:toc -->
```

## Section One
EOF
  assert_success
  assert_output_contains '<!-- md2x:toc -->'
  assert_output_contains '- [Section One](#section-one)'
}

@test "toc: marker - the marker is removed under --mode off" {
  toc_run off <<'EOF'
# Doc Title

<!-- md2x:toc -->

## Section One
EOF
  assert_success
  refute_output_contains 'md2x:toc'
  refute_output_contains '- ['
}

# --- 4. placement --------------------------------------------------------------------------

@test "toc: placement - with a document title, the TOC lands after it, not before" {
  toc_run on <<'EOF'
# Doc Title

Intro text.

## Section One

## Section Two
EOF
  assert_success
  local title_line toc_line
  title_line="$(toc_line_of '# Doc Title')"
  toc_line="$(toc_line_of '- [Section One]')"
  [[ -n "${title_line}" ]] || md2x_fail 'title line not found in output'
  [[ -n "${toc_line}" ]] || md2x_fail 'TOC entry not found in output'
  [[ "${toc_line}" -gt "${title_line}" ]] \
    || md2x_fail "expected TOC (line ${toc_line}) after the title (line ${title_line})"
}

@test "toc: placement - without a document title, the TOC lands at the top" {
  toc_run on <<'EOF'
## Section One

## Section Two
EOF
  assert_success
  local toc_line section_line
  toc_line="$(toc_line_of '- [Section One]')"
  section_line="$(toc_line_of '## Section One')"
  [[ -n "${toc_line}" ]] || md2x_fail 'TOC entry not found in output'
  [[ -n "${section_line}" ]] || md2x_fail 'section heading not found in output'
  [[ "${toc_line}" -lt "${section_line}" ]] \
    || md2x_fail "expected TOC (line ${toc_line}) before the heading (line ${section_line})"
}

@test "toc: placement - a marker wins over both the title-default and top-of-document defaults" {
  toc_run on <<'EOF'
# Doc Title

Intro text.

## Section One

<!-- md2x:toc -->

## Section Two
EOF
  assert_success
  local title_line section_one_line toc_line section_two_line
  title_line="$(toc_line_of '# Doc Title')"
  section_one_line="$(toc_line_of '## Section One')"
  toc_line="$(toc_line_of '- [Section One]')"
  section_two_line="$(toc_line_of '## Section Two')"
  [[ -n "${toc_line}" ]] || md2x_fail 'TOC entry not found in output'
  [[ "${toc_line}" -gt "${title_line}" ]] \
    || md2x_fail 'TOC should land after the title'
  [[ "${toc_line}" -gt "${section_one_line}" ]] \
    || md2x_fail 'TOC should land at the marker (after Section One), not the title-default position'
  [[ "${toc_line}" -lt "${section_two_line}" ]] \
    || md2x_fail 'TOC should land at the marker, before Section Two'
  refute_output_contains 'md2x:toc'
}

# --- 5. heuristic boundaries -----------------------------------------------------------------

@test "toc: heuristic - 4+ top-level sections but 2 estimated pages or fewer yields no TOC" {
  toc_run auto <<'EOF'
# Doc Title

## Section One

## Section Two

## Section Three

## Section Four
EOF
  assert_success
  refute_output_contains '- ['
}

@test "toc: heuristic - more than 2 estimated pages but only 3 top-level sections yields no TOC" {
  local doc_file="${TOC_TEST_TMPDIR}/three-sections.md"
  {
    printf '# Doc Title\n\n'
    local n
    for n in One Two Three; do
      printf '## Section %s\n\n' "${n}"
    done
    local i
    for ((i = 0; i < 100; i++)); do
      printf '\n'
    done
  } > "${doc_file}"

  toc_run_file auto "${doc_file}"
  assert_success
  refute_output_contains '- ['
}

@test "toc: heuristic - more than 2 estimated pages and 4+ top-level sections yields a TOC" {
  local doc_file="${TOC_TEST_TMPDIR}/four-sections.md"
  {
    printf '# Doc Title\n\n'
    local n
    for n in One Two Three Four; do
      printf '## Section %s\n\n' "${n}"
    done
    local i
    for ((i = 0; i < 100; i++)); do
      printf '\n'
    done
  } > "${doc_file}"

  toc_run_file auto "${doc_file}"
  assert_success
  assert_output_contains '- [Section One](#section-one)'
}

@test "toc: heuristic - exactly 90 estimated rendered lines yields no TOC" {
  local doc_file="${TOC_TEST_TMPDIR}/boundary-90.md"
  toc_write_padded_doc 80 "${doc_file}"
  toc_run_file auto "${doc_file}"
  assert_success
  refute_output_contains '- ['
}

@test "toc: heuristic - 91 estimated rendered lines yields a TOC" {
  local doc_file="${TOC_TEST_TMPDIR}/boundary-91.md"
  toc_write_padded_doc 81 "${doc_file}"
  toc_run_file auto "${doc_file}"
  assert_success
  assert_output_contains '- [Section 0](#section-0)'
}

@test "toc: heuristic - a document with no headings never gets a TOC" {
  toc_run auto <<'EOF'
Just some body text.

More body text, no headings at all.
EOF
  assert_success
  refute_output_contains '- ['
}

@test "toc: heuristic - a marker in an otherwise-small document forces a TOC" {
  toc_run auto <<'EOF'
# Doc Title

<!-- md2x:toc -->

## Section One
EOF
  assert_success
  assert_output_contains '- [Section One](#section-one)'
}

# --- 6. mode overrides ------------------------------------------------------------------------

@test "toc: mode override - --mode on overrides the small-document auto-suppress heuristic" {
  # A lone heading is always the document title (the sole heading at the shallowest
  # level present) and is excluded from the TOC regardless of mode -- see
  # 'plan/notes/toc-defaults-and-page-heuristic.md''s "Document title" -- so this uses
  # the smallest document with a non-title heading to show '--mode on' forcing a TOC
  # that 'auto' would suppress (too few sections, too few estimated pages).
  toc_run on <<'EOF'
# Doc Title
## Section
EOF
  assert_success
  assert_output_contains '- [Section](#section)'
}

@test "toc: mode override - --mode off suppresses a TOC that auto would emit" {
  local doc_file="${TOC_TEST_TMPDIR}/would-auto-toc.md"
  {
    printf '# Doc Title\n\n'
    local n
    for n in One Two Three Four; do
      printf '## Section %s\n\n' "${n}"
    done
    local i
    for ((i = 0; i < 100; i++)); do
      printf '\n'
    done
  } > "${doc_file}"

  toc_run_file auto "${doc_file}"
  assert_success
  assert_output_contains '- [Section One](#section-one)'

  toc_run_file off "${doc_file}"
  assert_success
  refute_output_contains '- ['
}

# --- 7. section counting (the note's five worked examples) ------------------------------------

@test "toc: section counting - one title and six siblings gives 6 sections (README shape)" {
  local doc_file="${TOC_TEST_TMPDIR}/readme-shape.md"
  {
    printf '# md2x\n\n'
    local n
    for n in 1 2 3 4 5 6; do
      printf '## Section %s\n\n' "${n}"
    done
  } > "${doc_file}"

  toc_run_file on "${doc_file}"
  assert_success
  refute_output_contains '- [md2x]'
  local n
  for n in 1 2 3 4 5 6; do
    assert_output_contains "- [Section ${n}](#section-${n})"
  done
}

@test "toc: section counting - one title and eight siblings gives 8 sections (md2x-spec shape)" {
  local doc_file="${TOC_TEST_TMPDIR}/spec-shape.md"
  {
    printf '# md2x Spec\n\n'
    local n
    for n in 1 2 3 4 5 6 7 8; do
      printf '## Section %s\n\n' "${n}"
    done
  } > "${doc_file}"

  toc_run_file on "${doc_file}"
  assert_success
  refute_output_contains '- [md2x Spec]'
  local n
  for n in 1 2 3 4 5 6 7 8; do
    assert_output_contains "- [Section ${n}](#section-${n})"
  done
}

@test "toc: section counting - one #, one ##, one ### gives 1 top-level section (tiny-doc shape)" {
  toc_run on <<'EOF'
# Tiny Doc

## Sole Section

### Sole Subsection
EOF
  assert_success
  refute_output_contains '- [Tiny Doc]'
  assert_output_contains '- [Sole Section](#sole-section)'
  assert_output_contains '  - [Sole Subsection](#sole-subsection)'
}

@test "toc: section counting - three sibling # chapters (no title) gives 3 top-level sections" {
  toc_run on <<'EOF'
# Chapter One

# Chapter Two

# Chapter Three
EOF
  assert_success
  assert_output_contains '- [Chapter One](#chapter-one)'
  assert_output_contains '- [Chapter Two](#chapter-two)'
  assert_output_contains '- [Chapter Three](#chapter-three)'
  refute_output_contains '  - ['
}

@test "toc: section counting - a document with no headings has 0 top-level sections" {
  toc_run on <<'EOF'
Body text only, no headings anywhere in this document.
EOF
  assert_success
  refute_output_contains '- ['
}

# --- 8. pass-through fidelity ------------------------------------------------------------------

@test "toc: pass-through fidelity - --mode off with no marker is byte-identical, CRLF included" {
  # Uses raw files rather than 'toc_run': command substitution ('$(...)', which
  # 'toc_run' uses to capture $output) strips trailing newlines, which would mask a
  # byte-identity regression at the end of the file.
  local input_file="${TOC_TEST_TMPDIR}/crlf-input.md" output_file="${TOC_TEST_TMPDIR}/crlf-output.md"
  printf '# Doc Title\r\n\r\nBody text.\r\n## Section\r\n' > "${input_file}"

  local run_status=0
  python3 "${TOC_SCRIPT}" --mode off < "${input_file}" > "${output_file}" 2> "${TOC_TEST_TMPDIR}/crlf-stderr" \
    || run_status=$?

  [[ "${run_status}" -eq 0 ]] || md2x_fail "expected exit 0, got ${run_status}"
  cmp -s "${input_file}" "${output_file}" \
    || md2x_fail 'output is not byte-identical to input (CRLF line endings)'
}

# --- 9. link-text handling -----------------------------------------------------------------------

@test "toc: link text - a heading containing a Markdown link produces a flattened, non-nested entry" {
  toc_run on <<'EOF'
# Doc Title

## Heading with [a link](http://example.com) inside
EOF
  assert_success
  assert_output_contains '- [Heading with a link inside](#heading-with-a-link-inside)'
}

@test "toc: link text - a heading containing literal brackets produces an escaped entry" {
  toc_run on <<'EOF'
# Doc Title

## Heading with [brackets] literally
EOF
  assert_success
  assert_output_contains '- [Heading with \[brackets\] literally](#heading-with-brackets-literally)'
}

#!/usr/bin/env bats
#
# Link and image handling, end to end against the REAL pandoc: the Lua filter
# 'src/cli/lib/md2x-links.lua' rewrites relative '.md'/'.markdown' links to the output
# format and resolves images against the directory of the source file that contains them
# (including per source under '--single-page'). Skipped, naming what is missing, when
# real pandoc is absent; the PDF cases additionally need md2x's managed WeasyPrint. Gating
# follows 'real-toolchain-e2e.bats'. These cases never use the stub executables.

load '../helpers/common'

setup() {
  li_setup
}

teardown() {
  li_teardown
}

li_setup() {
  if ! [[ -x "${MD2X_BIN}" ]]; then
    md2x_fail "built CLI not found at '${MD2X_BIN}'" "run 'make all' first"
    return 1
  fi
  if [[ ":${PATH}:" == *":${MD2X_STUB_DIR}:"* ]]; then
    md2x_fail "stub directory is on PATH: ${MD2X_STUB_DIR}" 'this file must run against the real toolchain'
    return 1
  fi
  LI_ORIGINAL_DIR="${PWD}"
  local tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  MD2X_TEST_TMPDIR="$(mktemp -d "${tmp_root}/md2x-e2e-test.XXXXXX")"
  MD2X_TEST_WORK_DIR="${MD2X_TEST_TMPDIR}/work"
  mkdir -p "${MD2X_TEST_WORK_DIR}"
  cd "${MD2X_TEST_WORK_DIR}"
}

li_teardown() {
  cd "${LI_ORIGINAL_DIR:-/}" 2>/dev/null || cd /
  if [[ -n "${MD2X_TEST_TMPDIR:-}" ]] && [[ "${MD2X_TEST_TMPDIR}" == */md2x-e2e-test.* ]] \
     && [[ -d "${MD2X_TEST_TMPDIR}" ]]; then
    rm -rf "${MD2X_TEST_TMPDIR}"
  fi
  unset MD2X_TEST_TMPDIR MD2X_TEST_WORK_DIR LI_ORIGINAL_DIR
}

li_require_pandoc() {
  command -v pandoc >/dev/null 2>&1 || skip "real 'pandoc' not found on PATH"
}

li_require_pdf() {
  li_require_pandoc
  [[ -x "${HOME}/.md2x/venv/bin/weasyprint" ]] || skip "md2x's managed WeasyPrint is not installed"
}

# li_png <path>: writes a valid 1x1 PNG.
li_png() {
  mkdir -p "$(dirname "$1")"
  printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==' \
    | python3 -c 'import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' > "$1"
}

# --- links ---------------------------------------------------------------------------------

@test "links: relative .md targets become .html, keeping fragments, ./ and trailing text" {
  li_require_pandoc
  cat > doc.md <<'EOF'
# Doc

[a](a.md) and [b](./sub/b.md#sec) then text, [c](c.markdown) [d](D.MD) [e](E.Markdown#x).

[ref]: g.md
See [ref] and [ref2][r2].

[r2]: ../up/h.md#frag
EOF
  md2x_run -F html -p out doc.md
  assert_success
  local html
  html="$(tr '\n' ' ' < out/doc.html | tr -s ' ')"
  [[ "${html}" == *'href="a.html"'* ]]
  [[ "${html}" == *'href="./sub/b.html#sec"'* ]]
  [[ "${html}" == *'href="c.html"'* ]]
  [[ "${html}" == *'href="D.html"'* ]]
  [[ "${html}" == *'href="E.html#x"'* ]]
  [[ "${html}" == *'href="g.html"'* ]]
  [[ "${html}" == *'href="../up/h.html#frag"'* ]]
  [[ "${html}" != *'././'* ]]
}

@test "links: absolute, URL-scheme and fragment-only targets, code spans and fences are left alone" {
  li_require_pandoc
  cat > doc.md <<'EOF'
# Doc

[abs](/x/a.md) [web](https://example.com/a.md) [mail](mailto:a@b.md) [odd](foo:bar.md) [frag](#top)

`[code](a.md)`

```
[fence](a.md)
```
EOF
  md2x_run -F html -p out doc.md
  assert_success
  local html
  html="$(tr '\n' ' ' < out/doc.html | tr -s ' ')"
  [[ "${html}" == *'href="/x/a.md"'* ]]
  [[ "${html}" == *'href="https://example.com/a.md"'* ]]
  [[ "${html}" == *'href="mailto:a@b.md"'* ]]
  [[ "${html}" == *'href="foo:bar.md"'* ]]
  [[ "${html}" == *'href="#top"'* ]]
  [[ "${html}" == *'[code](a.md)'* ]]
  [[ "${html}" == *'[fence](a.md)'* ]]
}

@test "links: the target format follows -F (docx links point at .docx)" {
  li_require_pandoc
  printf '# Doc\n\n[a](a.md)\n' > doc.md
  md2x_run -F docx -p out doc.md
  assert_success
  unzip -p out/doc.docx word/_rels/document.xml.rels | grep -q 'Target="a.docx"'
}

# --- images --------------------------------------------------------------------------------

@test "images: html resolves against the source directory, relative to the output file (-p mirroring)" {
  li_require_pandoc
  li_png docs/img/p.png
  mkdir -p docs/sub
  printf '# A\n\n![alt](../img/p.png)\n' > docs/sub/a.md
  md2x_run -F html -p out docs
  assert_success
  grep -q 'src="../../docs/img/p.png"' out/sub/a.html
  [[ -f "out/sub/$(sed -n 's/.*src="\([^"]*\)".*/\1/p' out/sub/a.html | head -n 1)" ]]
}

@test "images: html with -o is relative to the -o file's directory" {
  li_require_pandoc
  li_png docs/img/p.png
  printf '# A\n\n![alt](../img/p.png)\n' > docs/a.md
  mkdir -p docs/x
  mv docs/a.md docs/x/a.md
  md2x_run -F html -o build/deep/a.html docs/x/a.md
  assert_success
  grep -q 'src="../../docs/img/p.png"' build/deep/a.html
}

@test "images: --to-stdout html is relative to the cwd" {
  li_require_pandoc
  li_png docs/img/p.png
  mkdir -p docs/x
  printf '# A\n\n![alt](../img/p.png)\n' > docs/x/a.md
  md2x_run -F html --to-stdout docs/x/a.md
  assert_success
  [[ "${output}" == *'src="docs/img/p.png"'* ]]
}

@test "images: stdin resolves against the cwd" {
  li_require_pandoc
  li_png img/p.png
  md2x_run -F html -o out/s.html - <<< $'# S\n\n![alt](img/p.png)'
  assert_success
  grep -q 'src="../img/p.png"' out/s.html
}

@test "images: docx gets the image embedded from the source directory" {
  li_require_pandoc
  li_png docs/img/p.png
  mkdir -p docs/sub
  printf '# A\n\n![alt](../img/p.png)\n' > docs/sub/a.md
  md2x_run -F docx -p out docs/sub/a.md
  assert_success
  [[ -z "${stderr}" ]]
  unzip -l out/a.docx | grep -q 'word/media/'
}

@test "images: pdf embeds the image from the source directory" {
  li_require_pdf
  li_png docs/img/p.png
  mkdir -p docs/sub
  printf '# A\n\n![alt](../img/p.png)\n' > docs/sub/a.md
  md2x_run -F pdf -p out docs/sub/a.md
  assert_success
  [[ "${stderr}" != *'Failed to load image'* ]]
  [[ "${stderr}" != *'could not find image'* ]]
  grep -aq '/Subtype /Image' out/a.pdf
}

@test "images: absolute, URL-scheme and data: targets are left alone" {
  li_require_pandoc
  printf '# A\n\n![a](/nonexistent/p.png) ![b](https://example.com/p.png) ![c](data:image/png;base64,AAAA)\n' > a.md
  md2x_run -F html -p out a.md
  assert_success
  [[ "${stderr}" != *'could not find image'* ]]
  local html
  html="$(cat out/a.html)"
  [[ "${html}" == *'src="/nonexistent/p.png"'* ]]
  [[ "${html}" == *'src="https://example.com/p.png"'* ]]
  [[ "${html}" == *'src="data:image/png;base64,AAAA"'* ]]
}

@test "images: --single-page resolves each source's images against its own directory, and strips markers" {
  li_require_pandoc
  li_png one/img/o.png
  li_png two/img/t.png
  printf '# One\n\n![o](img/o.png)\n' > one/a.md
  printf '# Two\n\n![t](img/t.png)\n' > two/b.md
  md2x_run -F html --single-page -o out/all.html one/a.md two/b.md
  assert_success
  [[ "${stderr}" != *'could not find image'* ]]
  grep -q 'src="../one/img/o.png"' out/all.html
  grep -q 'src="../two/img/t.png"' out/all.html
  ! grep -q 'md2x:source' out/all.html
}

@test "images: a source directory named with spaces and '-->' still resolves, and the marker does not leak" {
  li_require_pandoc
  local dir='we ird --> dir'
  li_png "${dir}/img/p.png"
  printf '# W\n\n![w](img/p.png)\n' > "${dir}/w.md"
  printf '# X\n\ntext\n' > x.md
  md2x_run -F html --single-page -o out/all.html "${dir}/w.md" x.md
  assert_success
  [[ "${stderr}" != *'could not find image'* ]]
  grep -q 'src="[^"]*we%20ird%20--%3E%20dir/img/p.png"' out/all.html
  ! grep -q 'md2x:source' out/all.html
}

@test "images: a forged source marker in a --single-page source cannot redirect images or warnings" {
  li_require_pandoc
  li_png one/img/o.png
  li_png forged/img/o.png
  # The forged marker (no nonce) points at a directory holding a same-named image and claims
  # another source name. The true directory must still win for resolution and attribution.
  printf '# One\n\n<!-- md2x:source-dir=%s source=evil.md -->\n\n![o](img/o.png) ![m](missing.png)\n' \
    "${PWD}/forged" > one/a.md
  printf '# Two\n\nfine\n' > b.md
  md2x_run -F html --single-page -o out/all.html one/a.md b.md
  assert_success
  grep -q 'src="../one/img/o.png"' out/all.html
  ! grep -q 'src="../forged/img/o.png"' out/all.html
  [[ "${stderr}" == *"could not find image 'missing.png' (referenced from one/a.md)"* ]]
  [[ "${stderr}" != *'evil.md'* ]]
}

@test "images: a forged marker that guesses a nonce shape is still ignored" {
  li_require_pandoc
  li_png one/img/o.png
  printf '# One\n\n<!-- md2x:source-dir=/nonexistent source=evil.md nonce=00000000000000000000000000000000 -->\n\n![o](img/o.png)\n' > one/a.md
  printf '# Two\n\nfine\n' > b.md
  md2x_run -F html --single-page -o out/all.html one/a.md b.md
  assert_success
  [[ "${stderr}" != *'could not find image'* ]]
  grep -q 'src="../one/img/o.png"' out/all.html
}

@test "images: the embedded Lua filter is byte-identical to its source file" {
  li_require_pandoc
  printf '# A\n\ntext\n' > a.md
  md2x_run --keep-intermediate -F html -p out a.md
  assert_success
  local kept
  kept="$(md2x_kept_work_dir)"
  [[ -n "${kept}" ]] || md2x_fail "no kept-intermediate notice in stderr: ${stderr}"
  cmp "${kept}/md2x-links.lua" "${BATS_TEST_DIRNAME}/../../lib/md2x-links.lua"
}

@test "images: a missing image warns once per target, names the source, and the run succeeds (html)" {
  li_require_pandoc
  printf '# A\n\n![x](nope.png) ![y](nope.png) ![z](gone.png)\n' > a.md
  md2x_run -F html -p out a.md
  assert_success
  [[ -f out/a.html ]]
  [[ "$(printf '%s\n' "${stderr}" | grep -c "could not find image 'nope.png' (referenced from a.md)")" == 1 ]]
  [[ "$(printf '%s\n' "${stderr}" | grep -c "could not find image 'gone.png' (referenced from a.md)")" == 1 ]]
  [[ "${stderr}" == *'md2x: warning: could not find image'* ]]
}

@test "images: a missing image warns for docx too" {
  li_require_pandoc
  printf '# A\n\n![x](nope.png)\n' > a.md
  md2x_run -F docx -p out a.md
  assert_success
  [[ "$(printf '%s\n' "${stderr}" | grep -c "could not find image 'nope.png' (referenced from a.md)")" == 1 ]]
}

@test "images: a missing image warns for pdf too (WeasyPrint may add its own line)" {
  li_require_pdf
  printf '# A\n\n![x](nope.png)\n' > a.md
  md2x_run -F pdf -p out a.md
  assert_success
  [[ "$(printf '%s\n' "${stderr}" | grep -c "could not find image 'nope.png' (referenced from a.md)")" == 1 ]]
}

@test "images: under --single-page the warning names the source that references the image" {
  li_require_pandoc
  printf '# One\n\nfine\n' > a.md
  mkdir -p sub
  printf '# Two\n\n![x](nope.png)\n' > sub/b.md
  md2x_run -F html --single-page -o out/all.html a.md sub/b.md
  assert_success
  [[ "${stderr}" == *"could not find image 'nope.png' (referenced from sub/b.md)"* ]]
}

@test "images: a missing image from stdin names 'stdin'" {
  li_require_pandoc
  md2x_run -F html -o out/s.html - <<< $'# S\n\n![x](nope.png)'
  assert_success
  [[ "${stderr}" == *"could not find image 'nope.png' (referenced from stdin)"* ]]
}

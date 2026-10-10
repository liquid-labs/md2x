#!/usr/bin/env bash
# CI boundary check: with a pandoc older than md2x's 3.4 floor installed, the built CLI must refuse to run.
# Asserts exit status 3 and the "too old" message on stderr for a tiny markdown file. Expects 'bin/md2x' built
# ('make all') and every tool the CLI checks BEFORE pandoc's version (gs, pandoc, pdftk, python3) on PATH, so the
# failure under test is the pandoc one. Usage: scripts/test-pandoc-too-old.sh <expected pandoc version, e.g. 3.3>
set -euo pipefail

EXPECTED="${1:?usage: test-pandoc-too-old.sh <installed pandoc version, e.g. 3.3>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -x "$ROOT/bin/md2x" ] || { echo "FAIL: $ROOT/bin/md2x not built (run 'make all')" >&2; exit 1; }

INSTALLED="$(pandoc --version | head -n 1)"
[ "$INSTALLED" = "pandoc ${EXPECTED}" ] \
  || { echo "FAIL: installed '${INSTALLED}', expected 'pandoc ${EXPECTED}'" >&2; exit 1; }

printf '# Too old\n' > "$WORK/tiny.md"
STATUS=0
"$ROOT/bin/md2x" --output-format html --output-path "$WORK/out" "$WORK/tiny.md" > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
echo "exit status: $STATUS"
cat "$WORK/stderr"

[ "$STATUS" -eq 3 ] || { echo "FAIL: expected exit status 3, got $STATUS" >&2; exit 1; }
grep -qF "pandoc ${EXPECTED} is too old; md2x requires pandoc >= 3.4" "$WORK/stderr" \
  || { echo "FAIL: stderr lacks the 'pandoc ${EXPECTED} is too old' message" >&2; exit 1; }
[ ! -e "$WORK/out" ] || { echo "FAIL: output was produced despite the refusal" >&2; exit 1; }
echo "test-pandoc-too-old: ok"

#!/usr/bin/env bash
# Release-time check: packs the package, installs the tarball into a fresh temp project, and proves the
# native ESM named import, CJS require, and TypeScript types all work from the packed artifact.
# Run via 'make test-pack'. Needs the built artifacts ('make all'). The tarball install is a local file
# install; the TypeScript check uses the lockfile-pinned devDependency 'node_modules/.bin/tsc' (never a network
# fetch) and fails when it is absent (run 'bun install').
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$ROOT"
npm pack --pack-destination "$WORK" >/dev/null
TARBALL="$(ls "$WORK"/*.tgz)"

echo "== tarball contents =="
LIST="$(tar -tzf "$TARBALL")"
for f in package/LICENSE.txt package/bin/md2x package/dist/md2x.mjs package/dist/md2x.cjs package/dist/index.d.ts package/package.json; do
  grep -qx "$f" <<<"$LIST" || { echo "FAIL: $f missing from tarball" >&2; exit 1; }
  echo "ok  $f"
done

mkdir "$WORK/consumer"
cd "$WORK/consumer"
npm init -y >/dev/null
npm install --offline --no-audit --no-fund "$TARBALL" >/dev/null

CHECK='
const ok = (c, m) => { if (!c) { console.error("FAIL: " + m); process.exit(1) } }
ok(typeof md2x === "function", "md2x is not a function")
ok(typeof md2xAsync === "function", "md2xAsync is not a function")
try { md2x({}); ok(false, "md2x({}) did not throw") }
catch (e) { ok(e instanceof TypeError, "md2x({}) threw " + e) }
// Bin resolution: a real spawn must reach the CLI (numeric exitCode), not fail to locate bin/md2x.
try { md2x({ sources: ["/nonexistent-md2x-input.md"] }); ok(false, "nonexistent source did not throw") }
catch (e) { ok(typeof e.exitCode === "number", "CLI was not reached: " + e.message) }
md2xAsync({}).then(() => ok(false, "md2xAsync({}) did not reject"), (e) => {
  ok(e instanceof TypeError, "md2xAsync({}) rejected with " + e)
  console.log("ok")
})
'

echo "== ESM import =="
node --input-type=module -e "import { md2x, md2xAsync } from '@liquid-labs/md2x'; $CHECK"
echo "== CJS require =="
node -e "const { md2x, md2xAsync } = require('@liquid-labs/md2x'); $CHECK"

echo "== installed bin resolution =="
# Replace the INSTALLED bin with a stub. The wrapper must reach the stub (exit 42 plus the marker); if it resolved the
# CLI from anywhere else (e.g. a build-time absolute path into the repo tree), it would run the real CLI and fail here.
INSTALLED_BIN="$WORK/consumer/node_modules/@liquid-labs/md2x/bin/md2x"
[ -f "$INSTALLED_BIN" ] || { echo "FAIL: $INSTALLED_BIN missing from the installed package" >&2; exit 1; }
printf '#!/bin/sh\necho MD2X_INSTALLED_STUB >&2\nexit 42\n' > "$INSTALLED_BIN"
chmod +x "$INSTALLED_BIN"
STUB_CHECK='
const ok = (c, m) => { if (!c) { console.error("FAIL: " + m); process.exit(1) } }
try { md2x({ sources: ["a.md"] }); ok(false, "stub did not fail") }
catch (e) { ok(e.exitCode === 42 && String(e.stderr).includes("MD2X_INSTALLED_STUB"), "CLI was not resolved from the installed package: " + e.message) }
console.log("ok")
'
node --input-type=module -e "import { md2x } from '@liquid-labs/md2x'; $STUB_CHECK"
node -e "const { md2x } = require('@liquid-labs/md2x'); $STUB_CHECK"
for BUNDLE in node_modules/@liquid-labs/md2x/dist/md2x.mjs node_modules/@liquid-labs/md2x/dist/md2x.cjs; do
  [ -f "$BUNDLE" ] && [ -r "$BUNDLE" ] || { echo "FAIL: installed bundle $BUNDLE is missing or unreadable" >&2; exit 1; }
done
# Both the logical ('pwd') and the physical ('pwd -P') form of the root; grep status 1 is "no match" (good),
# 2 or higher is a grep error and must fail the check rather than read as a pass.
for BUILD_ROOT in "$ROOT" "$(cd "$ROOT" && pwd -P)"; do
  GREP_STATUS=0
  grep -lF -- "$BUILD_ROOT" node_modules/@liquid-labs/md2x/dist/md2x.mjs node_modules/@liquid-labs/md2x/dist/md2x.cjs || GREP_STATUS=$?
  [ "$GREP_STATUS" -eq 1 ] || {
    if [ "$GREP_STATUS" -eq 0 ]; then echo "FAIL: installed bundles embed the build path $BUILD_ROOT" >&2
    else echo "FAIL: grep errored (status $GREP_STATUS) checking for the build path" >&2; fi
    exit 1
  }
done

echo "== TypeScript types =="
cat > consumer.ts <<'TS'
import { md2x, md2xAsync } from '@liquid-labs/md2x'
import type { Md2xOptions, Md2xError } from '@liquid-labs/md2x'

const opts: Md2xOptions = { markdown: '# hi', format: 'html', quiet: true }
const files: string[] = md2x(opts)
const pending: Promise<string[]> = md2xAsync({ sources: ['a.md'], toc: true })
try { md2x({ sources: ['a.md'] }) }
catch (e) { const code: number | undefined = (e as Md2xError).exitCode; void code }
// @ts-expect-error 'markdown' and 'sources' are mutually exclusive
const bad: Md2xOptions = { markdown: 'x', sources: ['a.md'] }
void files; void pending; void bad
TS
TSC_ARGS=(--noEmit --strict --module nodenext --moduleResolution nodenext --target es2022 --skipLibCheck false consumer.ts)
TSC="$ROOT/node_modules/.bin/tsc"
[ -x "$TSC" ] || { echo "FAIL: $TSC not found; pinned TypeScript is not installed (run 'bun install')" >&2; exit 1; }
"$TSC" "${TSC_ARGS[@]}"
echo "ok"
echo "test-pack: all checks passed"

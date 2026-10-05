#!/usr/bin/env bash
# Release-time check: packs the package, installs the tarball into a fresh temp project, and proves the
# native ESM named import, CJS require, and TypeScript types all work from the packed artifact.
# Run via 'make test-pack'. Needs the built artifacts ('make all'). The tarball install is a local file
# install; the TypeScript check uses 'npx --yes -p typescript tsc' only if tsc is not already on the PATH,
# and otherwise degrades to a syntactic check of the .d.ts.
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
if command -v tsc >/dev/null 2>&1; then
  tsc "${TSC_ARGS[@]}"
elif npx --yes -p typescript tsc --version >/dev/null 2>&1; then
  npx --yes -p typescript tsc "${TSC_ARGS[@]}"
else
  echo "TypeScript unavailable; syntactic check of the .d.ts only (node --check cannot parse .d.ts)" >&2
  grep -q 'export function md2xAsync' node_modules/@liquid-labs/md2x/dist/index.d.ts
fi
echo "ok"
echo "test-pack: all checks passed"

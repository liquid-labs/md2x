#!/usr/bin/env node
// Smoke test of the BUILT Node package under the running Node (not bun): loads dist/md2x.cjs with require and
// dist/md2x.mjs with a native ESM import, checks the exports, and runs one real html conversion through each
// (wrapper -> bin/md2x -> pandoc) on a tiny temp file. Run via 'make test-node-dist'; needs 'make all' and the
// CLI's tools (gs, pandoc >= 3.4, pdftk, python3, GNU getopt). Written as .cjs so one file can do both loads.
'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { pathToFileURL } = require('node:url')

const root = path.resolve(__dirname, '..')

function check (label, api, work) {
  assert.equal(typeof api.md2x, 'function', `${label}: md2x is not a function`)
  assert.equal(typeof api.md2xAsync, 'function', `${label}: md2xAsync is not a function`)
  assert.throws(() => api.md2x({}), TypeError, `${label}: md2x({}) should throw a TypeError`)

  const source = path.join(work, `${label}.md`)
  fs.writeFileSync(source, `# Smoke ${label}\n\nHello from Node ${process.version}.\n`)
  const outDir = path.join(work, `out-${label}`)
  const files = api.md2x({ sources: [source], format: 'html', outputPath: outDir, quiet: true })
  assert.ok(Array.isArray(files) && files.length === 1, `${label}: expected one output path, got ${JSON.stringify(files)}`)
  assert.ok(fs.existsSync(files[0]), `${label}: output file ${files[0]} does not exist`)
  assert.match(fs.readFileSync(files[0], 'utf8'), /Hello from Node/, `${label}: output lacks the document text`)
  console.log(`ok  ${label}: ${path.basename(files[0])}`)
}

async function main () {
  console.log(`node ${process.version}`)
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'md2x-node-smoke-'))
  try {
    check('cjs', require(path.join(root, 'dist', 'md2x.cjs')), work)
    check('esm', await import(pathToFileURL(path.join(root, 'dist', 'md2x.mjs')).href), work)
  } finally {
    fs.rmSync(work, { recursive: true, force: true })
  }
  console.log('node-smoke: all checks passed')
}

main().catch((e) => {
  console.error(`FAIL: ${e && e.message ? e.message : e}`)
  process.exit(1)
})

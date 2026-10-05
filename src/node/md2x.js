/**
* md2x converts markdown documents into any format supported by [Pandoc](https://pandoc.org/MANUAL.html#options) by
* driving the md2x CLI as a child process. Arguments are passed as argv arrays; no shell is ever involved.
*
* Known limitation: the returned paths are parsed from the CLI's newline-delimited '--list-files' output, so an output
* path that itself contains a newline is mis-split into several entries.
*/
import { spawn, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import fsPath from 'node:path'

// A first-run WeasyPrint install writes a lot to stderr; the 1 MiB default would turn a successful run into an error.
const MAX_BUFFER = 64 * 1024 * 1024

const BOOLEAN_OPTIONS = ['flattenDirs', 'inferTitle', 'inferVersion', 'noToc', 'toc', 'singlePage', 'quiet']
const STRING_OPTIONS = ['outputPath', 'output', 'title']
const ALLOWED_KEYS = new Set(['markdown', 'sources', 'format', ...BOOLEAN_OPTIONS, ...STRING_OPTIONS])
const FORMATS = ['pdf', 'html', 'docx']

// Resolves md2x's own CLI executable by path, so the wrapper never goes through npx/bunx/PATH (which could fetch and
// run an unpinned package). From the built bundle (dist/md2x.js) the bin is at '../bin/md2x'; from source
// (src/node/md2x.js) it is at '../../bin/md2x'. Uses CJS '__dirname' (bun supports it in ESM source; the cjs bundle
// keeps it).
const resolveBin = () => {
  const candidates = [
    fsPath.join(__dirname, '..', 'bin', 'md2x'),
    fsPath.join(__dirname, '..', '..', 'bin', 'md2x')
  ]
  const found = candidates.find((candidate) => fs.existsSync(candidate))
  if (found === undefined) {
    throw new Error(`Could not locate the md2x CLI executable; looked in: ${candidates.join(', ')}. Run 'make all' to build it.`)
  }
  return found
}

const isNonEmptyString = (value) => typeof value === 'string' && value.length > 0

// Validates the options and builds the child invocation. Throws TypeError (naming the option) before anything spawns.
const buildInvocation = (options) => {
  if (options === null || typeof options !== 'object' || Array.isArray(options)) {
    throw new TypeError("md2x: 'options' must be an object")
  }
  for (const key of Object.keys(options)) {
    if (!ALLOWED_KEYS.has(key)) {
      throw new TypeError(`md2x: unknown option '${key}'`)
    }
  }
  const { markdown, sources, format = 'pdf', toc, noToc, output, outputPath } = options

  for (const key of BOOLEAN_OPTIONS) {
    if (options[key] !== undefined && typeof options[key] !== 'boolean') {
      throw new TypeError(`md2x: option '${key}' must be a boolean`)
    }
  }
  for (const key of STRING_OPTIONS) {
    if (options[key] !== undefined && !isNonEmptyString(options[key])) {
      throw new TypeError(`md2x: option '${key}' must be a non-empty string`)
    }
  }
  if (typeof format !== 'string' || !FORMATS.includes(format.toLowerCase())) {
    throw new TypeError(`md2x: option 'format' must be one of ${FORMATS.join(', ')}`)
  }
  if (toc && noToc) {
    throw new TypeError("md2x: options 'toc' and 'noToc' are mutually exclusive")
  }
  if (output !== undefined && outputPath !== undefined) {
    throw new TypeError("md2x: options 'output' and 'outputPath' are mutually exclusive")
  }
  if (output === '-') {
    throw new TypeError("md2x: option 'output' cannot be '-'; the wrapper returns file paths, not bytes")
  }

  if (markdown !== undefined && typeof markdown !== 'string') {
    throw new TypeError("md2x: option 'markdown' must be a string")
  }
  if (markdown !== undefined && sources !== undefined) {
    throw new TypeError("md2x: options 'markdown' and 'sources' are mutually exclusive")
  }
  if (markdown === undefined) {
    if (sources === undefined) {
      throw new TypeError("md2x: one of 'markdown' or 'sources' is required")
    }
    if (!Array.isArray(sources) || sources.length === 0 || !sources.every(isNonEmptyString)) {
      throw new TypeError("md2x: option 'sources' must be a non-empty array of non-empty strings")
    }
    if (sources.includes('-')) {
      throw new TypeError("md2x: option 'sources' cannot contain '-' (stdin); pass the content as 'markdown' instead")
    }
  }

  const args = ['--list-files', '--output-format', format.toLowerCase()]
  const flags = [
    ['flattenDirs', '--flatten-dirs'],
    ['inferTitle', '--infer-title'],
    ['inferVersion', '--infer-version'],
    ['noToc', '--no-toc'],
    ['toc', '--toc'],
    ['singlePage', '--single-page']
  ]
  for (const [key, flag] of flags) {
    if (options[key] === true) {
      args.push(flag)
    }
  }
  if (options.title !== undefined) {
    args.push('--title', options.title)
  }
  if (outputPath !== undefined) {
    args.push('--output-path', outputPath)
  }
  if (output !== undefined) {
    args.push('-o', output)
  }
  args.push(...(markdown !== undefined ? ['-'] : sources))

  return { args, input : markdown, quiet : options.quiet === true }
}

// Builds the Error for a failed run. 'exitCode' is only set for a genuine non-zero exit; 'cause' carries a spawn error.
const failure = ({ status, stderr, cause }) => {
  if (typeof status === 'number') {
    return Object.assign(new Error(`md2x failed (exit ${status}): ${stderr}`), { exitCode : status, stderr })
  }
  const detail = cause?.message ?? 'terminated by signal'
  return Object.assign(new Error(`md2x could not run: ${detail}`, { cause }), { exitCode : undefined, stderr })
}

const parseFiles = (stdout) => stdout.split('\n').filter((f) => f.length > 0)

const finish = ({ status, stdout, stderr, error }, quiet) => {
  if (error !== undefined || status !== 0) {
    throw failure({ status : error === undefined ? status : undefined, stderr, cause : error })
  }
  if (stderr && !quiet) {
    console.error(stderr)
  }
  return parseFiles(stdout)
}

/**
* Converts markdown to the requested format via the md2x CLI.
* @param {object} options - Either 'markdown' (a string, fed on stdin) or 'sources' (a non-empty array of paths).
* @returns {string[]} The generated file paths. A path containing a newline is mis-split (known limitation).
* @throws {TypeError} On invalid options, before anything is spawned.
* @throws {Error} On failure; carries 'exitCode' (number) and 'stderr' (string) for a non-zero exit.
*/
const md2x = (options) => {
  const { args, input, quiet } = buildInvocation(options)
  const result = spawnSync(resolveBin(), args, {
    input,
    stdio     : [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
    maxBuffer : MAX_BUFFER,
    encoding  : 'utf8'
  })
  return finish({
    status : result.status,
    stdout : result.stdout ?? '',
    stderr : result.stderr ?? '',
    error  : result.error ?? (result.status === null ? new Error(`killed by signal ${result.signal}`) : undefined)
  }, quiet)
}

/**
* Asynchronous 'md2x()': same options and validation, but validation errors reject the returned Promise.
* @param {object} options - See 'md2x()'.
* @returns {Promise<string[]>} The generated file paths.
*/
const md2xAsync = (options) => new Promise((resolve, reject) => {
  const { args, input, quiet } = buildInvocation(options)
  const child = spawn(resolveBin(), args, { stdio : [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'] })
  let stdout = ''
  let stderr = ''
  let settled = false
  const settle = (fn, value) => {
    if (!settled) {
      settled = true
      fn(value)
    }
  }
  child.stdout.setEncoding('utf8')
  child.stderr.setEncoding('utf8')
  child.stdout.on('data', (chunk) => { stdout += chunk })
  child.stderr.on('data', (chunk) => { stderr += chunk })
  // A spawn failure (missing bin) may not be followed by 'close', so reject right away.
  child.on('error', (err) => settle(reject, failure({ stderr, cause : err })))
  if (input !== undefined) {
    // The child may exit before reading all input; that surfaces as EPIPE here and is reported by the exit code.
    child.stdin.on('error', () => {})
    child.stdin.end(input)
  }
  child.on('close', (status, signal) => {
    try {
      settle(resolve, finish({
        status,
        stdout,
        stderr,
        error : status === null ? new Error(`killed by signal ${signal}`) : undefined
      }, quiet))
    }
    catch (err) {
      settle(reject, err)
    }
  })
})

export { md2x, md2xAsync }

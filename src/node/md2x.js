/**
* md2x converts a markdown document into any format supported by [Pandoc](https://pandoc.org/MANUAL.html#options). Once
* the asyncronous workers are updated to support "respond directly if complete within time X". But since it's actually
* pretty fast, even for substantial batch conversions, we just do it synchronously for now.
*/
import fsPath from 'node:path'

import shell from 'shelljs'

shell.config.silent = true
const execOptions = { shell : '/bin/bash' }

// Escapes a value for safe interpolation inside a single-quoted bash argument: close the quote, emit an escaped
// literal quote, reopen the quote. This is the standard POSIX single-quote escape idiom.
const shellQuote = (value) => `'${String(value).replace(/'/g, "'\\''")}'`

const md2x = ({
  markdown,
  format = 'pdf',
  flattenDirs,
  inferTitle,
  inferVersion,
  noToc,
  outputPath,
  title,
  singlePage = false,
  sources
}) => {
  const sourceSpec = sources ? sources.map(shellQuote).join(' ') : '' // will generate file below; see note on bugginess
  if (!title && sourceSpec === "'-'") {
    title = 'Report'
  }
  if (!title && markdown !== undefined) {
    title = 'Report'
  }
  const options = ['--list-files', `--output-format ${format}`]
  if (flattenDirs) {
    options.push('--flatten-dirs')
  }
  if (inferTitle) {
    options.push('--infer-title')
  }
  if (inferVersion) {
    options.push('--infer-version')
  }
  if (noToc) {
    options.push('--no-toc')
  }
  if (title) {
    options.push(`--title ${shellQuote(title)}`)
  }
  if (singlePage) {
    options.push('--single-page')
  }
  if (outputPath) {
    options.push(`--output-path ${shellQuote(outputPath)}`)
  }

  const command = `npx md2x ${options.join(' ')} ${sourceSpec}`

  let result
  if (markdown === undefined) { // we're working with a file
    result = shell.exec(command, execOptions)
  }
  else { // we have a string; initially tried to go straight from string to file, but that was causing problems:
    // shell.ShellString(markdown).exec(command, execOptions) was causing all leading spaces to be lost for some reason
    // testing with 'node -e 'const shell = require("shelljs"); console.log(shell.ShellString("  foo\n  bar").cat().toString())' looked OK, so the problem is with pandoc maybe?
    const stagingDir = fsPath.join(shell.tempdir(), 'md2x', (Math.random() + '').slice(2))
    shell.mkdir('-p', stagingDir)
    const stagingFile = fsPath.join(stagingDir, `${title}.md`)
    shell.ShellString(markdown).to(stagingFile)
    try {
      result = shell.exec(command + ' ' + shellQuote(stagingFile), execOptions)
    }
    finally { shell.rm('-r', stagingDir) }// cleanup
  }

  if (result.code !== 0) {
    throw new Error(`Could not covert file to '${format}': (${result.code}) ${result.stderr}`)
  }
  else if (result.stderr) {
    console.error(result.stderr)
  }

  return result.toString().split('\n').filter((f) => f.length > 0)
}

export { md2x }

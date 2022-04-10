/**
* md2x converts a markdown document into any format supported by [Pandoc](https://pandoc.org/MANUAL.html#options). Once
* the asyncronous workers are updated to support "respond directly if complete within time X". But since it's actually
* pretty fast, even for substantial batch conversions, we just do it synchronously for now.
*/
import shell from 'shelljs'

shell.config.silent = true
const execOptions = { shell: '/bin/bash' }

const md2x = ({ markdown, format = 'pdf', outputPath, preserveDirectoryStructure, title, singlePage = false, sources }) => {
  const sourceSpec = `${sources ? `'${sources.join("' '")}'` : '-'}`
  if (!title && sourceSpec === '-') {
    title = 'Report'
  }
  const options = ['--list-files', `--output-format ${format}`]
  if (title) {
    options.push(`--title '${title}'`)
  }
  if (singlePage) {
    options.push('--single-page')
  }
  if (outputPath) {
    options.push(`--output-path '${outputPath}'`)
  }
  if (preserveDirectoryStructure) {
    options.push('--preserve-directory-structure')
  }
  
  const command = `npm bin >&2; $(npm bin)/md2x ${options.join(' ')} ${sourceSpec}`
  
  const result = markdown
    ? shell.ShellString(markdown)
      .exec(command, execOptions)
    : shell.exec(command, execOptions)

  if (result.code !== 0) {
    throw new Error(`Could not covert file to '${format}': (${result.code}) ${result.stderr}`)
  }
  else if (result.stderr) {
    console.error(result.stderr)
  }

  return result.toString().split('\n').filter((f) => f.length > 0)
}

export { md2x }

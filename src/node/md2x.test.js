import { afterEach, beforeEach, describe, expect, jest, mock, test } from 'bun:test'
import fs from 'node:fs'
import os from 'node:os'
import fsPath from 'node:path'

// Manual factory mock: shelljs is CommonJS, imported as a default import, and mutated at module load
// (`shell.config.silent = true` in md2x.js). Bun does not hoist `mock.module` above static imports, so the mock is
// registered first and both `shelljs` and the module under test are loaded afterward with top-level dynamic
// `import()`. The factory nests the mock surface under `default` to satisfy the default-import interop.
mock.module('shelljs', () => ({
  default : {
    config      : {},
    exec        : jest.fn(),
    ShellString : jest.fn()
  }
}))

const { default : shell } = await import('shelljs')
const { md2x } = await import('./md2x')

// The repo bin/md2x is a gitignored build output, so 'fs.existsSync' is stubbed to report only this path as present.
const BIN_PATH = fsPath.join(import.meta.dir, '..', '..', 'bin', 'md2x')
const STAGING_DIR = '/tmp/md2x-AbC123'
const BIN = `'${BIN_PATH}'` // shellQuote(BIN_PATH); the path contains no single quotes

// Builds a fake shelljs 'exec' result: 'code'/'stderr' as plain properties (md2x.js reads them directly) and
// 'toString()' standing in for shelljs' ShellString-like stdout accessor.
const mockExecResult = (code, stdout = '', stderr = '') => ({
  code,
  stderr,
  toString : () => stdout
})

describe('md2x', () => {
  let shellStringTo
  let existsSpy
  let mkdtempSpy
  let rmSpy

  beforeEach(() => {
    jest.clearAllMocks()
    existsSpy = jest.spyOn(fs, 'existsSync').mockImplementation((path) => path === BIN_PATH)
    shell.exec.mockReturnValue(mockExecResult(0))
    mkdtempSpy = jest.spyOn(fs, 'mkdtempSync').mockReturnValue(STAGING_DIR)
    rmSpy = jest.spyOn(fs, 'rmSync').mockImplementation(() => {})
    shellStringTo = jest.fn()
    shell.ShellString.mockReturnValue({ to : shellStringTo })
  })

  test('is exported as a function', () => {
    expect(typeof md2x).toBe('function')
  })

  afterEach(() => {
    existsSpy.mockRestore()
  })

  describe('bin resolution', () => {
    test('invokes the resolved bin path directly, never via npx/bunx', () => {
      md2x({ sources : ['a.md'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command.startsWith(`${BIN} `)).toBe(true)
      expect(command).not.toMatch(/\b(npx|bunx)\b/)
    })

    test('throws a clear error, without executing anything, when no bin can be found', () => {
      existsSpy.mockImplementation(() => false)

      expect(() => md2x({ sources : ['a.md'] })).toThrow(/Could not locate the md2x CLI executable/)
      expect(shell.exec).not.toHaveBeenCalled()
    })
  })

  describe('argument marshaling', () => {
    test('applies only the always-on flags and the default output format when no options are set', () => {
      md2x({ sources : ['a.md'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' 'a.md'`)
    })

    test('honors a non-default output format', () => {
      md2x({ sources : ['a.md'], format : 'html' })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'html' 'a.md'`)
    })

    test.each([
      ['flattenDirs', '--flatten-dirs'],
      ['inferTitle', '--infer-title'],
      ['inferVersion', '--infer-version'],
      ['noToc', '--no-toc'],
      ['toc', '--toc'],
      ['singlePage', '--single-page']
    ])('adds %s as %s, and only that flag, when set', (option, flag) => {
      md2x({ sources : ['a.md'], [option] : true })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' ${flag} 'a.md'`)
    })

    test('single-quotes title and output path and places them in source order', () => {
      md2x({ sources : ['a.md'], title : 'My Report', outputPath : './out dir' })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(
        `${BIN} --list-files --output-format 'pdf' --title 'My Report' --output-path './out dir' 'a.md'`
      )
    })

    test('space-joins and single-quotes each of multiple sources', () => {
      md2x({ sources : ['a.md', 'b.md', 'c dir/d.md'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' 'a.md' 'b.md' 'c dir/d.md'`)
    })

    // followup GuQR: '[]' is truthy, so 'sources: []' still takes the truthy branch of
    // 'sources ? sources.map(shellQuote).join(' ') : ''', but '[].map(shellQuote).join(' ')' itself evaluates to
    // '', the same empty sourceSpec the falsy branch would produce. So no positional source argument is emitted at
    // all -- not a single empty-quoted "''" argument. Confirms the command ends with a bare trailing space and
    // carries zero positional source args.
    test('emits zero positional source args for an empty sources array (followup GuQR, locked in)', () => {
      md2x({ sources : [] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' `)
      expect(command.endsWith("''")).toBe(false)
    })

    // 'sourceSpec' is built by escaping and single-quoting each source individually and space-joining the result,
    // so a lone '-' source becomes the quoted string "'-'". The default-title check compares against that quoted
    // form, so the 'Report' default applies for a lone '-' (stdin) source.
    test('applies the default title for a lone "-" source (followup udVi, fixed)', () => {
      md2x({ sources : ['-'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' --title 'Report' '-'`)
    })

    // followup arUf: title/outputPath/sources are caller-supplied and were previously interpolated into raw
    // single quotes with no escaping, so an embedded single quote could break out of the quoted span and inject
    // arbitrary shell syntax. These cases assert the escaping helper closes that off: an embedded quote is
    // rendered as the standard POSIX escape "'\''", which keeps the value safely inside its own quoted span and
    // cannot terminate it early.
    test('escapes an embedded single quote in title so it cannot break out of its quoted span', () => {
      md2x({ sources : ['a.md'], title : "O'Brien's Report" })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(
        `${BIN} --list-files --output-format 'pdf' --title 'O'\\''Brien'\\''s Report' 'a.md'`
      )
    })

    test('escapes an embedded single quote in format so it cannot break out of its quoted span', () => {
      md2x({ sources : ['a.md'], format : "pdf'; touch /tmp/pwned; '" })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(
        `${BIN} --list-files --output-format 'pdf'\\''; touch /tmp/pwned; '\\''' 'a.md'`
      )
    })

    test('escapes an embedded single quote in outputPath so it cannot break out of its quoted span', () => {
      md2x({ sources : ['a.md'], outputPath : "./out'; touch /tmp/pwned; '" })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(
        `${BIN} --list-files --output-format 'pdf' --output-path './out'\\''; touch /tmp/pwned; '\\''' 'a.md'`
      )
    })

    test('escapes an embedded single quote in one sources entry without affecting adjacent entries', () => {
      md2x({ sources : ["a'.md", 'b.md'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' 'a'\\''.md' 'b.md'`)
    })
  })

  describe('return value', () => {
    test('splits stdout on newlines and drops empty entries', () => {
      shell.exec.mockReturnValue(mockExecResult(0, '/out/a.pdf\n\n/out/b.pdf\n'))

      const files = md2x({ sources : ['a.md'] })

      expect(files).toEqual(['/out/a.pdf', '/out/b.pdf'])
    })
  })

  describe('error propagation', () => {
    test('throws an Error carrying the exit code and stderr on non-zero exit', () => {
      shell.exec.mockReturnValue(mockExecResult(1, '', 'pandoc: missing binary'))

      expect(() => md2x({ sources : ['a.md'] }))
        .toThrow("Could not covert file to 'pdf': (1) pandoc: missing binary")
    })
  })

  describe('non-fatal stderr', () => {
    let errorSpy

    beforeEach(() => {
      errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
    })

    afterEach(() => {
      errorSpy.mockRestore()
    })

    test('returns normally and forwards stderr to console.error when the exit code is 0', () => {
      shell.exec.mockReturnValue(mockExecResult(0, '/out/a.pdf\n', 'a warning'))

      const files = md2x({ sources : ['a.md'] })

      expect(files).toEqual(['/out/a.pdf'])
      expect(errorSpy).toHaveBeenCalledWith('a warning')
    })
  })

  describe('markdown staging path', () => {
    test('stages the markdown string, appends the staging file to the command, and cleans up on success', () => {
      shell.exec.mockReturnValue(mockExecResult(0, '/out/Title.pdf\n'))

      const files = md2x({ markdown : '# Hello', title : 'Title' })

      expect(mkdtempSpy).toHaveBeenCalledTimes(1)
      expect(mkdtempSpy).toHaveBeenCalledWith(fsPath.join(os.tmpdir(), 'md2x-'))

      const stagingFile = fsPath.join(STAGING_DIR, 'input.md')
      expect(shell.ShellString).toHaveBeenCalledWith('# Hello')
      expect(shellStringTo).toHaveBeenCalledWith(stagingFile)

      const [command] = shell.exec.mock.calls[0]
      // Two spaces separate the last flag from the staging file: one from the empty 'sourceSpec', one from the append.
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' --title 'Title'  '${stagingFile}'`)

      expect(rmSpy).toHaveBeenCalledTimes(1)
      expect(rmSpy).toHaveBeenCalledWith(STAGING_DIR, { recursive : true, force : true })
      expect(files).toEqual(['/out/Title.pdf'])
    })

    test('never derives the staging path from a path-traversal title', () => {
      shell.exec.mockReturnValue(mockExecResult(0, '/out/esc.pdf\n'))

      md2x({ markdown : '# Hello', title : '../esc' })

      const stagingFile = fsPath.join(STAGING_DIR, 'input.md')
      expect(shellStringTo).toHaveBeenCalledWith(stagingFile)
      const [command] = shell.exec.mock.calls[0]
      expect(command.endsWith(` '${stagingFile}'`)).toBe(true)
      expect(command).toContain("--title '../esc'")
      expect(command.replace("--title '../esc'", '')).not.toContain('esc')
    })

    test('keeps the staging file as input.md and escapes an embedded single quote in title', () => {
      shell.exec.mockReturnValue(mockExecResult(0, "/out/O'Brien.pdf\n"))

      const files = md2x({ markdown : '# Hello', title : "O'Brien" })

      const stagingFile = fsPath.join(STAGING_DIR, 'input.md')
      expect(shellStringTo).toHaveBeenCalledWith(stagingFile)

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`${BIN} --list-files --output-format 'pdf' --title 'O'\\''Brien'  '${stagingFile}'`)

      expect(files).toEqual(["/out/O'Brien.pdf"])
    })

    test('cleans up the staging directory even when the command fails (finally)', () => {
      shell.exec.mockReturnValue(mockExecResult(1, '', 'boom'))

      expect(() => md2x({ markdown : '# Hello', title : 'Title' })).toThrow()

      expect(rmSpy).toHaveBeenCalledTimes(1)
      expect(rmSpy).toHaveBeenCalledWith(STAGING_DIR, { recursive : true, force : true })
    })

    test('still passes --title Report when no title is given, with the fixed staging file name', () => {
      shell.exec.mockReturnValue(mockExecResult(0, '/out/Report.pdf\n'))

      md2x({ markdown : '# Hello' })

      expect(shellStringTo).toHaveBeenCalledWith(fsPath.join(STAGING_DIR, 'input.md'))
      expect(shell.exec.mock.calls[0][0]).toContain("--title 'Report'")
    })

    test('does not use Math.random', () => {
      const randomSpy = jest.spyOn(Math, 'random')
      shell.exec.mockReturnValue(mockExecResult(0))

      md2x({ markdown : '# Hello', title : 'T' })

      expect(randomSpy).not.toHaveBeenCalled()
      randomSpy.mockRestore()
    })
  })
})

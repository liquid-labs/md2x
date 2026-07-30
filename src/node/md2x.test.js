/* global afterEach beforeEach describe expect jest test */
import fsPath from 'node:path'
import shell from 'shelljs'
import { md2x } from './md2x'

// Manual factory mock: shelljs is CommonJS, imported as a default import, and mutated at module load
// (`shell.config.silent = true` in md2x.js). Babel's ESM interop resolves the default import to `.default`, so the
// mock must nest its surface under `default` with `__esModule: true`. `jest.mock` calls are hoisted by
// babel-plugin-jest-hoist above the imports above at compile time, so ordering them after the imports here (to
// satisfy `import/first`) does not change when the mock takes effect.
jest.mock('shelljs', () => ({
  __esModule : true,
  default    : {
    config      : {},
    exec        : jest.fn(),
    tempdir     : jest.fn(),
    mkdir       : jest.fn(),
    rm          : jest.fn(),
    ShellString : jest.fn()
  }
}))

// Builds a fake shelljs 'exec' result: 'code'/'stderr' as plain properties (md2x.js reads them directly) and
// 'toString()' standing in for shelljs' ShellString-like stdout accessor.
const mockExecResult = (code, stdout = '', stderr = '') => ({
  code,
  stderr,
  toString : () => stdout
})

describe('md2x', () => {
  let shellStringTo

  beforeEach(() => {
    jest.clearAllMocks()
    shell.exec.mockReturnValue(mockExecResult(0))
    shell.tempdir.mockReturnValue('/tmp')
    shellStringTo = jest.fn()
    shell.ShellString.mockReturnValue({ to : shellStringTo })
  })

  test('is exported as a function', () => {
    expect(typeof md2x).toBe('function')
  })

  describe('argument marshaling', () => {
    test('applies only the always-on flags and the default output format when no options are set', () => {
      md2x({ sources : ['a.md'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe("npx md2x --list-files --output-format pdf 'a.md'")
    })

    test('honors a non-default output format', () => {
      md2x({ sources : ['a.md'], format : 'html' })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe("npx md2x --list-files --output-format html 'a.md'")
    })

    test.each([
      ['flattenDirs', '--flatten-dirs'],
      ['inferTitle', '--infer-title'],
      ['inferVersion', '--infer-version'],
      ['noToc', '--no-toc'],
      ['singlePage', '--single-page']
    ])('adds %s as %s, and only that flag, when set', (option, flag) => {
      md2x({ sources : ['a.md'], [option] : true })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(`npx md2x --list-files --output-format pdf ${flag} 'a.md'`)
    })

    test('single-quotes title and output path and places them in source order', () => {
      md2x({ sources : ['a.md'], title : 'My Report', outputPath : './out dir' })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(
        "npx md2x --list-files --output-format pdf --title 'My Report' --output-path './out dir' 'a.md'"
      )
    })

    test('space-joins and single-quotes each of multiple sources', () => {
      md2x({ sources : ['a.md', 'b.md', 'c dir/d.md'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe("npx md2x --list-files --output-format pdf 'a.md' 'b.md' 'c dir/d.md'")
    })

    // 'sourceSpec' is built by escaping and single-quoting each source individually and space-joining the result,
    // so a lone '-' source becomes the quoted string "'-'". The default-title check compares against that quoted
    // form, so the 'Report' default applies for a lone '-' (stdin) source.
    test('applies the default title for a lone "-" source (followup udVi, fixed)', () => {
      md2x({ sources : ['-'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe("npx md2x --list-files --output-format pdf --title 'Report' '-'")
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
        "npx md2x --list-files --output-format pdf --title 'O'\\''Brien'\\''s Report' 'a.md'"
      )
    })

    test('escapes an embedded single quote in outputPath so it cannot break out of its quoted span', () => {
      md2x({ sources : ['a.md'], outputPath : "./out'; touch /tmp/pwned; '" })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe(
        "npx md2x --list-files --output-format pdf --output-path './out'\\''; touch /tmp/pwned; '\\''' 'a.md'"
      )
    })

    test('escapes an embedded single quote in one sources entry without affecting adjacent entries', () => {
      md2x({ sources : ["a'.md", 'b.md'] })

      const [command] = shell.exec.mock.calls[0]
      expect(command).toBe("npx md2x --list-files --output-format pdf 'a'\\''.md' 'b.md'")
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

      expect(shell.tempdir).toHaveBeenCalledTimes(1)
      expect(shell.mkdir).toHaveBeenCalledTimes(1)
      const [mkdirFlag, stagingDir] = shell.mkdir.mock.calls[0]
      expect(mkdirFlag).toBe('-p')
      expect(stagingDir.startsWith(fsPath.join('/tmp', 'md2x') + fsPath.sep)).toBe(true)

      const stagingFile = fsPath.join(stagingDir, 'Title.md')
      expect(shell.ShellString).toHaveBeenCalledWith('# Hello')
      expect(shellStringTo).toHaveBeenCalledWith(stagingFile)

      const [command] = shell.exec.mock.calls[0]
      // The command template always inserts a space before the (here empty, since 'sources' is not given)
      // 'sourceSpec', and the staging-file append adds a second space, so two spaces separate the last flag from
      // the (now single-quoted, per followup arUf) staging file path.
      expect(command).toBe(`npx md2x --list-files --output-format pdf --title 'Title'  '${stagingFile}'`)

      expect(shell.rm).toHaveBeenCalledTimes(1)
      expect(shell.rm).toHaveBeenCalledWith('-r', stagingDir)
      expect(files).toEqual(['/out/Title.pdf'])
    })

    // followup arUf: 'title' feeds the trailing filename component of the staging path appended to the command,
    // so an embedded single quote there is also part of the injection surface even though the containing
    // directory is one this code controls. Confirms the appended staging-file argument is safely escaped.
    test('escapes an embedded single quote in title within the appended staging file path', () => {
      shell.exec.mockReturnValue(mockExecResult(0, "/out/O'Brien.pdf\n"))

      const files = md2x({ markdown : '# Hello', title : "O'Brien" })

      const [, stagingDir] = shell.mkdir.mock.calls[0]
      const stagingFile = fsPath.join(stagingDir, "O'Brien.md")
      expect(shellStringTo).toHaveBeenCalledWith(stagingFile)

      const [command] = shell.exec.mock.calls[0]
      const escapedStagingFile = `'${stagingFile.replace(/'/g, "'\\''")}'`
      expect(command).toBe(
        `npx md2x --list-files --output-format pdf --title 'O'\\''Brien'  ${escapedStagingFile}`
      )

      expect(files).toEqual(["/out/O'Brien.pdf"])
    })

    test('cleans up the staging directory even when the command fails (finally)', () => {
      shell.exec.mockReturnValue(mockExecResult(1, '', 'boom'))

      expect(() => md2x({ markdown : '# Hello', title : 'Title' })).toThrow()

      const [, stagingDir] = shell.mkdir.mock.calls[0]
      expect(shell.rm).toHaveBeenCalledTimes(1)
      expect(shell.rm).toHaveBeenCalledWith('-r', stagingDir)
    })

    // With no 'title' given for the markdown-string path, 'title' now defaults to 'Report' before the staging
    // filename is built, so the staging file is named 'Report.md' rather than the literal 'undefined.md'.
    test('defaults the staging filename to Report.md when no title is given (followup egcc, fixed)', () => {
      shell.exec.mockReturnValue(mockExecResult(0, '/out/Report.pdf\n'))

      md2x({ markdown : '# Hello' })

      const [, stagingDir] = shell.mkdir.mock.calls[0]
      expect(shellStringTo).toHaveBeenCalledWith(fsPath.join(stagingDir, 'Report.md'))
    })
  })
})

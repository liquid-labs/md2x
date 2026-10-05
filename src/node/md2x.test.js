import { afterEach, beforeEach, describe, expect, jest, mock, test } from 'bun:test'
import { EventEmitter } from 'node:events'
import fs from 'node:fs'
import fsPath from 'node:path'

// Bun does not hoist 'mock.module' above static imports, so the mock is registered first and the module under test is
// loaded afterward with a top-level dynamic 'import()'.
mock.module('node:child_process', () => ({
  spawn     : jest.fn(),
  spawnSync : jest.fn()
}))

const { spawn, spawnSync } = await import('node:child_process')
const { md2x, md2xAsync } = await import('./md2x')
const index = await import('./index')

// The repo bin/md2x is a gitignored build output, so 'fs.existsSync' is stubbed to report only this path as present.
const BIN_PATH = fsPath.join(import.meta.dir, '..', '..', 'bin', 'md2x')

const syncResult = (status, stdout = '', stderr = '', extra = {}) => ({ status, stdout, stderr, ...extra })

// A fake child process for the async path.
const fakeChild = () => {
  const child = new EventEmitter()
  child.stdout = Object.assign(new EventEmitter(), { setEncoding : jest.fn() })
  child.stderr = Object.assign(new EventEmitter(), { setEncoding : jest.fn() })
  child.stdin = Object.assign(new EventEmitter(), { end : jest.fn() })
  return child
}

const argsOf = () => spawnSync.mock.calls[0][1]

describe('md2x', () => {
  let existsSpy
  let errorSpy

  beforeEach(() => {
    jest.clearAllMocks()
    existsSpy = jest.spyOn(fs, 'existsSync').mockImplementation((path) => path === BIN_PATH)
    errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
    spawnSync.mockReturnValue(syncResult(0))
  })

  afterEach(() => {
    existsSpy.mockRestore()
    errorSpy.mockRestore()
  })

  test('index exports md2x and md2xAsync', () => {
    expect(index.md2x).toBe(md2x)
    expect(index.md2xAsync).toBe(md2xAsync)
  })

  describe('bin resolution', () => {
    test('invokes the resolved bin path directly, never via a shell or npx/bunx', () => {
      md2x({ sources : ['a.md'] })

      const [bin, , opts] = spawnSync.mock.calls[0]
      expect(bin).toBe(BIN_PATH)
      expect(opts.shell).toBeUndefined()
    })

    test('throws a clear error, without spawning, when no bin can be found', () => {
      existsSpy.mockImplementation(() => false)

      expect(() => md2x({ sources : ['a.md'] })).toThrow(/Could not locate the md2x CLI executable/)
      expect(spawnSync).not.toHaveBeenCalled()
    })

    test('falls back to the second candidate (bundle layout)', () => {
      const bundleBin = fsPath.join(import.meta.dir, '..', 'bin', 'md2x')
      existsSpy.mockImplementation((path) => path === bundleBin)

      md2x({ sources : ['a.md'] })

      expect(spawnSync.mock.calls[0][0]).toBe(bundleBin)
    })
  })

  describe('argv marshaling', () => {
    test('applies only the always-on flags and the default format when no options are set', () => {
      md2x({ sources : ['a.md'] })

      expect(argsOf()).toEqual(['--list-files', '--output-format', 'pdf', '--', 'a.md'])
    })

    test('passes the format lowercased', () => {
      md2x({ sources : ['a.md'], format : 'HTML' })

      expect(argsOf()).toEqual(['--list-files', '--output-format', 'html', '--', 'a.md'])
    })

    test.each([
      ['flattenDirs', '--flatten-dirs'],
      ['inferTitle', '--infer-title'],
      ['inferVersion', '--infer-version'],
      ['noToc', '--no-toc'],
      ['toc', '--toc'],
      ['singlePage', '--single-page']
    ])('adds %s as %s, and only that flag, when true', (option, flag) => {
      md2x({ sources : ['a.md'], [option] : true })

      expect(argsOf()).toEqual(['--list-files', '--output-format', 'pdf', flag, '--', 'a.md'])
    })

    test('omits a flag set to false', () => {
      md2x({ sources : ['a.md'], toc : false, singlePage : false })

      expect(argsOf()).toEqual(['--list-files', '--output-format', 'pdf', '--', 'a.md'])
    })

    test('maps outputPath to --output-path and output to -o', () => {
      md2x({ sources : ['a.md'], outputPath : './out dir' })
      expect(argsOf()).toEqual(['--list-files', '--output-format', 'pdf', '--output-path', './out dir', '--', 'a.md'])

      jest.clearAllMocks()
      md2x({ sources : ['a.md'], output : 'o/final.pdf' })
      expect(argsOf()).toEqual(['--list-files', '--output-format', 'pdf', '-o', 'o/final.pdf', '--', 'a.md'])
    })

    test('passes title, output, and sources verbatim, with no quoting', () => {
      const title = 'It\'s a "quoted" $HOME `x` $(y) title'
      md2x({ sources : ['c dir/d.md', "it's.md"], title, output : "o'dir/$x.pdf" })

      expect(argsOf()).toEqual([
        '--list-files', '--output-format', 'pdf', '--title', title, '-o', "o'dir/$x.pdf", '--', 'c dir/d.md', "it's.md"
      ])
    })

    test('places sources after "--" so a dash-leading source is a file, not an option', () => {
      md2x({ sources : ['-weird.md'] })

      expect(argsOf()).toEqual(['--list-files', '--output-format', 'pdf', '--', '-weird.md'])
    })

    test('omits --title unless given (no Report default)', () => {
      md2x({ markdown : '# x' })

      expect(argsOf()).not.toContain('--title')
      expect(JSON.stringify(argsOf())).not.toContain('Report')
    })
  })

  describe('stdin handling', () => {
    test('sends markdown as input byte-exact, with "-" as the only positional argument', () => {
      const markdown = '  # Hi\n    indented\nno trailing newline'
      md2x({ markdown, format : 'html' })

      const [, args, opts] = spawnSync.mock.calls[0]
      expect(args).toEqual(['--list-files', '--output-format', 'html', '--', '-'])
      expect(opts.input).toBe(markdown)
      expect(opts.stdio[0]).toBe('pipe')
    })

    test('does not stage anything on disk', () => {
      const mkdtemp = jest.spyOn(fs, 'mkdtempSync')
      md2x({ markdown : 'x' })
      expect(mkdtemp).not.toHaveBeenCalled()
      mkdtemp.mockRestore()
    })

    test('ignores stdin for sources so the CLI can never block on an inherited stdin', () => {
      md2x({ sources : ['a.md'] })

      const opts = spawnSync.mock.calls[0][2]
      expect(opts.stdio).toEqual(['ignore', 'pipe', 'pipe'])
      expect(opts.input).toBeUndefined()
    })

    test('sets a generous maxBuffer and utf8 encoding', () => {
      md2x({ sources : ['a.md'] })

      const opts = spawnSync.mock.calls[0][2]
      expect(opts.maxBuffer).toBeGreaterThanOrEqual(64 * 1024 * 1024)
      expect(opts.encoding).toBe('utf8')
    })
  })

  describe('validation', () => {
    test.each([
      ['non-object options', undefined, /'options' must be an object/],
      ['null options', null, /'options' must be an object/],
      ['array options', [], /'options' must be an object/],
      ['unknown key', { sources : ['a.md'], keepIntermediate : true }, /unknown option 'keepIntermediate'/],
      ['non-boolean flag', { sources : ['a.md'], toc : 'yes' }, /'toc' must be a boolean/],
      ['non-boolean quiet', { sources : ['a.md'], quiet : 1 }, /'quiet' must be a boolean/],
      ['empty title', { sources : ['a.md'], title : '' }, /'title' must be a non-empty string/],
      ['non-string output', { sources : ['a.md'], output : 3 }, /'output' must be a non-empty string/],
      ['empty outputPath', { sources : ['a.md'], outputPath : '' }, /'outputPath' must be a non-empty string/],
      ['bad format', { sources : ['a.md'], format : 'epub' }, /'format' must be one of/],
      ['non-string format', { sources : ['a.md'], format : 5 }, /'format' must be one of/],
      ['toc with noToc', { sources : ['a.md'], toc : true, noToc : true }, /'toc' and 'noToc'/],
      ['output with outputPath', { sources : ['a.md'], output : 'a', outputPath : 'b' }, /'output' and 'outputPath'/],
      ['output "-"', { sources : ['a.md'], output : '-' }, /'output' cannot be '-'/],
      ['markdown with sources', { markdown : 'x', sources : ['a.md'] }, /'markdown' and 'sources'/],
      ['non-string markdown', { markdown : 5 }, /'markdown' must be a string/],
      ['neither markdown nor sources', {}, /'markdown' or 'sources' is required/],
      ['empty sources', { sources : [] }, /'sources' must be a non-empty array/],
      ['non-array sources', { sources : 'a.md' }, /'sources' must be a non-empty array/],
      ['empty-string source', { sources : ['a.md', ''] }, /'sources' must be a non-empty array/],
      ['stdin source', { sources : ['-'] }, /cannot contain '-'.*'markdown'/],
      ['stdin source among others', { sources : ['a.md', '-'] }, /cannot contain '-'/]
    ])('throws TypeError for %s, without spawning', (_name, options, message) => {
      let error
      try { md2x(options) }
      catch (err) { error = err }

      expect(error).toBeInstanceOf(TypeError)
      expect(error.message).toMatch(message)
      expect(spawnSync).not.toHaveBeenCalled()
    })

    test('accepts a markdown-only call and an empty markdown string', () => {
      expect(() => md2x({ markdown : '' })).not.toThrow()
    })
  })

  describe('results and errors', () => {
    test('returns the --list-files stdout lines as an array, dropping blanks', () => {
      spawnSync.mockReturnValue(syncResult(0, 'out/a.pdf\n\nout/b.pdf\n'))

      expect(md2x({ sources : ['a.md', 'b.md'] })).toEqual(['out/a.pdf', 'out/b.pdf'])
    })

    test('forwards stderr to console.error on success', () => {
      spawnSync.mockReturnValue(syncResult(0, 'a.pdf\n', 'a warning'))

      md2x({ sources : ['a.md'] })

      expect(errorSpy).toHaveBeenCalledWith('a warning')
    })

    test('quiet suppresses the stderr forwarding', () => {
      spawnSync.mockReturnValue(syncResult(0, 'a.pdf\n', 'a warning'))

      md2x({ sources : ['a.md'], quiet : true })

      expect(errorSpy).not.toHaveBeenCalled()
      expect(argsOf()).not.toContain('quiet')
    })

    test('does not call console.error when stderr is empty', () => {
      md2x({ sources : ['a.md'] })

      expect(errorSpy).not.toHaveBeenCalled()
    })

    test('tolerates missing stdout/stderr on the result', () => {
      spawnSync.mockReturnValue({ status : 0 })

      expect(md2x({ sources : ['a.md'] })).toEqual([])
    })

    test('a non-zero exit throws an Error carrying exitCode and stderr, spelled correctly', () => {
      spawnSync.mockReturnValue(syncResult(2, '', 'bad usage'))

      let error
      try { md2x({ sources : ['a.md'] }) }
      catch (err) { error = err }

      expect(error).toBeInstanceOf(Error)
      expect(error.message).toBe('md2x failed (exit 2): bad usage')
      expect(error.exitCode).toBe(2)
      expect(error.stderr).toBe('bad usage')
      expect(error.message).not.toMatch(/co(v)ert/)
    })

    test('a spawn failure throws with the cause preserved and exitCode undefined', () => {
      const cause = Object.assign(new Error('spawn ENOENT'), { code : 'ENOENT' })
      spawnSync.mockReturnValue({ status : null, error : cause, stdout : null, stderr : null })

      let error
      try { md2x({ sources : ['a.md'] }) }
      catch (err) { error = err }

      expect(error.cause).toBe(cause)
      expect(error.exitCode).toBeUndefined()
      expect(error.message).toMatch(/could not run: spawn ENOENT/)
    })

    test('a signal-terminated child is reported as a failure with no exitCode', () => {
      spawnSync.mockReturnValue({ status : null, signal : 'SIGKILL', stdout : '', stderr : 'x' })

      let error
      try { md2x({ sources : ['a.md'] }) }
      catch (err) { error = err }

      expect(error.exitCode).toBeUndefined()
      expect(error.stderr).toBe('x')
      expect(error.cause.message).toMatch(/SIGKILL/)
    })
  })
})

describe('md2xAsync', () => {
  let existsSpy
  let errorSpy
  let child

  beforeEach(() => {
    jest.clearAllMocks()
    existsSpy = jest.spyOn(fs, 'existsSync').mockImplementation((path) => path === BIN_PATH)
    errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
    child = fakeChild()
    spawn.mockReturnValue(child)
  })

  afterEach(() => {
    existsSpy.mockRestore()
    errorSpy.mockRestore()
  })

  test('resolves with the file list, writing markdown to stdin and ending it', async() => {
    const markdown = '  # Hi\n'
    const promise = md2xAsync({ markdown, format : 'html' })
    child.stdout.emit('data', 'out/')
    child.stdout.emit('data', 'output.html\n')
    child.stderr.emit('data', 'note')
    child.emit('close', 0, null)

    expect(await promise).toEqual(['out/output.html'])
    const [bin, args, opts] = spawn.mock.calls[0]
    expect(bin).toBe(BIN_PATH)
    expect(args).toEqual(['--list-files', '--output-format', 'html', '--', '-'])
    expect(opts.stdio).toEqual(['pipe', 'pipe', 'pipe'])
    expect(child.stdin.end).toHaveBeenCalledWith(markdown)
    expect(errorSpy).toHaveBeenCalledWith('note')
  })

  test('places a dash-leading source after "--"', async() => {
    const promise = md2xAsync({ sources : ['-weird.md'] })
    child.emit('close', 0, null)

    await promise
    expect(spawn.mock.calls[0][1]).toEqual(['--list-files', '--output-format', 'pdf', '--', '-weird.md'])
  })

  test('ignores stdin for sources and does not write to it', async() => {
    const promise = md2xAsync({ sources : ['a.md'], quiet : true })
    child.stderr.emit('data', 'note')
    child.emit('close', 0, null)

    await promise
    expect(spawn.mock.calls[0][2].stdio[0]).toBe('ignore')
    expect(child.stdin.end).not.toHaveBeenCalled()
    expect(errorSpy).not.toHaveBeenCalled()
  })

  test('swallows an EPIPE on stdin; the exit code is what is reported', async() => {
    const promise = md2xAsync({ markdown : 'x' })
    expect(() => child.stdin.emit('error', Object.assign(new Error('EPIPE'), { code : 'EPIPE' }))).not.toThrow()
    child.stderr.emit('data', 'died early')
    child.emit('close', 1, null)

    await expect(promise).rejects.toMatchObject({ exitCode : 1, stderr : 'died early' })
  })

  test('rejects with exitCode and stderr on a non-zero exit', async() => {
    const promise = md2xAsync({ sources : ['a.md'] })
    child.stderr.emit('data', 'bad usage')
    child.emit('close', 2, null)

    const error = await promise.catch((err) => err)
    expect(error.message).toBe('md2x failed (exit 2): bad usage')
    expect(error.exitCode).toBe(2)
    expect(error.stderr).toBe('bad usage')
  })

  test('rejects with the cause preserved on a spawn error, and ignores a following close', async() => {
    const promise = md2xAsync({ sources : ['a.md'] })
    const cause = new Error('spawn ENOENT')
    child.emit('error', cause)
    child.emit('close', -2, null)

    const error = await promise.catch((err) => err)
    expect(error.cause).toBe(cause)
    expect(error.exitCode).toBeUndefined()
  })

  test('rejects when the child is killed by a signal', async() => {
    const promise = md2xAsync({ sources : ['a.md'] })
    child.emit('close', null, 'SIGTERM')

    const error = await promise.catch((err) => err)
    expect(error.exitCode).toBeUndefined()
    expect(error.cause.message).toMatch(/SIGTERM/)
  })

  test('rejects (never throws synchronously) on invalid options, without spawning', async() => {
    let promise
    expect(() => { promise = md2xAsync({ sources : ['-'] }) }).not.toThrow()

    await expect(promise).rejects.toBeInstanceOf(TypeError)
    expect(spawn).not.toHaveBeenCalled()
  })

  test('rejects when the bin cannot be located', async() => {
    existsSpy.mockImplementation(() => false)

    await expect(md2xAsync({ sources : ['a.md'] })).rejects.toThrow(/Could not locate the md2x CLI executable/)
    expect(spawn).not.toHaveBeenCalled()
  })
})

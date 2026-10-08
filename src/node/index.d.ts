/** Output format accepted by the md2x CLI. Matched case-insensitively at runtime. */
export type Md2xFormat = 'pdf' | 'html' | 'docx'

/** Options shared by every invocation, regardless of the input source. */
export interface Md2xBaseOptions {
  /** Output format. Defaults to 'pdf'. */
  format?: Md2xFormat
  /** Flatten the output directory structure (--flatten-dirs). */
  flattenDirs?: boolean
  /** Embed the title (from 'title', or otherwise the filename) as document metadata (--infer-title). */
  inferTitle?: boolean
  /**
   * Add a version to the PDF footer: the package.json version of the git repository containing the first input (the
   * current directory for 'markdown'), or 'working' when its tree is dirty (--infer-version). Needs 'git' and 'jq'.
   */
  inferVersion?: boolean
  /** Force a table of contents (--toc). Mutually exclusive with 'noToc'. */
  toc?: boolean
  /** Suppress the table of contents (--no-toc). Mutually exclusive with 'toc'. */
  noToc?: boolean
  /** Concatenate all inputs into a single document before conversion (--single-page). */
  singlePage?: boolean
  /** Document title (--title). Must be a non-empty string. */
  title?: string
  /**
   * Output directory (--output-path). Must be a non-empty string. Mutually exclusive with 'output'.
   */
  outputPath?: string
  /**
   * Output file (-o). Must be a non-empty string and cannot be '-': the wrapper returns file paths, not bytes.
   * Mutually exclusive with 'outputPath'.
   */
  output?: string
  /** Suppress forwarding of the CLI's stderr to 'console.error' on success. */
  quiet?: boolean
}

/** Input from a markdown string, fed to the CLI on stdin. Mutually exclusive with 'sources'. */
export interface Md2xMarkdownOptions extends Md2xBaseOptions {
  /** The markdown content. Mutually exclusive with 'sources'. */
  markdown: string
  sources?: never
}

/** Input from files or directories on disk. Mutually exclusive with 'markdown'. */
export interface Md2xSourcesOptions extends Md2xBaseOptions {
  /**
   * A non-empty array of non-empty source paths. Cannot contain '-' (stdin); pass the content as 'markdown' instead.
   * Mutually exclusive with 'markdown'.
   */
  sources: string[]
  markdown?: never
}

/**
 * Options for 'md2x' and 'md2xAsync'. Exactly one of 'markdown' or 'sources' is required; unknown keys, wrong types,
 * and violated exclusivity throw a TypeError before anything is spawned (rejects, for 'md2xAsync').
 */
export type Md2xOptions = Md2xMarkdownOptions | Md2xSourcesOptions

/** The Error thrown (or rejected) when the md2x CLI fails or cannot be run. */
export interface Md2xError extends Error {
  /** The CLI's exit code. Undefined when the process could not be spawned or was killed by a signal. */
  exitCode?: number
  /** The CLI's captured stderr. */
  stderr?: string
}

/**
 * Converts markdown to the requested format by running the md2x CLI synchronously.
 *
 * Known limitation: the returned paths are parsed from newline-delimited CLI output, so an output path that itself
 * contains a newline is mis-split into several entries.
 *
 * @returns The generated file paths.
 * @throws {TypeError} On invalid options.
 * @throws {Md2xError} When the CLI fails.
 */
export function md2x(options: Md2xOptions): string[]

/**
 * Asynchronous 'md2x': same options and limitation, but errors (including invalid options) reject the Promise.
 *
 * @returns A Promise of the generated file paths.
 */
export function md2xAsync(options: Md2xOptions): Promise<string[]>

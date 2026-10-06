import neostandard from 'neostandard'
import importX from 'eslint-plugin-import-x'

export default [
  { ignores : ['dist/**', 'coverage/**', 'node_modules/**', 'bin/**', 'worktrees/**', 'plan/**', '.flow/**'] },
  ...neostandard(),
  {
    files           : ['**/*.js', '**/*.mjs'],
    plugins         : { 'import-x' : importX },
    languageOptions : { ecmaVersion : 'latest', sourceType : 'module' },
    rules           : {
      '@stylistic/brace-style' : ['error', 'stroustrup', { allowSingleLine : true }],
      curly                    : ['error', 'multi-line'],
      'import-x/export'        : 'warn',
      'import-x/extensions'    : ['error', 'never', { mjs : 'always', json : 'always' }],
      '@stylistic/indent'      : ['error', 2, { FunctionDeclaration : { body : 1, parameters : 2 } }],
      '@stylistic/key-spacing' : ['error', {
        singleLine : { beforeColon : true, afterColon : true, mode : 'strict' },
        multiLine  : { beforeColon : true, afterColon : true, align : 'colon' }
      }],
      '@stylistic/operator-linebreak'          : ['error', 'before', { overrides : { '=' : 'after' } }],
      'prefer-const'                           : 'error',
      'prefer-spread'                          : 'error',
      '@stylistic/space-before-function-paren' : ['error', 'never'],
      'array-callback-return'                  : 'error',
      'guard-for-in'                           : 'error',
      'no-caller'                              : 'error',
      'no-extra-bind'                          : 'error',
      '@stylistic/no-multi-spaces'             : 'error',
      'no-new-wrappers'                        : 'error',
      'no-throw-literal'                       : 'error',
      'no-unexpected-multiline'                : 'error',
      'no-with'                                : 'error',
      yoda                                     : 'error'
    }
  }
]

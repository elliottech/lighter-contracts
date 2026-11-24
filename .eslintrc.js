module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
    mocha: true,
    es2020: true,
  },
  parserOptions: { ecmaVersion: 8 },
  extends: ['eslint:recommended', 'plugin:prettier/recommended'],
  rules: {
    '@typescript-eslint/no-unused-vars': [
      'error',
      {
        args: 'all',
        argsIgnorePattern: '^_',
        caughtErrors: 'all',
        caughtErrorsIgnorePattern: '^_',
        destructuredArrayIgnorePattern: '^_',
        varsIgnorePattern: '^_',
      },
    ],
    radix: ['error', 'always'],
    'object-shorthand': ['error', 'always'],
    'prettier/prettier': [
      'error',
      { semi: true },
      {
        usePrettierrc: true,
      },
    ],
    camelcase: [
      'error',
      {
        allow: ['^.*__.*'], // typechain-types generates types which have __ in them, like DeployFactory__factory
      },
    ],
    'prefer-const': 'off', // temporary disable as it makes development slower
    'no-explicit-any': 'off', // temporary disable as it makes development slower
    'sort-imports': ['error', { ignoreDeclarationSort: true }],
  },
  overrides: [
    {
      files: ['test/**/*.js'],
      rules: {
        'no-unused-expressions': 'off',
        // Allow the use of @ts-ignore
        '@typescript-eslint/ban-ts-comment': 'off',
      },
    },
    {
      parser: '@typescript-eslint/parser',
      plugins: ['@typescript-eslint'],
      files: ['*.ts', '*.tsx'],
      extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended', 'plugin:prettier/recommended'],
    },
  ],
};

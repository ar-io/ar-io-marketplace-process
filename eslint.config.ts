import path from 'node:path';
import { fileURLToPath } from 'node:url';
import tsParser from '@typescript-eslint/parser';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);


export default [
  {
    files: ['**/*.ts', '**/*.tsx'],
    ignores: ['node_modules', 'dist', 'coverage', '**/package.json'],
    plugins: {},
    languageOptions: {
      parser: tsParser,
      ecmaVersion: 2022,
      sourceType: 'module',
      parserOptions: {
        project: './tsconfig.json',
        tsconfigRootDir: __dirname,
      },
    },
    rules: {
      'header/header': [2, './resources/license.header.mjs'],
    },
  },
];

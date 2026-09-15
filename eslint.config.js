/* ESLint flat config（ESM，根 package type=module）
 * 范围：前端 js/ 与 tests/、scripts/；忽略第三方 lib、APK assets 副本、云函数（CJS 另行约定）。
 * 目标：先挡住真 bug（no-undef/no-dupe-keys/no-unreachable），风格类降级为 warn，避免一次性红屏。 */
import js from '@eslint/js';

const browserGlobals = {
  window: 'readonly', document: 'readonly', navigator: 'readonly', localStorage: 'readonly',
  fetch: 'readonly', URL: 'readonly', MutationObserver: 'readonly', requestAnimationFrame: 'readonly',
  setTimeout: 'readonly', clearTimeout: 'readonly', setInterval: 'readonly', clearInterval: 'readonly',
  console: 'readonly', Math: 'readonly', Date: 'readonly', JSON: 'readonly', Promise: 'readonly',
  // 第三方 classic 全局（libs）
  Swiper: 'readonly', BScroll: 'readonly', BetterScroll: 'readonly', AlloyFinger: 'readonly',
  anime: 'readonly', autoAnimate: 'readonly',
};

export default [
  js.configs.recommended,
  {
    ignores: [
      'js/lib/**',
      'HealthyDiet/app/src/main/assets/**',
      'HealthyDiet/cloudfunctions/**',
      'node_modules/**',
      '.mimosa/**',
    ],
  },
  {
    files: ['js/**/*.js', 'tests/**/*.js', 'scripts/**/*.mjs'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...browserGlobals, process: 'readonly', require: 'readonly', module: 'writable', __dirname: 'readonly' },
    },
    rules: {
      'no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-console': 'off',
      'no-undef': 'error',
    },
  },
  {
    // tests 允许 node:test 全局
    files: ['tests/**/*.js'],
    languageOptions: { globals: { ...browserGlobals, process: 'readonly' } },
  },
];

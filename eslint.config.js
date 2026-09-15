/* ESLint flat config（ESM，根 package type=module）
 * 范围：前端 js/ 与 tests/、scripts/；忽略第三方 lib、APK assets 副本、云函数（CJS 另行约定）。
 * 目标：先挡住真 bug（no-undef/no-dupe-keys/no-unreachable），风格类降级为 warn。
 *
 * 全局变量用标准 globals 包而非手写清单 —— 手写会随 API 使用不断漏项
 * （曾漏 structuredClone/AbortSignal/Image/location 四个，导致 CI 红）。 */
import js from '@eslint/js';
import globals from 'globals';

/* 项目自有 classic 全局：js/lib 下的 UMD 库，页面用 <script> 引入而非 ESM import */
const libGlobals = {
  Swiper: 'readonly', BScroll: 'readonly', BetterScroll: 'readonly',
  AlloyFinger: 'readonly', anime: 'readonly', autoAnimate: 'readonly',
};

const sharedRules = {
  'no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
  'no-console': 'off',
  'no-undef': 'error',
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
    // 前端运行时：浏览器 / WebView 环境
    files: ['js/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.browser, ...libGlobals },
    },
    rules: sharedRules,
  },
  {
    // 构建与工具脚本：Node 环境
    files: ['scripts/**/*.mjs'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: globals.node,
    },
    rules: sharedRules,
  },
  {
    // 单元测试：Node 环境 + 浏览器（被测对象可能是前端逻辑）
    files: ['tests/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.node, ...globals.browser },
    },
    rules: sharedRules,
  },
];
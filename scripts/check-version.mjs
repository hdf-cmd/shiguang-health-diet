/* 版本号一致性校验（CI 门禁）。
 *
 * 单一来源：package.json 的 version。
 *   - Android：HealthyDiet/app/build.gradle.kts 构建时自动读取，无需校验
 *   - 前端：js/version.js 的 APP_VERSION 需手写保持同步，这里负责拦截漂移
 *
 * 用法：npm run check:version（CI 中在 lint 之前执行） */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = p => readFileSync(join(root, p), 'utf8');

const pkgVersion = JSON.parse(read('package.json')).version;
const jsVersion = read('js/version.js').match(/APP_VERSION\s*=\s*'([^']+)'/)?.[1];

const problems = [];
if (!jsVersion) {
  problems.push('js/version.js 里找不到 APP_VERSION 常量');
} else if (jsVersion !== pkgVersion) {
  problems.push(`js/version.js 的 APP_VERSION=${jsVersion}，与 package.json 的 version=${pkgVersion} 不一致`);
}

if (problems.length) {
  console.error('[check-version] 版本号不一致：');
  for (const p of problems) console.error('  - ' + p);
  console.error('  修法：把 js/version.js 的 APP_VERSION 改成与 package.json 的 version 相同');
  process.exit(1);
}

console.log(`[check-version] 版本号一致：${pkgVersion}`);
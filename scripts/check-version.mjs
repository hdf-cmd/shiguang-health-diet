/* 版本号一致性校验（CI 门禁）。
 *
 * 单一来源：package.json 的 version。
 *   - Android：HealthyDiet/app/build.gradle.kts 构建时自动读取，无需校验
 *   - 前端：js/version.js 的 APP_VERSION 需手写保持同步，这里负责拦截漂移
 *   - 文档：README.md 的「当前版本：vX.Y.Z」与 食光-vX.Y.Z.apk 文件名引用同样受检
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

/* README 的版本声明与 APK 文件名引用也纳入门禁——v1.3.1 发版时 README 停在
 * v1.0.0 被老大抓到（"事不过三"），此后漏更直接 CI 失败。 */
const readme = read('README.md');
const readmeVersion = readme.match(/当前版本：v(\d+\.\d+\.\d+)/)?.[1];
if (!readmeVersion) {
  problems.push('README.md 里找不到「当前版本：vX.Y.Z」声明');
} else if (readmeVersion !== pkgVersion) {
  problems.push(`README.md 当前版本=v${readmeVersion}，与 package.json 的 version=${pkgVersion} 不一致`);
}
const apkRefs = [...readme.matchAll(/食光-v(\d+\.\d+\.\d+)\.apk/g)].map(m => m[1]);
for (const v of apkRefs) {
  if (v !== pkgVersion) problems.push(`README.md 引用了 食光-v${v}.apk，应为 食光-v${pkgVersion}.apk`);
}

if (problems.length) {
  console.error('[check-version] 版本号不一致：');
  for (const p of problems) console.error('  - ' + p);
  console.error('  修法：同步 js/version.js 的 APP_VERSION 与 README.md 的版本声明/APK 文件名到 package.json 的 version');
  process.exit(1);
}

console.log(`[check-version] 版本号一致：${pkgVersion}`);
/* ============================================================
 * 同步 web 资源 → Android assets（单一事实来源 = 仓库根目录）
 * ------------------------------------------------------------
 * 用法：npm run sync:assets   （或 gradle 构建时自动调用）
 * 将根目录 index.html / css/ / js/ 复制到
 * HealthyDiet/app/src/main/assets/web/，杜绝手工 Copy-Item 漏同步漂移。
 * 仅复制 web 运行时文件，不含 tests/ scripts/ node_modules/。
 * 注：不用 fs.cpSync/rmSync 递归（Windows 下偶发原生崩溃），改为显式逐文件镜像。
 * ============================================================ */
import { copyFileSync, mkdirSync, readdirSync, rmSync, statSync, existsSync } from 'node:fs';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, '..');
const DEST = join(ROOT, 'HealthyDiet', 'app', 'src', 'main', 'assets', 'web');
const TARGETS = ['index.html', 'css', 'js'];

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

/* 镜像单个目标（文件或目录）：覆盖同名、删除目标端多余文件 */
function mirror(src, dst) {
  if (!statSync(src).isDirectory()) {
    mkdirSync(dirname(dst), { recursive: true });
    copyFileSync(src, dst);
    return 1;
  }
  mkdirSync(dst, { recursive: true });
  const srcFiles = walk(src).map(f => relative(src, f));
  // 删除目标端已不存在于源的文件
  if (existsSync(dst)) {
    for (const f of walk(dst)) {
      const rel = relative(dst, f);
      if (!srcFiles.includes(rel)) rmSync(f, { force: true });
    }
  }
  for (const rel of srcFiles) {
    const from = join(src, rel), to = join(dst, rel);
    mkdirSync(dirname(to), { recursive: true });
    copyFileSync(from, to);
  }
  return srcFiles.length;
}

let total = 0;
for (const t of TARGETS) {
  const src = join(ROOT, t);
  if (!existsSync(src)) { console.warn(`[sync] 跳过不存在: ${t}`); continue; }
  total += mirror(src, join(DEST, t));
}
console.log(`[sync] 已镜像 ${total} 个文件 → ${DEST}`);

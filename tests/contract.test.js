/* 双栈契约测试（H5 侧，node:test，不联网）：
 * 读 contract/fixtures/diet-core.json，断言 js/api.js 的
 *   1) ROUTES[route] 路径模板与 fixture.path 一致；
 *   2) HealthAPI[jsMethod] 调 request 时的 method（缺省 GET）与 fixture.httpMethod 一致。
 * fixture 的 httpMethod/path 同时被 Dart 侧 contract_test.dart 用真实调用链断言，
 * 两端共用一份契约 → 任一侧改路由必有一侧红。 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ROUTES } from '../js/api.js';

const fixture = JSON.parse(
  readFileSync(new URL('../contract/fixtures/diet-core.json', import.meta.url), 'utf8')
);
const apiSrc = readFileSync(new URL('../js/api.js', import.meta.url), 'utf8');

test('fixture 自身结构合法：每条含 route/dartMethod/path/httpMethod', () => {
  assert.ok(Array.isArray(fixture.routes) && fixture.routes.length > 0);
  for (const e of fixture.routes) {
    assert.ok(typeof e.route === 'string' && e.route.length > 0, 'route 必填');
    assert.ok(typeof e.dartMethod === 'string' && e.dartMethod.length > 0, 'dartMethod 必填');
    assert.ok(typeof e.path === 'string' && e.path.startsWith('/'), 'path 须以 / 开头');
    assert.ok(['GET', 'POST', 'PUT', 'DELETE'].includes(e.httpMethod), `httpMethod 非法: ${e.httpMethod}`);
    assert.ok(Array.isArray(e.responseFields) && e.responseFields.length > 0, 'responseFields 必填');
  }
});

for (const e of fixture.routes) {
  test(`ROUTES.${e.route} 路径与契约一致（${e.path}）`, () => {
    assert.ok(e.route in ROUTES, `js/api.js ROUTES 缺少路由: ${e.route}`);
    assert.equal(ROUTES[e.route], e.path);
  });

  if (e.jsMethod) {
    test(`${e.jsMethod} 请求方法与契约一致（${e.httpMethod}）`, () => {
      // 定位 HealthAPI 里该方法的 request 调用行（整行匹配，方法名到 request('route' 之间允许箭头参数）
      const lineRe = new RegExp(`^[^\\n]*\\b${e.jsMethod}:\\s*[^\\n]*?request\\('${e.route}'[^\\n]*$`, 'm');
      const m = apiSrc.match(lineRe);
      assert.ok(m, `js/api.js 未找到 ${e.jsMethod} → request('${e.route}') 调用`);
      const mm = m[0].match(/method:\s*'(GET|POST|PUT|DELETE)'/);
      assert.equal(mm ? mm[1] : 'GET', e.httpMethod);
    });
  }
}

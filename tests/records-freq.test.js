/* 食物频次聚合纯逻辑（M12-③）——钉 HealthyDiet/cloudfunctions/api-diet/freq.js。
 * 只钉两件与数据库无关的事：按菜名计数（trim/空名/非字符串）、翻页收集的终止与截断判定。
 * 真实 db 查询（skip/limit/orderBy）本地跑不起来（云函数目录无 node_modules），
 * 由部署后的真调用验收，见 M12 spec 的部署闸。 */
import test from 'node:test';
import assert from 'node:assert/strict';
import freq from '../HealthyDiet/cloudfunctions/api-diet/freq.js';

test('countNames：同名合并、名字去首尾空格、空名与非字符串丢弃', () => {
  const counts = freq.countNames([
    { name: '米饭' },
    { name: ' 米饭 ' },
    { name: '鸡胸肉' },
    { name: '' },
    { name: '   ' },
    {},
    { name: 42 },
    null,
  ]);
  assert.deepEqual(counts, { 米饭: 2, 鸡胸肉: 1 });
});

test('countNames：空列表得空对象（不是 null）', () => {
  assert.deepEqual(freq.countNames([]), {});
});

test('collectAll：短页即止，complete=true，按 pageSize 递增 skip', async () => {
  const calls = [];
  const pages = [
    [{ name: 'A0' }, { name: 'A1' }, { name: 'A2' }],
    [{ name: 'B0' }],
  ];
  const r = await freq.collectAll(
    async (skip, limit) => {
      calls.push([skip, limit]);
      return pages[calls.length - 1];
    },
    { pageSize: 3, maxPages: 5 },
  );
  assert.equal(r.complete, true);
  assert.equal(r.records.length, 4);
  assert.deepEqual(calls, [[0, 3], [3, 3]]);
});

test('collectAll：恰好整页结束要多拉一页确认；始终满页则在 maxPages 停并标 complete=false', async () => {
  const calls = [];
  const r = await freq.collectAll(
    async (skip) => {
      calls.push(skip);
      return [{ name: 'x' }, { name: 'x' }];
    },
    { pageSize: 2, maxPages: 3 },
  );
  assert.equal(r.records.length, 6);
  assert.equal(r.complete, false, '被 maxPages 截断必须自报，不得静默少算');
  assert.deepEqual(calls, [0, 2, 4]);
});

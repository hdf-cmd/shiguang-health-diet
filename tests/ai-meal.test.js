import test from 'node:test';
import assert from 'node:assert/strict';
import meal from '../HealthyDiet/cloudfunctions/api-diet/ai_meal.js';

test('validateMealItems：合法条目通过，营养字段被丢弃', () => {
  const r = meal.validateMealItems({
    items: [
      { query: '米饭', quantity: 1, unit: 'serving', portion: 'bowl', calories: 999, protein: 99 },
      { query: '鸡蛋', quantity: 2 },
    ],
  });
  assert.equal(r.ok, true);
  assert.equal(r.items.length, 2);
  assert.deepEqual(r.items[0], { query: '米饭', quantity: 1, unit: 'serving', portion: 'bowl' });
  assert.equal(r.items[0].calories, undefined);
  assert.equal(r.items[0].protein, undefined);
  assert.deepEqual(r.items[1], { query: '鸡蛋', quantity: 2, unit: null, portion: null });
});

test('validateMealItems：kg / l / lb 归一化，未知单位只丢单位保留数量', () => {
  const r = meal.validateMealItems({
    items: [
      { query: '牛奶', quantity: 1.5, unit: 'l' },
      { query: '牛肉', quantity: 0.5, unit: 'kg' },
      { query: '面包', quantity: 2, unit: '片' },
    ],
  });
  assert.equal(r.ok, true);
  assert.equal(r.items[0].unit, 'ml');
  assert.equal(r.items[0].quantity, 1500);
  assert.equal(r.items[1].unit, 'g');
  assert.equal(r.items[1].quantity, 500);
  assert.equal(r.items[2].unit, null);
  assert.equal(r.items[2].quantity, 2);
});

test('validateMealItems：family portion 只保留白名单词', () => {
  const r = meal.validateMealItems({
    items: [
      { query: '吐司', quantity: 3, portion: 'SLICE' },
      { query: '汤', quantity: 1, portion: 'a good amount' },
    ],
  });
  assert.equal(r.items[0].portion, 'slice');
  assert.equal(r.items[1].portion, null);
});

test('validateMealItems：无字母的名字丢弃，其余条目保留并记 errors', () => {
  const r = meal.validateMealItems({
    items: [{ query: '12345' }, { query: '鸡蛋', quantity: 2 }, { query: '' }],
  });
  assert.equal(r.ok, true);
  assert.equal(r.items.length, 1);
  assert.equal(r.items[0].query, '鸡蛋');
  assert.deepEqual(r.errors.map(e => e.reason), ['name', 'name']);
});

test('validateMealItems：数量越界/非正/NaN 的处理', () => {
  const r = meal.validateMealItems({
    items: [
      { query: '米饭', quantity: 0 },
      { query: '面条', quantity: 10001 },
      { query: '牛奶', quantity: 'NaN' },
      { query: '苹果', quantity: '1,5', unit: 'kg' },
    ],
  });
  assert.equal(r.ok, true);
  // 0 → null（当没写）；10001 越界整条丢弃；NaN → null；1,5kg → 1500g
  assert.deepEqual(r.items.map(i => [i.query, i.quantity, i.unit]), [
    ['米饭', null, null],
    ['牛奶', null, null],
    ['苹果', 1500, 'g'],
  ]);
  assert.deepEqual(r.errors, [{ index: 1, reason: 'quantity' }]);
});

test('validateMealItems：空数组是有效答案，全丢不是', () => {
  assert.deepEqual(meal.validateMealItems({ items: [] }), { ok: true, items: [], errors: [] });
  const allBad = meal.validateMealItems({ items: [{ query: '---' }, { query: '123' }] });
  assert.equal(allBad.ok, false);
  assert.equal(allBad.reason, 'all_dropped');
  assert.equal(meal.validateMealItems({ foo: 1 }).reason, 'shape');
  assert.equal(meal.validateMealItems(null).reason, 'shape');
});

test('validateMealItems：超过 12 条只取前 12 条', () => {
  const items = Array.from({ length: 20 }, (_, i) => ({ query: '食物' + i }));
  const r = meal.validateMealItems({ items });
  assert.equal(r.ok, true);
  assert.equal(r.items.length, meal.kMealItemsMax);
});

test('looksLikeFoodName：中文/英文算食物名，纯数字/符号不算', () => {
  assert.equal(meal.looksLikeFoodName('番茄炒蛋'), true);
  assert.equal(meal.looksLikeFoodName('egg'), true);
  assert.equal(meal.looksLikeFoodName('カレー'), true);
  assert.equal(meal.looksLikeFoodName('123'), false);
  assert.equal(meal.looksLikeFoodName('---'), false);
});

test('rankMealMatches：精确同名排第一，其余保持原序，最多 3 个', () => {
  const rows = [{ name: '鸡蛋羹' }, { name: '鸡蛋' }, { name: '米饭' }, { name: '面条' }];
  const r = meal.rankMealMatches(rows, '鸡蛋');
  assert.deepEqual(r.map(x => x.name), ['鸡蛋', '鸡蛋羹', '米饭']);
  assert.equal(meal.rankMealMatches([], '鸡蛋').length, 0);
  assert.equal(meal.rankMealMatches(null, '鸡蛋').length, 0);
  const noExact = meal.rankMealMatches(rows, '牛奶');
  assert.deepEqual(noExact.map(x => x.name), ['鸡蛋羹', '鸡蛋', '米饭']);
});

test('textStatesAUnit / dropUnstatedUnits：单位必须有原文佐证', () => {
  assert.equal(meal.textStatesAUnit('100g 米饭'), true);
  assert.equal(meal.textStatesAUnit('250毫升牛奶'), true);
  assert.equal(meal.textStatesAUnit('1.5L 可乐'), true);
  assert.equal(meal.textStatesAUnit('两个鸡蛋'), false);
  assert.equal(meal.textStatesAUnit('一盒安慕希酸奶'), false);

  const withUnit = meal.dropUnstatedUnits(
    [{ query: '米饭', quantity: 100, unit: 'g', portion: null }],
    '100g 米饭',
  );
  assert.equal(withUnit[0].unit, 'g');

  const withoutUnit = meal.dropUnstatedUnits(
    [{ query: '安慕希酸奶', quantity: 1, unit: 'g', portion: null }],
    '一盒安慕希酸奶',
  );
  assert.equal(withoutUnit[0].unit, null);
  assert.equal(withoutUnit[0].quantity, 1);
});

test('statedUnitQuantities / alignStatedUnits：唯一规格重量校正模型数量', () => {
  assert.deepEqual(meal.statedUnitQuantities('早餐一瓶200g安慕希酸奶'), [{ quantity: 200, unit: 'g' }]);
  assert.deepEqual(meal.statedUnitQuantities('1.5l 牛奶'), [{ quantity: 1500, unit: 'ml' }]);

  const items = [
    { query: '安慕希酸奶', quantity: 1, unit: 'g', portion: null },
    { query: '肉包', quantity: 1, unit: null, portion: null },
  ];
  const aligned = meal.alignStatedUnits(items, '早餐一瓶200g安慕希酸奶，1个肉包');
  assert.equal(aligned[0].quantity, 200);
  assert.equal(aligned[0].unit, 'g');
  assert.equal(aligned[1].quantity, 1);

  const multi = [
    { query: '米饭', quantity: 100, unit: 'g', portion: null },
    { query: '牛奶', quantity: 250, unit: 'ml', portion: null },
  ];
  assert.deepEqual(meal.alignStatedUnits(multi, '100g米饭、250ml牛奶'), multi);
});

test('buildMealParseMessages：首轮与重试轮不同，重试需更强的格式约束', () => {
  const first = meal.buildMealParseMessages('  一碗米饭、两个鸡蛋 ', false);
  const retry = meal.buildMealParseMessages('一碗米饭、两个鸡蛋', true);
  assert.equal(first[0].role, 'system');
  assert.equal(first[1].role, 'user');
  assert.ok(first[1].content.includes('一碗米饭'));
  assert.ok(retry[1].content.includes('上一次输出不合法'));
  assert.ok(first[0].content.includes('不估算任何营养数值'));
});

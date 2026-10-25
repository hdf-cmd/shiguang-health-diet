import test from 'node:test';
import assert from 'node:assert/strict';
import ai from '../HealthyDiet/cloudfunctions/api-diet/ai.js';

const good = { dish: '蒜薹鸡块', confidence: 'high',
  per100: { kcal: 156, protein: 8.6, carb: 7.4, fat: 9.8 }, note: '偏油' };

test('parseModelJson：纯 JSON / 围栏 / 前后寒暄 / 坏 JSON', () => {
  assert.equal(ai.parseModelJson('{"a":1}').a, 1);
  assert.equal(ai.parseModelJson('```json\n{"a":1}\n```').a, 1);
  assert.equal(ai.parseModelJson('好的，结果如下：{"a":1} 以上。').a, 1);
  assert.equal(ai.parseModelJson('不是 JSON'), null);
  assert.equal(ai.parseModelJson(null), null);
});

test('normalizePer100：kcal 取整、三大营养素 1 位小数；缺项返回 null', () => {
  assert.deepEqual(ai.normalizePer100({ kcal: 155.6, protein: 8.64, carb: 7.35, fat: 9.81 }),
    { kcal: 156, protein: 8.6, carb: 7.4, fat: 9.8 });
  assert.equal(ai.normalizePer100({ kcal: 100 }), null);
});

test('energyDeviation：4P+4C+9F 与热量之差的比例', () => {
  const d = ai.energyDeviation({ kcal: 100, protein: 10, carb: 10, fat: 4.84 }); // 4*10+4*10+9*4.84=123.56
  assert.ok(d > 0.23 && d < 0.24);
});

test('validateScanResult：合法通过，confidence 非法降为 low', () => {
  const v = ai.validateScanResult(good);
  assert.equal(v.ok, true);
  assert.equal(v.dish, '蒜薹鸡块');
  assert.equal(v.confidence, 'high');
  assert.equal(ai.validateScanResult({ ...good, confidence: 'sure' }).confidence, 'low');
});

test('validateScanResult：dish 空、数值越界、能量不自洽分别拒绝', () => {
  assert.equal(ai.validateScanResult({ ...good, dish: '  ' }).reason, 'dish');
  assert.equal(ai.validateScanResult({ ...good, per100: { ...good.per100, kcal: 901 } }).reason, 'range');
  assert.equal(ai.validateScanResult({ ...good, per100: { ...good.per100, protein: 101 } }).reason, 'range');
  assert.equal(ai.validateScanResult({ ...good, per100: { kcal: 300, protein: 1, carb: 1, fat: 1 } }).reason, 'energy');
});

test('buildScanMessages：无 hint 保持原文；有 hint 注入提示且保留 strict 前缀', () => {
  const none = ai.buildScanMessages('data:image/jpeg;base64,AAA', '', false);
  assert.equal(none[0].role, 'system');
  assert.equal(none[1].content[0].text, '请识别这道菜。');
  assert.equal(none[1].content[1].image_url.url, 'data:image/jpeg;base64,AAA');

  const hinted = ai.buildScanMessages('data:image/jpeg;base64,AAA', ' 番茄炒蛋 ', false);
  assert.match(hinted[1].content[0].text, /番茄炒蛋/);
  assert.match(hinted[1].content[0].text, /优先使用提示中的菜名/);
  assert.match(hinted[1].content[0].text, /以图片为准/);

  const strict = ai.buildScanMessages('x', '番茄炒蛋', true);
  assert.match(strict[1].content[0].text, /^上一次结果不合法/);
  assert.match(strict[1].content[0].text, /番茄炒蛋/);
});

test('常量口径', () => {
  assert.equal(ai.kAiScanDailyLimit, 50);
  assert.equal(ai.kAiImageMaxChars, 280000);
  assert.equal(ai.kAiImagePrefix.test('data:image/jpeg;base64,AAA'), true);
  assert.equal(ai.kAiImagePrefix.test('data:text/plain;base64,AAA'), false);
});

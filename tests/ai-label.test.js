import test from 'node:test';
import assert from 'node:assert/strict';
import label from '../HealthyDiet/cloudfunctions/api-diet/ai_label.js';

test('validateLabelResult：合法营养表通过，字段归一化', () => {
  const r = label.validateLabelResult({
    ok: true,
    name: ' 安慕希酸奶 ',
    brand: '伊利',
    unit: 'ml',
    servingGrams: '200',
    per100: { kcal: '89', protein: '3.1', carb: '12', fat: '3.1' },
    note: '每100毫升',
  });
  assert.equal(r.ok, true);
  assert.equal(r.name, '安慕希酸奶');
  assert.equal(r.brand, '伊利');
  assert.equal(r.unit, 'ml');
  assert.equal(r.servingGrams, 200);
  assert.deepEqual(r.per100, { kcal: 89, protein: 3.1, carb: 12, fat: 3.1 });
  assert.equal(r.verify, false);
});

test('validateLabelResult：只有 kJ 时按 4.184 折算', () => {
  const r = label.validateLabelResult({
    ok: true,
    per100: { kJ: 418.4, protein: 3, carb: 10, fat: 3 },
  });
  assert.equal(r.ok, true);
  assert.equal(r.per100.kcal, 100);
});

test('validateLabelResult：全 0、越界、能量不自洽、unreadable 分别拒绝', () => {
  const base = { ok: true, per100: { kcal: 100, protein: 3, carb: 10, fat: 3 } };
  assert.equal(label.validateLabelResult({ ...base, per100: { kcal: 0, protein: 0, carb: 0, fat: 0 } }).reason, 'zero');
  assert.equal(label.validateLabelResult({ ...base, per100: { ...base.per100, protein: 101 } }).reason, 'shape');
  assert.equal(label.validateLabelResult({ ...base, per100: { kcal: 900, protein: 1, carb: 1, fat: 1 } }).reason, 'energy');
  assert.equal(label.validateLabelResult({ ok: false }).reason, 'unreadable');
  assert.equal(label.validateLabelResult(null).reason, 'shape');
});

test('validateLabelResult：serveGrams 越界置空，空名字允许', () => {
  const r = label.validateLabelResult({
    ok: true,
    name: '',
    servingGrams: 99999,
    per100: { kcal: 100, protein: 3, carb: 10, fat: 3 },
  });
  assert.equal(r.ok, true);
  assert.equal(r.name, '');
  assert.equal(r.servingGrams, null);
});

test('buildLabelScanMessages：带 hint 与严格重试提示', () => {
  const first = label.buildLabelScanMessages('data:image/jpeg;base64,AA', '安慕希酸奶', false);
  const retry = label.buildLabelScanMessages('data:image/jpeg;base64,AA', '', true);
  assert.equal(first[0].role, 'system');
  assert.ok(first[1].content[0].text.includes('安慕希酸奶'));
  assert.ok(retry[1].content[0].text.includes('上一次结果不合法'));
});

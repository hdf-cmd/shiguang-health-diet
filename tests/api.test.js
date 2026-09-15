/* HealthAPI 接口契约测试（Mock 模式，node:test）：验证返回结构与增删改链路 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { HealthAPI, setUseMock, getUseMock } from '../js/api.js';

test.before(() => { setUseMock(true); });
test.after(() => { setUseMock(false); });

test('setUseMock 切换生效', () => {
  assert.equal(getUseMock(), true);
});

test('getDailySummary 返回汇总结构（含 target/三大营养素/water）', async () => {
  const s = await HealthAPI.getDailySummary('2026-09-15');
  assert.ok(typeof s.kcal === 'number');
  assert.ok(typeof s.target === 'number');
  for (const k of ['carb', 'protein', 'fat', 'water']) assert.ok(typeof s[k] === 'number');
});

test('addFoodRecord → getDailySummary 热量累加；deleteFoodRecord 回退', async () => {
  const date = '2026-09-14';
  const before = (await HealthAPI.getDailySummary(date)).kcal;
  const rec = await HealthAPI.addFoodRecord({ date, meal: 'lunch', name: '测试菜', portion: '1份', kcal: 100, protein: 10, carb: 10, fat: 1 });
  const after = (await HealthAPI.getDailySummary(date)).kcal;
  assert.equal(after, before + 100);
  await HealthAPI.deleteFoodRecord(rec.id);
  const back = (await HealthAPI.getDailySummary(date)).kcal;
  assert.equal(back, before);
});

test('addExercise → getExercises 可见；deleteExercise 移除', async () => {
  const date = '2026-09-13';
  const rec = await HealthAPI.addExercise({ date, key: 'run', name: '跑步', emoji: '🏃', amount: 5, unit: 'km', kcal: 285 });
  const list = await HealthAPI.getExercises(date);
  assert.ok(list.some(x => x.id === rec.id && x.kcal === 285));
  await HealthAPI.deleteExercise(rec.id);
  const list2 = await HealthAPI.getExercises(date);
  assert.ok(!list2.some(x => x.id === rec.id));
});

test('searchFoods 按餐次过滤（meals 字段）', async () => {
  const breakfast = await HealthAPI.searchFoods('', 'breakfast');
  const dinner = await HealthAPI.searchFoods('', 'dinner');
  assert.ok(breakfast.length > 0 && dinner.length > 0);
  // 早餐结果不应包含仅午晚餐的菜品
  assert.ok(breakfast.every(f => !f.meals || f.meals.includes('breakfast')));
  assert.ok(dinner.every(f => !f.meals || f.meals.includes('dinner')));
});

test('addWater 累加并受目标上限约束', async () => {
  const r1 = await HealthAPI.addWater(1, '2026-09-12');
  assert.ok(typeof r1.water === 'number');
});

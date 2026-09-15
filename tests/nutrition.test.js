/* 营养素与热量计算单测（node:test，零依赖）
 *
 * 覆盖三类换算：
 *   1) macroGoals      —— 目标热量 → 三大营养素克数（碳水 50% / 蛋白 25% / 脂肪 25% 供能比）
 *   2) portionMacros   —— 每 100g 营养 → 任意克数（线性换算）
 *   3) exerciseKcalOf  —— 运动消耗（距离型 / 时长型 MET 公式）
 *   4) computeMetabolism —— 代谢与安全下限（补齐男性档，原有用例只覆盖女性）
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { macroGoals, portionMacros, exerciseKcalOf, computeMetabolism, EXERCISE_LIB } from '../js/logic.js';

/* ---------- macroGoals：目标热量 → 营养素克数 ---------- */

test('macroGoals: 按 50/25/25 供能比换算（碳水4、蛋白4、脂肪9 kcal/g）', () => {
  assert.deepEqual(macroGoals(2000), { carb: 250, protein: 125, fat: 56 });
  // carb = 2000*0.5/4 = 250；protein = 2000*0.25/4 = 125；fat = 2000*0.25/9 = 55.56 → 56
});

test('macroGoals: 回算热量与目标基本一致（仅四舍五入误差）', () => {
  // 三项各自最多 ±0.5g：碳水/蛋白 ±2 kcal、脂肪 ±4.5 kcal，合计理论上限约 ±8.5 kcal
  for (const target of [1200, 1500, 1800, 2000, 2500]) {
    const g = macroGoals(target);
    const back = g.carb * 4 + g.protein * 4 + g.fat * 9;
    assert.ok(Math.abs(back - target) <= 10, `${target} kcal 回算得 ${back} kcal，偏差过大`);
  }
});

test('macroGoals: 边界值 0 与高热量', () => {
  assert.deepEqual(macroGoals(0), { carb: 0, protein: 0, fat: 0 });
  assert.deepEqual(macroGoals(3000), { carb: 375, protein: 188, fat: 83 });
});

/* ---------- portionMacros：每 100g → 任意克数 ---------- */

const RICE = { per100: { kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3 } };   // 贴近米饭量级

test('portionMacros: 100g 即 per100 原值', () => {
  assert.deepEqual(portionMacros(RICE, 100), { kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3 });
});

test('portionMacros: 150g 按比例换算（热量取整、宏量保留一位小数）', () => {
  assert.deepEqual(portionMacros(RICE, 150), { kcal: 174, protein: 3.9, carb: 38.8, fat: 0.4 });
  // 116*1.5=174；2.6*1.5=3.9；25.9*1.5=38.85→"38.8"（浮点下溢）；0.3*1.5=0.45→"0.4"
});

test('portionMacros: 0g 与极小克数', () => {
  assert.deepEqual(portionMacros(RICE, 0), { kcal: 0, protein: 0, carb: 0, fat: 0 });
  const tiny = portionMacros(RICE, 1);
  assert.equal(tiny.kcal, 1);      // round(1.16)
  assert.equal(tiny.carb, 0.3);    // 0.259 → 一位小数
});

test('portionMacros: 大克数（500g）与小数克数', () => {
  assert.deepEqual(portionMacros(RICE, 500), { kcal: 580, protein: 13, carb: 129.5, fat: 1.5 });
  assert.deepEqual(portionMacros(RICE, 37.5), { kcal: 44, protein: 1, carb: 9.7, fat: 0.1 });
});

test('portionMacros: 宏量保留一位小数（不出现长尾浮点）', () => {
  const p = portionMacros({ per100: { kcal: 137, protein: 7.33, carb: 11.11, fat: 3.33 } }, 133);
  const decimalsOf = v => (String(v).split('.')[1] || '').length;
  for (const k of ['protein', 'carb', 'fat']) {
    assert.ok(decimalsOf(p[k]) <= 1, `${k}=${p[k]} 小数位过多`);
  }
});

/* ---------- exerciseKcalOf：运动消耗 ---------- */

test('exerciseKcalOf: 距离型 = 系数 × 体重 × 距离', () => {
  const run = EXERCISE_LIB.find(l => l.key === 'run');
  assert.equal(exerciseKcalOf(run, 5, 60), Math.round(run.perKgKm * 60 * 5));
  assert.equal(exerciseKcalOf(run, 0, 60), 0);          // 零距离 → 0
});

test('exerciseKcalOf: 时长型 = MET × 3.5 × 体重 ÷ 200 × 分钟', () => {
  const swim = EXERCISE_LIB.find(l => l.key === 'swim');
  assert.equal(exerciseKcalOf(swim, 30, 60), Math.round(swim.met * 3.5 * 60 / 200 * 30));
  assert.equal(exerciseKcalOf(swim, 0, 60), 0);
});

test('exerciseKcalOf: 体重缺省或为 0 时回退 55kg', () => {
  const run = EXERCISE_LIB.find(l => l.key === 'run');
  assert.equal(exerciseKcalOf(run, 5, undefined), exerciseKcalOf(run, 5, 55));
  assert.equal(exerciseKcalOf(run, 5, 0), exerciseKcalOf(run, 5, 55));
});

/* ---------- computeMetabolism：男性档与安全下限 ---------- */

test('computeMetabolism: 男性 BMR 公式（+5）与未被下限托住的正常档', () => {
  const MALE = { heightCm: 175, weightKg: 80, age: 30, gender: 'male', activity: 'light', deficit: 500 };
  const m = computeMetabolism(MALE, 70);
  // BMR = 10*80 + 6.25*175 - 5*30 + 5 = 1748.75 → 1749
  assert.equal(m.bmr, 1749);
  // TDEE = 1749 * 1.375 = 2404.875 → 2405
  assert.equal(m.tdee, 2405);
  // suggest = max(2405-500, 男性下限1500, BMR 1749) = 1905（未被下限托住）
  assert.equal(m.suggest, 1905);
  assert.equal(m.realDeficit, 500);
  assert.equal(m.useActual, false);
});

test('computeMetabolism: 女性安全下限 1200 生效于极端缺口', () => {
  const aggressive = { heightCm: 165, weightKg: 60, age: 28, gender: 'female', activity: 'light', deficit: 2000 };
  const m = computeMetabolism(aggressive, 52);
  // BMR = 1330，suggest = max(1829-2000, 1200, 1330) = 1330 —— 由 BMR 托底（BMR 高于 1200 下限）
  assert.equal(m.suggest, 1330);
  assert.ok(m.suggest >= m.bmr, '建议摄入不得低于基础代谢');
});

test('computeMetabolism: 未提供目标体重时按当前体重（缺口为 0，给出维持提示）', () => {
  const BODY = { heightCm: 165, weightKg: 60, age: 28, gender: 'female', activity: 'light', deficit: 500 };
  const m = computeMetabolism(BODY, undefined);
  assert.ok(m.etaText.includes('维持当前摄入'));
});
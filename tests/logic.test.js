/* 纯领域逻辑单测（node:test，零依赖）：node --test tests/ */
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  computeMetabolism, macroGoals, exerciseKcalOf, portionMacros, biaEstimate,
  avgDeficitFromRows, localIso, dateLabelOf, buildAdvice, makeAdviceCtx,
  EXERCISE_LIB, WATER_CUP_ML,
} from '../js/logic.js';

const BODY = { heightCm: 165, weightKg: 60, age: 28, gender: 'female', activity: 'light', deficit: 500 };

test('computeMetabolism: BMR/TDEE/建议摄入 符合 Mifflin-St Jeor 与安全下限', () => {
  const m = computeMetabolism(BODY, 52);
  // BMR = 10*60 + 6.25*165 - 5*28 - 161 = 1330.25 → 1330
  assert.equal(m.bmr, 1330);
  // TDEE = 1330 * 1.375 = 1828.75 → 1829
  assert.equal(m.tdee, 1829);
  // suggest = max(1829-500, 1200, 1330) = 1330（被 BMR 下限托住）
  assert.equal(m.suggest, 1330);
  assert.equal(m.realDeficit, m.tdee - m.suggest);
  assert.ok(m.etaText.includes('减到 52kg'));
});

test('computeMetabolism: 实际缺口 > 预设时达标时间更短（反馈3）', () => {
  const preset = computeMetabolism(BODY, 52);
  const actual = computeMetabolism(BODY, 52, { avgDeficit: 800, days: 3 });
  assert.equal(actual.useActual, true);
  assert.equal(actual.effDeficit, 800);
  assert.ok(actual.etaText.includes('按近 3 天实际日均缺口 800 kcal 估算'));
  // 实际缺口更大 → 天数更少
  const daysOf = t => Number(t.match(/预计 (\d+) 周/)[1]);
  assert.ok(daysOf(actual.etaText) < daysOf(preset.etaText));
});

test('computeMetabolism: 实际数据不足 2 天 → 退回预设缺口', () => {
  const m = computeMetabolism(BODY, 52, { avgDeficit: 800, days: 1 });
  assert.equal(m.useActual, false);
  assert.equal(m.effDeficit, m.realDeficit);
});

test('computeMetabolism: 无需减重时给出维持提示', () => {
  const m = computeMetabolism(BODY, 60);
  assert.ok(m.etaText.includes('维持当前摄入'));
});

test('macroGoals: 1800kcal → 碳水225/蛋白113/脂肪50', () => {
  assert.deepEqual(macroGoals(1800), { carb: 225, protein: 113, fat: 50 });
});

test('exerciseKcalOf: 距离型与时长型公式', () => {
  const run = EXERCISE_LIB.find(l => l.key === 'run');
  const swim = EXERCISE_LIB.find(l => l.key === 'swim');
  assert.equal(exerciseKcalOf(run, 5, 55), 285);          // 1.036*55*5
  assert.equal(exerciseKcalOf(swim, 30, 55), 231);        // 8*3.5*55/200*30
  assert.equal(exerciseKcalOf(run, 5, undefined), 285);   // 缺省体重 55
});

test('portionMacros: per100 按克数线性换算', () => {
  const f = { per100: { kcal: 100, protein: 10, carb: 10, fat: 10 } };
  assert.deepEqual(portionMacros(f, 200), { kcal: 200, protein: 20, carb: 20, fat: 20 });
  assert.deepEqual(portionMacros(f, 50), { kcal: 50, protein: 5, carb: 5, fat: 5 });
});

test('avgDeficitFromRows: 均值计算与最小天数门槛', () => {
  const rows = [{ intake: 1500, exKcal: 0 }, { intake: 1400, exKcal: 100 }];
  const r = avgDeficitFromRows(2000, rows);
  assert.deepEqual(r, { avgDeficit: 600, days: 2, tdee: 2000 });
  assert.equal(avgDeficitFromRows(2000, [rows[0]]), null);   // <2 天
  assert.equal(avgDeficitFromRows(2000, []), null);
});

test('localIso/dateLabelOf: 本地时区安全与口语标签', () => {
  assert.equal(localIso(new Date(2026, 8, 15)), '2026-09-15');
  const yd = new Date(); yd.setDate(yd.getDate() - 1);
  assert.equal(dateLabelOf(localIso(yd)), '昨天');
});

test('buildAdvice: 三餐已记录 → 零食方向（反馈5）', () => {
  const ctx = makeAdviceCtx({
    summary: { kcal: 1500, target: 1800, carb: 180, protein: 60, fat: 45, water: 8 },
    exerciseKcal: 0,
    records: [{ meal: 'breakfast' }, { meal: 'lunch' }, { meal: 'dinner' }],
    isToday: true, weightKg: 60, waterGoalMl: 1600,
  });
  const tips = buildAdvice(ctx);
  assert.ok(ctx.allMealsDone);
  assert.ok(tips.some(([e, t]) => e === '🍎' && t.includes('零食')));
  assert.ok(!tips.some(([, t]) => t.includes('下一餐加一份蛋')));
});

test('buildAdvice: 三餐未齐 → 餐次方向（下一餐加蛋）', () => {
  const ctx = makeAdviceCtx({
    summary: { kcal: 300, target: 1800, carb: 40, protein: 10, fat: 8, water: 8 },
    exerciseKcal: 0,
    records: [{ meal: 'breakfast' }],
    isToday: true, weightKg: 60, waterGoalMl: 1600,
  });
  const tips = buildAdvice(ctx);
  assert.ok(!ctx.allMealsDone);
  assert.ok(tips.some(([e]) => e === '🥚'));
});

test('buildAdvice: 无记录 → 引导记录；且最多 3 条', () => {
  const ctx = makeAdviceCtx({
    summary: { kcal: 0, target: 1800, carb: 0, protein: 0, fat: 0, water: 0 },
    exerciseKcal: 0, records: [], isToday: true, weightKg: 60, waterGoalMl: 1600,
  });
  const tips = buildAdvice(ctx);
  assert.equal(tips[0][0], '📝');
  assert.ok(tips.length <= 3);
  assert.equal(WATER_CUP_ML, 200);
});

/* ---------- 二期：BIA 体成分估算 ---------- */
test('biaEstimate: 男性典型输入落在合理区间且肌肉率=0.948*(100-体脂)', () => {
  const r = biaEstimate({ weightKg: 78.7, heightCm: 172, age: 21, sexMale: true, impedanceOhm: 500 });
  assert.ok(r, '应返回结果');
  assert.ok(r.bodyFatPct > 8 && r.bodyFatPct < 35, `体脂率离谱: ${r.bodyFatPct}`);
  assert.equal(r.musclePct, +((0.948 * (100 - r.bodyFatPct)).toFixed(1)));
});

test('biaEstimate: 阻抗越大体脂越高（同人身）', () => {
  const base = { weightKg: 78.7, heightCm: 172, age: 21, sexMale: true };
  const lo = biaEstimate({ ...base, impedanceOhm: 400 });
  const hi = biaEstimate({ ...base, impedanceOhm: 600 });
  assert.ok(hi.bodyFatPct > lo.bodyFatPct);
});

test('biaEstimate: 非法输入返回 null；极端阻抗钳制在 5–80', () => {
  assert.equal(biaEstimate({ weightKg: 78.7, heightCm: 172, age: 21, sexMale: true, impedanceOhm: 0 }), null);
  assert.equal(biaEstimate({ weightKg: 1, heightCm: 172, age: 21, sexMale: true, impedanceOhm: 500 }), null);
  assert.equal(biaEstimate({ weightKg: 78.7, heightCm: 300, age: 21, sexMale: true, impedanceOhm: 500 }), null);
  const extreme = biaEstimate({ weightKg: 78.7, heightCm: 172, age: 21, sexMale: true, impedanceOhm: 5000 });
  assert.ok(extreme.bodyFatPct <= 80 && extreme.bodyFatPct >= 5);
});

test('biaEstimate: 女性分支独立且合理', () => {
  const r = biaEstimate({ weightKg: 55, heightCm: 162, age: 25, sexMale: false, impedanceOhm: 600 });
  assert.ok(r.bodyFatPct > 15 && r.bodyFatPct < 45, `女性体脂率离谱: ${r.bodyFatPct}`);
});

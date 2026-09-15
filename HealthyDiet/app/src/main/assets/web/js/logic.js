/* ============================================================
 * 食光 · 纯领域逻辑（ES Module，无 DOM / 无全局 state / 可单测）
 * ------------------------------------------------------------
 * 只放「输入→输出」的纯函数与数据表：代谢计算、运动消耗、份量换算、
 * 日期工具、宏量目标、实际缺口均值、每日建议规则表。
 * 渲染 / 事件 / 存储副作用一律留在 app.js，本文件可被 vitest/node 直接 import。
 * ============================================================ */

/* ---------- 餐次 ---------- */
export const MEAL_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];
export const MEAL_NAMES = { breakfast: '早餐', lunch: '午餐', dinner: '晚餐', snack: '零食' };
/* 餐次图标：实拍风格缩略图（assets/web/img/meals/*.jpg） */
export const MEAL_IMG = {
  breakfast: 'img/meals/breakfast.jpg',
  lunch: 'img/meals/lunch.jpg',
  dinner: 'img/meals/dinner.jpg',
  snack: 'img/meals/snack.jpg',
};

/* ---------- 喝水 ---------- */
export const WATER_CUP_ML = 200;
export const WATER_GOAL_MIN = 800;
export const WATER_GOAL_MAX = 3000;

/* ---------- 代谢 ---------- */
export const ACTIVITY = {
  sedentary: { f: 1.2,   label: '久坐' },
  light:     { f: 1.375, label: '轻度' },
  moderate:  { f: 1.55,  label: '中度' },
  active:    { f: 1.725, label: '重度' },
  extreme:   { f: 1.9,   label: '极大' },
};
export const KCAL_PER_KG = 7700;   // 减 1kg 体脂约需缺口
export const BODY_DEFAULT = { heightCm: 165, weightKg: 55, bmi: 20.2, age: 28, gender: 'female', activity: 'light', deficit: 500 };

/* ---------- 运动库（距离型 perKgKm；时长型 MET） ---------- */
export const EXERCISE_LIB = [
  { key: 'run',      name: '跑步',     emoji: '🏃', unit: 'km',  perKgKm: 1.036 },
  { key: 'walk',     name: '快走',     emoji: '🚶', unit: 'km',  perKgKm: 0.5 },
  { key: 'cycle',    name: '骑行',     emoji: '🚴', unit: 'km',  perKgKm: 0.35 },
  { key: 'swim',     name: '游泳',     emoji: '🏊', unit: 'min', met: 8 },
  { key: 'pushup',   name: '俯卧撑',   emoji: '💪', unit: 'min', met: 8 },
  { key: 'strength', name: '力量训练', emoji: '🏋️', unit: 'min', met: 5 },
  { key: 'yoga',     name: '瑜伽',     emoji: '🧘', unit: 'min', met: 2.5 },
  { key: 'rope',     name: '跳绳',     emoji: '🤸', unit: 'min', met: 11 },
  { key: 'hiit',     name: 'HIIT',     emoji: '🔥', unit: 'min', met: 8 },
  { key: 'ball',     name: '球类',     emoji: '🏀', unit: 'min', met: 7 },
];

/* ============================================================
 * 日期工具（本地时区安全：不用 toISOString，避免 UTC 偏移跳天）
 * ============================================================ */
export function localIso(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
export const todayIso = () => localIso(new Date());
/* 日期口语标签：今天/昨天/M月D日 */
export function dateLabelOf(iso) {
  const yd = new Date(); yd.setDate(yd.getDate() - 1);
  if (iso === localIso(yd)) return '昨天';
  const d = new Date(iso + 'T00:00:00');
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

/* ============================================================
 * 代谢计算（Mifflin-St Jeor）
 *   BMR 男 = 10W + 6.25H − 5A + 5；女 = 10W + 6.25H − 5A − 161
 *   TDEE = BMR × 活动系数；建议摄入 = max(TDEE − 缺口, 安全下限, BMR)
 *   达标时间 = (当前−目标)kg × 7700 ÷ 有效每日缺口
 * actualInfo = { avgDeficit, days }：近 N 天实际日均缺口（反馈3），不足时退回预设。
 * ============================================================ */
export function computeMetabolism(b, targetWeight, actualInfo) {
  const W = b.weightKg, H = b.heightCm, A = b.age;
  const bmr = Math.round(10 * W + 6.25 * H - 5 * A + (b.gender === 'male' ? 5 : -161));
  const f = (ACTIVITY[b.activity] || ACTIVITY.light).f;
  const tdee = Math.round(bmr * f);
  const floor = b.gender === 'male' ? 1500 : 1200;
  const suggest = Math.max(tdee - b.deficit, floor, bmr);
  const realDeficit = tdee - suggest;   // 预设缺口（建议值）
  const bmi = +(W / Math.pow(H / 100, 2)).toFixed(1);
  const need = +(W - (targetWeight || W)).toFixed(1);
  const useActual = !!actualInfo && actualInfo.avgDeficit > 0 && actualInfo.days >= 2;
  const effDeficit = useActual ? actualInfo.avgDeficit : realDeficit;
  let etaText;
  if (need <= 0) etaText = '已达标或目标不低于当前体重，维持当前摄入即可';
  else if (effDeficit <= 0) etaText = useActual
    ? '近期实际摄入无缺口（吃动持平），无法减重，可适当控制饮食或增加运动'
    : '当前摄入无缺口，无法减重，请提高缺口档位';
  else {
    const days = Math.ceil(need * KCAL_PER_KG / effDeficit);
    const weeks = Math.ceil(days / 7);
    const d = new Date(Date.now() + days * 86400000);
    const months = Math.round(days / 30.44);
    const span = months >= 12 ? `约 ${Math.floor(months / 12)} 年 ${months % 12} 个月` : `约 ${months} 个月`;
    etaText = `预计 ${weeks} 周（${span} · ${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日）减到 ${targetWeight}kg`;
    etaText += useActual
      ? ` · 按近 ${actualInfo.days} 天实际日均缺口 ${effDeficit} kcal 估算`
      : ` · 按预设缺口 ${effDeficit} kcal 估算（记录满 2 天后转为实际缺口）`;
    if (effDeficit * 7 / KCAL_PER_KG > 1) etaText += ' · 减重偏快，建议降为温和缺口';
  }
  const lo = (18.5 * Math.pow(H / 100, 2)).toFixed(1), hi = (23.9 * Math.pow(H / 100, 2)).toFixed(1);
  return { bmr, tdee, suggest, realDeficit, effDeficit, useActual, bmi, etaText, rangeText: `合理体重区间 ${lo}–${hi} kg（BMI 18.5–23.9）` };
}

/* 宏量目标（g）：按 50% 碳水 / 25% 蛋白 / 25% 脂肪 供能比估算 */
export function macroGoals(targetKcal) {
  return {
    carb: Math.round(targetKcal * .5 / 4),
    protein: Math.round(targetKcal * .25 / 4),
    fat: Math.round(targetKcal * .25 / 9),
  };
}

/* ============================================================
 * 运动消耗：距离型 = 系数 × 体重 × 距离；时长型 = MET × 3.5 × 体重 / 200 × 分钟
 * ============================================================ */
export function exerciseKcalOf(lib, amount, weightKg) {
  const w = weightKg || 55;
  return lib.unit === 'km'
    ? Math.round(lib.perKgKm * w * amount)
    : Math.round(lib.met * 3.5 * w / 200 * amount);
}

/* 每 100g 食物按克数换算宏量 */
export function portionMacros(food, grams) {
  const p = food.per100, k = grams / 100;
  return {
    kcal: Math.round(p.kcal * k),
    protein: +(p.protein * k).toFixed(1),
    carb: +(p.carb * k).toFixed(1),
    fat: +(p.fat * k).toFixed(1),
  };
}

/* ============================================================
 * 实际日均缺口：rows = [{ intake, exKcal }]（仅有记录的日子）
 *   日均缺口 = mean(TDEE + 运动 − 摄入)；不足 minDays 天返回 null（沿用预设）
 * ============================================================ */
export function avgDeficitFromRows(tdee, rows, minDays = 2) {
  if (!rows || rows.length < minDays) return null;
  const total = rows.reduce((a, d) => a + (tdee + (d.exKcal || 0) - (d.intake || 0)), 0);
  return { avgDeficit: Math.round(total / rows.length), days: rows.length, tdee };
}

/* ============================================================
 * 每日建议 · 规则表（反馈5/6：新增建议只需加一条规则）
 * ctx 字段：s(summary) ex budget remain goals pGap cGap isToday weightKg
 *           waterGoalMl wml allMealsDone
 * 每条规则 { id, when(ctx), tip(ctx) -> [emoji, text] }，按序命中即收集。
 * ============================================================ */
export const ADVICE_RULES = [
  { id: 'empty', when: c => c.s.kcal === 0,
    tip: c => ['📝', c.isToday ? '今天还没记录，去「记录」页点「记一笔」开始第一餐吧' : '这一天还没有记录，可在记录页切换日期查看'] },

  /* 三餐已齐 → 零食/加餐方向（不再提“下一餐”） */
  { id: 'snack-room', when: c => c.s.kcal > 0 && c.allMealsDone && c.remain >= 100,
    tip: c => ['🍎', `三餐已记录，今日额度还剩 ${c.remain} kcal，零食可选：水果一份、无糖酸奶、坚果一小把（约 20g）`] },
  { id: 'snack-tight', when: c => c.s.kcal > 0 && c.allMealsDone && c.remain > 0 && c.remain < 100,
    tip: c => ['🍵', `三餐已记录，额度仅剩 ${c.remain} kcal，若饿可喝无糖豆浆/黑咖啡，或明天再安排零食`] },
  { id: 'snack-over', when: c => c.s.kcal > 0 && c.allMealsDone && c.remain <= 0,
    tip: c => ['⚠️', `三餐已记录且超今日额度 ${-c.remain} kcal，快走 30 分钟约消耗 ${exerciseKcalOf(EXERCISE_LIB[1], 2.5, c.weightKg)} kcal，零食就先免了`] },
  { id: 'protein-snack', when: c => c.s.kcal > 0 && c.allMealsDone && c.pGap >= 15,
    tip: c => ['🥛', `蛋白质还差 ${c.pGap}g，加餐选高蛋白零食：希腊酸奶、水煮蛋、无糖豆浆`] },
  { id: 'fat-snack', when: c => c.s.kcal > 0 && c.allMealsDone && c.s.fat > c.goals.fat,
    tip: c => ['🍳', `脂肪已达目标 ${Math.round(c.s.fat / c.goals.fat * 100)}%，零食避开坚果/油炸，选水果或酸奶`] },

  /* 三餐未齐 → 餐次方向 */
  { id: 'meal-room', when: c => c.s.kcal > 0 && !c.allMealsDone && c.remain > 0,
    tip: c => ['🍽️', `还能吃 ${c.remain} kcal${c.pGap > 10 ? '，优先补蛋白：蛋、豆制品、鱼虾' : '，主食、蔬菜、蛋白均衡搭配'}`] },
  { id: 'meal-over', when: c => c.s.kcal > 0 && !c.allMealsDone && c.remain <= 0,
    tip: c => ['⚠️', `已超今日额度 ${-c.remain} kcal，快走 30 分钟约消耗 ${exerciseKcalOf(EXERCISE_LIB[1], 2.5, c.weightKg)} kcal，或明天稍减主食`] },
  { id: 'protein-meal', when: c => c.s.kcal > 0 && !c.allMealsDone && c.pGap >= 15,
    tip: c => ['🥚', `蛋白质还差 ${c.pGap}g，下一餐加一份蛋、豆制品或鱼虾`] },
  { id: 'fat-meal', when: c => c.s.kcal > 0 && !c.allMealsDone && c.s.fat > c.goals.fat,
    tip: c => ['🍳', `脂肪已达目标 ${Math.round(c.s.fat / c.goals.fat * 100)}%，剩余餐次选蒸煮、白切等少油做法`] },
  { id: 'carb', when: c => c.s.kcal > 0 && !c.allMealsDone && c.cGap >= 40,
    tip: c => ['🍚', `主食还差 ${c.cGap}g 碳水，不吃主食易乏力，保留适量谷物`] },

  /* 通用 */
  { id: 'water', when: c => c.isToday && c.wml < c.waterGoalMl,
    tip: c => ['💧', `喝水 ${c.wml}/${c.waterGoalMl}ml，记得少量多次补水`] },
];
/* 收尾规则：只有一条且已有摄入时补一条“均衡”肯定 */
export function buildAdvice(ctx) {
  const tips = ADVICE_RULES.filter(r => r.when(ctx)).map(r => r.tip(ctx));
  if (tips.length === 1 && ctx.s.kcal > 0) {
    tips.push(['✅', ctx.allMealsDone ? '三餐已记录且营养均衡，保持这个节奏' : '三大营养素都在合理区间，保持这个节奏']);
  }
  return tips.slice(0, 3);
}
/* 由 state 片段构造建议上下文（app.js 复用，保证 ctx 字段齐全） */
export function makeAdviceCtx({ summary, exerciseKcal = 0, records = [], isToday, weightKg = 55, waterGoalMl = 1600 }) {
  const s = summary;
  const budget = s.target + exerciseKcal;
  const goals = macroGoals(s.target);
  const logged = new Set((records || []).map(r => r.meal));
  return {
    s, ex: exerciseKcal, budget,
    remain: budget - s.kcal,
    goals,
    pGap: goals.protein - s.protein,
    cGap: goals.carb - s.carb,
    isToday,
    weightKg,
    waterGoalMl,
    wml: (s.water || 0) * WATER_CUP_ML,
    allMealsDone: ['breakfast', 'lunch', 'dinner'].every(m => logged.has(m)),
  };
}

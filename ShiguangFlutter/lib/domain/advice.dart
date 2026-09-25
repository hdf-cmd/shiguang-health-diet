// ShiguangFlutter/lib/domain/advice.dart
// 每日建议规则引擎。唯一权威源：js/logic.js:146-210，规则顺序与文案逐字移植。
// 反馈5/6：新增建议只需在 [adviceRules] 加一条规则。
// ctx 字段：s(summary) ex budget remain goals pGap cGap isToday weightKg
//           waterGoalMl wml allMealsDone
// 每条规则 { id, when(ctx), tip(ctx) -> (emoji, text) }，按序命中即收集。
// 分层铁律：本文件不得 import package:flutter。
import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/exercise.dart';
import 'package:shiguang_flutter/domain/js_compat.dart';
import 'package:shiguang_flutter/domain/metabolism.dart';
import 'package:shiguang_flutter/domain/models.dart';

/// 建议上下文（字段与 JS ctx 同名；comp 参数已随体成分下线，不带回来）
class AdviceCtx {
  const AdviceCtx({
    required this.s,
    required this.ex,
    required this.budget,
    required this.remain,
    required this.goals,
    required this.pGap,
    required this.cGap,
    required this.isToday,
    required this.weightKg,
    required this.waterGoalMl,
    required this.wml,
    required this.allMealsDone,
  });

  final Summary s;
  final num ex;
  final num budget;
  final num remain;
  final MacroGoals goals;
  final num pGap;
  final num cGap;
  final bool isToday;
  final num weightKg;
  final num waterGoalMl;
  final num wml;
  final bool allMealsDone;
}

/// 单条建议规则：命中 [when] 则产出 (emoji, text)
class AdviceRule {
  const AdviceRule({required this.id, required this.when, required this.tip});

  final String id;
  final bool Function(AdviceCtx) when;
  final (String, String) Function(AdviceCtx) tip;
}

final adviceRules = <AdviceRule>[
  AdviceRule(
      id: 'empty',
      when: (c) => c.s.kcal == 0,
      tip: (c) => (
            '📝',
            c.isToday
                ? '今天还没记录，去「记录」页点「记一笔」开始第一餐吧'
                : '这一天还没有记录，可在记录页切换日期查看'
          )),

  /* 三餐已齐 → 零食/加餐方向（不再提“下一餐”） */
  AdviceRule(
      id: 'snack-room',
      when: (c) => c.s.kcal > 0 && c.allMealsDone && c.remain >= 100,
      tip: (c) => (
            '🍎',
            '三餐已记录，今日额度还剩 ${jsNumText(c.remain)} kcal，'
                '零食可选：水果一份、无糖酸奶、坚果一小把（约 20g）'
          )),
  AdviceRule(
      id: 'snack-tight',
      when: (c) =>
          c.s.kcal > 0 && c.allMealsDone && c.remain > 0 && c.remain < 100,
      tip: (c) => (
            '🍵',
            '三餐已记录，额度仅剩 ${jsNumText(c.remain)} kcal，'
                '若饿可喝无糖豆浆/黑咖啡，或明天再安排零食'
          )),
  AdviceRule(
      id: 'snack-over',
      when: (c) => c.s.kcal > 0 && c.allMealsDone && c.remain <= 0,
      tip: (c) => (
            '⚠️',
            '三餐已记录且超今日额度 ${jsNumText(-c.remain)} kcal，'
                '快走 30 分钟约消耗 ${exerciseKcalOf(exerciseLib[1], 2.5, c.weightKg)} kcal，零食就先免了'
          )),
  AdviceRule(
      id: 'protein-snack',
      when: (c) => c.s.kcal > 0 && c.allMealsDone && c.pGap >= 15,
      tip: (c) => (
            '🥛',
            '蛋白质还差 ${jsNumText(c.pGap)}g，加餐选高蛋白零食：希腊酸奶、水煮蛋、无糖豆浆'
          )),
  AdviceRule(
      id: 'fat-snack',
      when: (c) => c.s.kcal > 0 && c.allMealsDone && c.s.fat > c.goals.fat,
      tip: (c) => (
            '🍳',
            '脂肪已达目标 ${jsRound(c.s.fat / c.goals.fat * 100)}%，零食避开坚果/油炸，选水果或酸奶'
          )),

  /* 三餐未齐 → 餐次方向 */
  AdviceRule(
      id: 'meal-room',
      when: (c) => c.s.kcal > 0 && !c.allMealsDone && c.remain > 0,
      tip: (c) => (
            '🍽️',
            '还能吃 ${jsNumText(c.remain)} kcal'
                '${c.pGap > 10 ? '，优先补蛋白：蛋、豆制品、鱼虾' : '，主食、蔬菜、蛋白均衡搭配'}'
          )),
  AdviceRule(
      id: 'meal-over',
      when: (c) => c.s.kcal > 0 && !c.allMealsDone && c.remain <= 0,
      tip: (c) => (
            '⚠️',
            '已超今日额度 ${jsNumText(-c.remain)} kcal，'
                '快走 30 分钟约消耗 ${exerciseKcalOf(exerciseLib[1], 2.5, c.weightKg)} kcal，或明天稍减主食'
          )),
  AdviceRule(
      id: 'protein-meal',
      when: (c) => c.s.kcal > 0 && !c.allMealsDone && c.pGap >= 15,
      tip: (c) => (
            '🥚',
            '蛋白质还差 ${jsNumText(c.pGap)}g，下一餐加一份蛋、豆制品或鱼虾'
          )),
  AdviceRule(
      id: 'fat-meal',
      when: (c) => c.s.kcal > 0 && !c.allMealsDone && c.s.fat > c.goals.fat,
      tip: (c) => (
            '🍳',
            '脂肪已达目标 ${jsRound(c.s.fat / c.goals.fat * 100)}%，剩余餐次选蒸煮、白切等少油做法'
          )),
  AdviceRule(
      id: 'carb',
      when: (c) => c.s.kcal > 0 && !c.allMealsDone && c.cGap >= 40,
      tip: (c) => (
            '🍚',
            '主食还差 ${jsNumText(c.cGap)}g 碳水，不吃主食易乏力，保留适量谷物'
          )),

  /* 通用 */
  AdviceRule(
      id: 'water',
      when: (c) => c.isToday && c.wml < c.waterGoalMl,
      tip: (c) => (
            '💧',
            '喝水 ${jsNumText(c.wml)}/${jsNumText(c.waterGoalMl)}ml，记得少量多次补水'
          )),
];

/// 收尾规则：只有一条且已有摄入时补一条“均衡”肯定（对齐 JS buildAdvice）
List<(String, String)> buildAdvice(AdviceCtx ctx) {
  final tips =
      adviceRules.where((r) => r.when(ctx)).map((r) => r.tip(ctx)).toList();
  if (tips.length == 1 && ctx.s.kcal > 0) {
    tips.add(('✅',
        ctx.allMealsDone ? '三餐已记录且营养均衡，保持这个节奏' : '三大营养素都在合理区间，保持这个节奏'));
  }
  return tips.take(3).toList();
}

/// 由数据片段构造建议上下文（对齐 JS makeAdviceCtx，保证 ctx 字段齐全）
AdviceCtx makeAdviceCtx({
  required Summary summary,
  num exerciseKcal = 0,
  List<Map> records = const [],
  required bool isToday,
  num weightKg = 55,
  num waterGoalMl = 1600,
}) {
  final s = summary;
  final budget = s.target + exerciseKcal;
  final goals = macroGoals(s.target);
  final logged = records.map((r) => r['meal']).toSet();
  return AdviceCtx(
    s: s,
    ex: exerciseKcal,
    budget: budget,
    remain: budget - s.kcal,
    goals: goals,
    pGap: goals.protein - s.protein,
    cGap: goals.carb - s.carb,
    isToday: isToday,
    weightKg: weightKg,
    waterGoalMl: waterGoalMl,
    wml: s.water * waterCupMl,
    allMealsDone:
        const ['breakfast', 'lunch', 'dinner'].every((m) => logged.contains(m)),
  );
}

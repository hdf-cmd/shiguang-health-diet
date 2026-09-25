// ShiguangFlutter/test/domain/metabolism_test.dart
// 逐条移植自 H5 单测（期望值逐字照抄）：
//   tests/logic.test.js #1 computeMetabolism BMR/TDEE/建议摄入
//   tests/logic.test.js #2 实际缺口 > 预设时达标时间更短（反馈3）
//   tests/logic.test.js #3 实际数据不足 2 天 → 退回预设缺口
//   tests/logic.test.js #4 无需减重时给出维持提示
//   tests/logic.test.js #5 macroGoals 1800kcal
//   tests/nutrition.test.js macroGoals 3 条 + computeMetabolism 3 条
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/metabolism.dart';
import 'package:shiguang_flutter/domain/models.dart';

final body = Body(
    heightCm: 165, weightKg: 60, age: 28,
    gender: 'female', activity: 'light', deficit: 500);

/// JS: Number(t.match(/预计 (\d+) 周/)[1])
int _weeksOf(String eta) {
  final m = RegExp(r'预计 (\d+) 周').firstMatch(eta);
  expect(m, isNotNull, reason: 'etaText 应包含「预计 N 周」');
  return int.parse(m![1]!);
}

void main() {
  test('computeMetabolism: BMR/TDEE/建议摄入 符合 Mifflin-St Jeor 与安全下限', () {
    final m = computeMetabolism(body, 52);
    // BMR = 10*60 + 6.25*165 - 5*28 - 161 = 1330.25 → 1330
    expect(m.bmr, 1330);
    // TDEE = 1330 * 1.375 = 1828.75 → 1829
    expect(m.tdee, 1829);
    // suggest = max(1829-500, 1200, 1330) = 1330（被 BMR 下限托住）
    expect(m.suggest, 1330);
    expect(m.realDeficit, m.tdee - m.suggest);
    expect(m.etaText.contains('减到 52kg'), isTrue);
  });

  test('computeMetabolism: 实际缺口 > 预设时达标时间更短（反馈3）', () {
    final preset = computeMetabolism(body, 52);
    final actual = computeMetabolism(body, 52, {'avgDeficit': 800, 'days': 3});
    expect(actual.useActual, true);
    expect(actual.effDeficit, 800);
    expect(actual.etaText.contains('按近 3 天实际日均缺口 800 kcal 估算'), isTrue);
    // 实际缺口更大 → 天数更少
    expect(_weeksOf(actual.etaText) < _weeksOf(preset.etaText), isTrue);
  });

  test('computeMetabolism: 实际数据不足 2 天 → 退回预设缺口', () {
    final m = computeMetabolism(body, 52, {'avgDeficit': 800, 'days': 1});
    expect(m.useActual, false);
    expect(m.effDeficit, m.realDeficit);
  });

  test('computeMetabolism: 无需减重时给出维持提示', () {
    final m = computeMetabolism(body, 60);
    expect(m.etaText.contains('维持当前摄入'), isTrue);
  });

  test('macroGoals: 1800kcal → 碳水225/蛋白113/脂肪50', () {
    expect(macroGoals(1800),
        const MacroGoals(carb: 225, protein: 113, fat: 50));
  });

  /* ---------- 来自 nutrition.test.js：macroGoals ---------- */

  test('macroGoals: 按 50/25/25 供能比换算（碳水4、蛋白4、脂肪9 kcal/g）', () {
    expect(macroGoals(2000), const MacroGoals(carb: 250, protein: 125, fat: 56));
    // carb = 2000*0.5/4 = 250；protein = 2000*0.25/4 = 125；fat = 2000*0.25/9 = 55.56 → 56
  });

  test('macroGoals: 回算热量与目标基本一致（仅四舍五入误差）', () {
    // 三项各自最多 ±0.5g：碳水/蛋白 ±2 kcal、脂肪 ±4.5 kcal，合计理论上限约 ±8.5 kcal
    for (final target in [1200, 1500, 1800, 2000, 2500]) {
      final g = macroGoals(target);
      final back = g.carb * 4 + g.protein * 4 + g.fat * 9;
      expect((back - target).abs() <= 10, isTrue,
          reason: '$target kcal 回算得 $back kcal，偏差过大');
    }
  });

  test('macroGoals: 边界值 0 与高热量', () {
    expect(macroGoals(0), const MacroGoals(carb: 0, protein: 0, fat: 0));
    expect(macroGoals(3000), const MacroGoals(carb: 375, protein: 188, fat: 83));
  });

  /* ---------- 来自 nutrition.test.js：computeMetabolism ---------- */

  test('computeMetabolism: 男性 BMR 公式（+5）与未被下限托住的正常档', () {
    final male = Body(
        heightCm: 175, weightKg: 80, age: 30,
        gender: 'male', activity: 'light', deficit: 500);
    final m = computeMetabolism(male, 70);
    // BMR = 10*80 + 6.25*175 - 5*30 + 5 = 1748.75 → 1749
    expect(m.bmr, 1749);
    // TDEE = 1749 * 1.375 = 2404.875 → 2405
    expect(m.tdee, 2405);
    // suggest = max(2405-500, 男性下限1500, BMR 1749) = 1905（未被下限托住）
    expect(m.suggest, 1905);
    expect(m.realDeficit, 500);
    expect(m.useActual, false);
  });

  test('computeMetabolism: 女性安全下限 1200 生效于极端缺口', () {
    final aggressive = Body(
        heightCm: 165, weightKg: 60, age: 28,
        gender: 'female', activity: 'light', deficit: 2000);
    final m = computeMetabolism(aggressive, 52);
    // BMR = 1330，suggest = max(1829-2000, 1200, 1330) = 1330 —— 由 BMR 托底（BMR 高于 1200 下限）
    expect(m.suggest, 1330);
    expect(m.suggest >= m.bmr, isTrue, reason: '建议摄入不得低于基础代谢');
  });

  test('computeMetabolism: 未提供目标体重时按当前体重（缺口为 0，给出维持提示）', () {
    final m = computeMetabolism(body, null);
    expect(m.etaText.contains('维持当前摄入'), isTrue);
  });
}

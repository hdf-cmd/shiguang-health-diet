// ShiguangFlutter/test/domain/advice_test.dart
// 逐条移植自 tests/logic.test.js #10/#11/#12（buildAdvice 全部 3 条用例）。
// JS [emoji, text] 二元素数组 → Dart record (String, String)。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/advice.dart';
import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/models.dart';

void main() {
  test('buildAdvice: 三餐已记录 → 零食方向（反馈5）', () {
    final ctx = makeAdviceCtx(
      summary: const Summary(
          kcal: 1500, target: 1800, carb: 180, protein: 60, fat: 45, water: 8),
      exerciseKcal: 0,
      records: const [
        {'meal': 'breakfast'},
        {'meal': 'lunch'},
        {'meal': 'dinner'}
      ],
      isToday: true,
      weightKg: 60,
      waterGoalMl: 1600,
    );
    final tips = buildAdvice(ctx);
    expect(ctx.allMealsDone, isTrue);
    expect(tips.any((t) => t.$1 == '🍎' && t.$2.contains('零食')), isTrue);
    expect(tips.any((t) => t.$2.contains('下一餐加一份蛋')), isFalse);
  });

  test('buildAdvice: 三餐未齐 → 餐次方向（下一餐加蛋）', () {
    final ctx = makeAdviceCtx(
      summary: const Summary(
          kcal: 300, target: 1800, carb: 40, protein: 10, fat: 8, water: 8),
      exerciseKcal: 0,
      records: const [
        {'meal': 'breakfast'}
      ],
      isToday: true,
      weightKg: 60,
      waterGoalMl: 1600,
    );
    final tips = buildAdvice(ctx);
    expect(ctx.allMealsDone, isFalse);
    expect(tips.any((t) => t.$1 == '🥚'), isTrue);
  });

  test('buildAdvice: 无记录 → 引导记录；且最多 3 条', () {
    final ctx = makeAdviceCtx(
      summary: const Summary(
          kcal: 0, target: 1800, carb: 0, protein: 0, fat: 0, water: 0),
      exerciseKcal: 0,
      records: const [],
      isToday: true,
      weightKg: 60,
      waterGoalMl: 1600,
    );
    final tips = buildAdvice(ctx);
    expect(tips.first.$1, '📝');
    expect(tips.length <= 3, isTrue);
    expect(waterCupMl, 200);
  });
}

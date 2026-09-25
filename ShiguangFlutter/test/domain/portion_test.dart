// ShiguangFlutter/test/domain/portion_test.dart
// 逐条移植自 tests/logic.test.js #7 与 tests/nutrition.test.js portionMacros 5 条。
// 期望值逐字照抄，含 JS 浮点语义用例（25.9*1.5=38.85→"38.8"、0.3*1.5=0.45→"0.4"，
// 二者在 Dart 同为 IEEE754 双精度且 toStringAsFixed 按实际二进制值舍入，结果一致）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/models.dart';
import 'package:shiguang_flutter/domain/portion.dart';

const f100 = Per100(kcal: 100, protein: 10, carb: 10, fat: 10);
const rice = Per100(kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3); // 贴近米饭量级

void main() {
  test('portionMacros: per100 按克数线性换算（logic.test.js #7）', () {
    expect(portionMacros(f100, 200),
        const PortionResult(kcal: 200, protein: 20, carb: 20, fat: 20));
    expect(portionMacros(f100, 50),
        const PortionResult(kcal: 50, protein: 5, carb: 5, fat: 5));
  });

  test('portionMacros: 100g 即 per100 原值', () {
    expect(portionMacros(rice, 100),
        const PortionResult(kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3));
  });

  test('portionMacros: 150g 按比例换算（热量取整、宏量保留一位小数）', () {
    expect(
        portionMacros(rice, 150),
        const PortionResult(kcal: 174, protein: 3.9, carb: 38.8, fat: 0.4));
    // 116*1.5=174；2.6*1.5=3.9；25.9*1.5=38.85→"38.8"（浮点下溢）；0.3*1.5=0.45→"0.4"
  });

  test('portionMacros: 0g 与极小克数', () {
    expect(portionMacros(rice, 0),
        const PortionResult(kcal: 0, protein: 0, carb: 0, fat: 0));
    final tiny = portionMacros(rice, 1);
    expect(tiny.kcal, 1); // round(1.16)
    expect(tiny.carb, 0.3); // 0.259 → 一位小数
  });

  test('portionMacros: 大克数（500g）与小数克数', () {
    expect(portionMacros(rice, 500),
        const PortionResult(kcal: 580, protein: 13, carb: 129.5, fat: 1.5));
    expect(portionMacros(rice, 37.5),
        const PortionResult(kcal: 44, protein: 1, carb: 9.7, fat: 0.1));
  });

  test('portionMacros: 宏量保留一位小数（不出现长尾浮点）', () {
    final p = portionMacros(
        const Per100(kcal: 137, protein: 7.33, carb: 11.11, fat: 3.33), 133);
    int decimalsOf(double v) {
      final s = '$v';
      final dot = s.indexOf('.');
      return dot < 0 ? 0 : s.length - dot - 1;
    }
    for (final entry in {
      'protein': p.protein, 'carb': p.carb, 'fat': p.fat
    }.entries) {
      expect(decimalsOf(entry.value) <= 1, isTrue,
          reason: '${entry.key}=${entry.value} 小数位过多');
    }
  });
}

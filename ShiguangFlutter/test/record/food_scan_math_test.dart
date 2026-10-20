// ShiguangFlutter/test/record/food_scan_math_test.dart
// M13-T5 钉：识菜结果按克数等比换算——kcal 取整、蛋白/碳水/脂肪 1 位小数。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/record/food_scan_math.dart';

void main() {
  test('按克数等比换算：kcal 取整、三大营养素 1 位小数', () {
    final t = scanPortionTotals(
        {'kcal': 156, 'protein': 8.6, 'carb': 7.4, 'fat': 9.8}, 200);
    expect(t.kcal, 312);
    expect(t.protein, 17.2);
    expect(t.carb, 14.8);
    expect(t.fat, 19.6);
  });

  test('非整百克数与 0g 边界', () {
    final t = scanPortionTotals(
        {'kcal': 156, 'protein': 8.6, 'carb': 7.4, 'fat': 9.8}, 137);
    expect(t.kcal, 214); // 213.72
    expect(
        scanPortionTotals(
                {'kcal': 156, 'protein': 8.6, 'carb': 7.4, 'fat': 9.8}, 0)
            .kcal,
        0);
  });
}

// ShiguangFlutter/test/record/food_scan_math_test.dart
// M13-T5 钉：识菜结果按克数等比换算——kcal 取整、蛋白/碳水/脂肪 1 位小数。
// M13-T6：舍入口径统一走 domain/js_compat 的 jsRound/jsFixed1（与
// domain/portion.dart:portionMacros 同一 H5 权威源），补边界断言钉死两条路同值。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/models.dart' show Per100;
import 'package:shiguang_flutter/domain/portion.dart' show portionMacros;
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

  test('舍入与 portionMacros 同口径（jsRound/jsFixed1）', () {
    // 0.7×1.5=1.0499999999999998：两条路必须同值（控制者裁定的边界断言）
    const per100 = {'kcal': 156, 'protein': 0.7, 'carb': 0.7, 'fat': 0.7};
    final t = scanPortionTotals(per100, 150);
    final ref = portionMacros(
        const Per100(kcal: 156, protein: 0.7, carb: 0.7, fat: 0.7), 150);
    expect(t.kcal, ref.kcal.toInt());
    expect(t.protein, ref.protein);
    expect(t.carb, ref.carb);
    expect(t.fat, ref.fat);

    // 7.35 是 (v*10).round() 与 JS toFixed(1) 分道的边界：
    // 7.35 的 double 实值略小于 7.35，JS/H5 得 7.3；旧 _round1 会得 7.4。
    final edge = scanPortionTotals(
        const {'kcal': 0, 'protein': 7.35, 'carb': 0, 'fat': 0}, 100);
    expect(edge.protein, 7.3);
    expect(
      edge.protein,
      portionMacros(
              const Per100(kcal: 0, protein: 7.35, carb: 0, fat: 0), 100)
          .protein,
    );
  });
}

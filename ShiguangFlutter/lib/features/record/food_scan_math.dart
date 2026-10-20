// ShiguangFlutter/lib/features/record/food_scan_math.dart
// M13-T5：识菜结果「每 100g 营养」→「这一份营养」的等比换算。
//
// 为什么单独抽纯函数：扫描结果落库前要按用户改过的克数重算，而 kcal 是整数
// 字段、三大营养素各留 1 位小数（与手记/展示同规）；换算规则集中在一处，
// UI 与保存链只需喂 (per100, grams)，避免各入口各算一套产生漂移。

/// 保留 1 位小数（四舍五入）。
double _round1(double v) => (v * 10).round() / 10;

/// 按克数等比换算一份的营养。
///
/// [per100] 为每 100g 的数值（键：kcal/protein/carb/fat，缺键按 0 处理）；
/// [grams] 为这一份的克数。返回 kcal 取整、蛋白/碳水/脂肪 1 位小数。
({int kcal, double protein, double carb, double fat}) scanPortionTotals(
    Map<String, num> per100, int grams) {
  final scale = grams / 100;
  num at(String k) => per100[k] ?? 0;
  return (
    kcal: (at('kcal') * scale).round(),
    protein: _round1((at('protein') * scale).toDouble()),
    carb: _round1((at('carb') * scale).toDouble()),
    fat: _round1((at('fat') * scale).toDouble()),
  );
}

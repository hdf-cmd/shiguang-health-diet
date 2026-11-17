// 「描述一餐」复核层的纯换算逻辑。不得 import flutter，便于单测。
//
// 规则：用户说了克/毫升就用它；说了个数/份数就乘命中食物的默认份量；
// 什么都没说就用食物自己的默认份量（没有则 100g）。没有 per100 的记录
// 按「份」处理，初始 1 份。

import 'models.dart' show Per100;

/// 每 100g/ml 营养按「这一份」换算后的表单值。
class ServingNutrition {
  const ServingNutrition({
    required this.grams,
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
  });

  final double grams;
  final double kcal;
  final double protein;
  final double carb;
  final double fat;
}

ServingNutrition servingNutritionFromPer100(
  Map<String, dynamic> per100, {
  double? grams,
}) {
  final g = (grams != null && grams > 0) ? grams : 100.0;
  final p = Per100.fromMap(Map<String, Object?>.from(per100));
  final k = g / 100;
  double round1(double v) => (v * 10).round() / 10;
  return ServingNutrition(
    grams: g,
    kcal: (p.kcal * k).roundToDouble(),
    protein: round1(p.protein * k),
    carb: round1(p.carb * k),
    fat: round1(p.fat * k),
  );
}

double initialMealAmount(
  Map<String, dynamic> item,
  Map<String, dynamic>? match,
) {
  final q = (item['quantity'] as num?)?.toDouble();
  final unit = '${item['unit'] ?? ''}';
  final per100 = match?['per100'];
  if (per100 is Map) {
    final baseG = (match?['baseG'] as num?)?.toDouble();
    final fallback = (baseG != null && baseG > 0) ? baseG : 100.0;
    if (unit == 'g' || unit == 'ml') return q ?? fallback;
    if (q != null) return q * fallback;
    return fallback;
  }
  return q != null && q > 0 ? q : 1;
}

/// 份量文本：整数不带小数点，其余保留一位。
String formatMealAmount(num v) => v == v.roundToDouble()
    ? '${v.round()}'
    : v.toStringAsFixed(1);

/// 候选列表：优先用云端返回的 `matches`，旧响应只有 `match` 时退化为单候选。
List<Map<String, dynamic>> mealMatchesOf(
  Map<String, dynamic> item,
  Map<String, dynamic>? match,
) {
  final raw = item['matches'];
  if (raw is List) {
    final list = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (list.isNotEmpty) return list;
  }
  return match == null ? const <Map<String, dynamic>>[] : [match];
}

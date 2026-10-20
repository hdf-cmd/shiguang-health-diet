// ShiguangFlutter/lib/features/record/food_scan_math.dart
// M13-T5：识菜结果「每 100g 营养」→「这一份营养」的等比换算。
// M13-T6：舍入改走 domain/js_compat 的 jsRound/jsFixed1——与
// domain/portion.dart:portionMacros 同一 H5 权威口径（js/logic.js:125-134）。
// 为什么单抽纯函数：扫描结果落库前要按用户改过的克数重算，而 kcal 是整数
// 字段、三大营养素各留 1 位小数（与手记/展示同规）；换算规则集中在一处，
// UI 与保存链只需喂 (per100, grams)，避免各入口各算一套产生漂移。
// 口径要点：jsFixed1 是 JS +(v).toFixed(1)（按十进制串四舍五入），不是
// (v*10).round()/10——7.35 这类边界两者差 0.1（H5 得 7.3，旧法得 7.4）。
import '../../domain/js_compat.dart' show jsFixed1, jsRound;

/// 按克数等比换算一份的营养。
///
/// [per100] 为每 100g 的数值（键：kcal/protein/carb/fat，缺键按 0 处理）；
/// [grams] 为这一份的克数。返回 kcal 取整（jsRound）、蛋白/碳水/脂肪
/// 1 位小数（jsFixed1），与 portionMacros 逐值同口径。
({int kcal, double protein, double carb, double fat}) scanPortionTotals(
    Map<String, num> per100, int grams) {
  final scale = grams / 100;
  num at(String k) => per100[k] ?? 0;
  return (
    kcal: jsRound(at('kcal') * scale),
    protein: jsFixed1(at('protein') * scale),
    carb: jsFixed1(at('carb') * scale),
    fat: jsFixed1(at('fat') * scale),
  );
}

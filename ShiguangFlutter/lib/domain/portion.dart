// ShiguangFlutter/lib/domain/portion.dart
// 份量换算。唯一权威源：js/logic.js:125-134：每 100g 食物按克数换算宏量。
// 分层铁律：本文件不得 import package:flutter。
import 'package:shiguang_flutter/domain/js_compat.dart';
import 'package:shiguang_flutter/domain/models.dart';

/// portionMacros 返回值（kcal 取整；三大营养素保留一位小数，字段名与云函数一致）
class PortionResult {
  const PortionResult({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
  });

  final double kcal;
  final double protein;
  final double carb;
  final double fat;

  @override
  bool operator ==(Object other) =>
      other is PortionResult &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.carb == carb &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(kcal, protein, carb, fat);

  @override
  String toString() =>
      'PortionResult(kcal: $kcal, protein: $protein, carb: $carb, fat: $fat)';
}

/// 每 100g 营养 [p] 按 [grams] 克线性换算（对齐 js/logic.js portionMacros）
PortionResult portionMacros(Per100 p, num grams) {
  final k = grams / 100;
  return PortionResult(
    kcal: jsRound(p.kcal * k).toDouble(),
    protein: jsFixed1(p.protein * k),
    carb: jsFixed1(p.carb * k),
    fat: jsFixed1(p.fat * k),
  );
}

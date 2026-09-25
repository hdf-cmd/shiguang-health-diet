// ShiguangFlutter/lib/domain/exercise.dart
// 运动消耗。唯一权威源：js/logic.js:115-123。
//   距离型 = 系数 × 体重 × 距离；时长型 = MET × 3.5 × 体重 / 200 × 分钟
// 乘法顺序与 JS 逐字一致，保证浮点结果逐位相同。
// 分层铁律：本文件不得 import package:flutter。
import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/js_compat.dart';

/// [weightKg] 为 null（JS undefined）或 0（JS falsy）时回退 55kg
int exerciseKcalOf(Exercise lib, num amount, num? weightKg) {
  final w = (weightKg == null || weightKg == 0) ? 55 : weightKg;
  return lib.unit == 'km'
      ? jsRound(lib.perKgKm! * w * amount)
      : jsRound(lib.met! * 3.5 * w / 200 * amount);
}

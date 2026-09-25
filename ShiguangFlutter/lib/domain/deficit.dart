// ShiguangFlutter/lib/domain/deficit.dart
// 实际日均缺口。唯一权威源：js/logic.js:136-144。
//   rows = [{ intake, exKcal }]（仅有记录的日子）
//   日均缺口 = mean(TDEE + 运动 − 摄入)；不足 minDays 天返回 null（沿用预设）
// 分层铁律：本文件不得 import package:flutter。
import 'package:shiguang_flutter/domain/js_compat.dart';

/// 返回 { avgDeficit, days, tdee } 或 null（对齐 JS `if (!rows || rows.length < minDays) return null`）
Map<String, Object>? avgDeficitFromRows(num tdee, List<Map>? rows,
    [int minDays = 2]) {
  if (rows == null || rows.length < minDays) return null;
  final total = rows.fold<num>(
      0, (a, d) => a + (tdee + (d['exKcal'] as num? ?? 0) - (d['intake'] as num? ?? 0)));
  return {
    'avgDeficit': jsRound(total / rows.length),
    'days': rows.length,
    'tdee': tdee,
  };
}

// ShiguangFlutter/lib/domain/deficit.dart
// 实际日均缺口。唯一权威源：js/logic.js:136-144。
//   rows = [{ intake, exKcal }]（仅有记录的日子）
//   日均缺口 = mean(TDEE + 运动 − 摄入)；不足 minDays 天返回 null（沿用预设）
// 分层铁律：本文件不得 import package:flutter。
import 'dart:math' as math;

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

/// 实测优先版：当天有手表全天活动时，TDEE = BMR + max(手表活动, 运动记录)
/// （戴表时手表通常≥记录不双算，手动补录多出来的部分也能生效）；
/// 没有手表数据的日期回落 [fallbackTdee] + exKcal（旧口径，手动记录照常生效）。
/// [watchActiveKcalByDate] 为 date(YYYY-MM-DD) → 全天活动热量。
Map<String, Object>? avgDeficitFromRowsSmart(
  num fallbackTdee,
  num bmr,
  Map<String, num> watchActiveKcalByDate,
  List<Map>? rows,
  [int minDays = 2]
) {
  if (rows == null || rows.length < minDays) return null;
  var activeDays = 0;
  final total = rows.fold<num>(0, (a, d) {
    final date = '${d['date'] ?? ''}';
    final watch = watchActiveKcalByDate[date] ?? 0;
    final ex = d['exKcal'] as num? ?? 0;
    final intake = d['intake'] as num? ?? 0;
    if (watch > 0) {
      activeDays++;
      return a + (bmr + math.max(watch, ex) - intake);
    }
    return a + (fallbackTdee + ex - intake);
  });
  return {
    'avgDeficit': jsRound(total / rows.length),
    'days': rows.length,
    'tdee': fallbackTdee,
    // 只在确有实测活动的天携带，保持旧口径 map 形状不变。
    if (activeDays > 0) 'activeDays': activeDays,
  };
}

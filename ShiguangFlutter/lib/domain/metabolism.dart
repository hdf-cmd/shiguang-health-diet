// ShiguangFlutter/lib/domain/metabolism.dart
// 代谢引擎与宏量目标。唯一权威源：js/logic.js:66-113，公式与文案逐字移植。
//   BMR 男 = 10W + 6.25H − 5A + 5；女 = 10W + 6.25H − 5A − 161（Mifflin-St Jeor）
//   TDEE = BMR × 活动系数；建议摄入 = max(TDEE − 缺口, 安全下限, BMR)
//   达标时间 = (当前−目标)kg × 7700 ÷ 有效每日缺口
// actualInfo = { avgDeficit, days }：近 N 天实际日均缺口（反馈3），不足时退回预设。
// 分层铁律：本文件不得 import package:flutter。
import 'dart:math' as math;

import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/js_compat.dart';
import 'package:shiguang_flutter/domain/models.dart';

/// computeMetabolism 返回值（字段名与 JS 返回对象一致）
class MetabResult {
  const MetabResult({
    required this.bmr,
    required this.tdee,
    required this.suggest,
    required this.realDeficit,
    required this.effDeficit,
    required this.useActual,
    required this.bmi,
    required this.etaText,
    required this.rangeText,
    this.tdeeFromWatch = false,
  });

  final int bmr;
  final int tdee;
  final num suggest;
  final num realDeficit;
  final num effDeficit;
  final bool useActual;
  final double bmi;
  final String etaText;
  final String rangeText;

  /// true = TDEE 用「BMR + 手表全天活动热量」实测口径；false = 活动系数估算。
  final bool tdeeFromWatch;
}

/// 宏量目标（g）：按 50% 碳水 / 25% 蛋白 / 25% 脂肪 供能比估算
class MacroGoals {
  const MacroGoals({required this.carb, required this.protein, required this.fat});

  final int carb;
  final int protein;
  final int fat;

  @override
  bool operator ==(Object other) =>
      other is MacroGoals &&
      other.carb == carb &&
      other.protein == protein &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(carb, protein, fat);

  @override
  String toString() => 'MacroGoals(carb: $carb, protein: $protein, fat: $fat)';
}

/// Mifflin-St Jeor 代谢计算（对齐 js/logic.js computeMetabolism）。
/// [targetWeight] 为 null（JS undefined）或 0（JS falsy）时按当前体重；
/// [actualInfo] 传 { avgDeficit, days }；[now] 为可注入时钟（JS 内部用 Date.now()）。
/// [watchActiveKcal] 为手表当日活动热量：>0 时 TDEE = BMR + 手表活动
/// （实测口径），否则回落 BMR × 活动系数（估算口径）。
MetabResult computeMetabolism(Body b, double? targetWeight,
    [Map? actualInfo, DateTime? now, num? watchActiveKcal]) {
  final W = b.weightKg, H = b.heightCm, A = b.age;
  final bmr = jsRound(10 * W + 6.25 * H - 5 * A + (b.gender == 'male' ? 5 : -161));
  final f = (activity[b.activity] ?? activity['light']!).f;
  final watch =
      (watchActiveKcal != null && watchActiveKcal > 0) ? watchActiveKcal : null;
  final tdee = watch != null ? jsRound(bmr + watch) : jsRound(bmr * f);
  final tdeeFromWatch = watch != null;
  final floor = b.gender == 'male' ? 1500 : 1200;
  final suggest = math.max(tdee - b.deficit, math.max(floor, bmr));
  final realDeficit = tdee - suggest; // 预设缺口（建议值）
  final bmi = jsFixed1(W / math.pow(H / 100, 2));
  // JS: targetWeight || W（null/0 均视为未提供）
  final tw = (targetWeight == null || targetWeight == 0) ? W : targetWeight;
  final need = jsFixed1(W - tw);
  final avgDeficit = actualInfo == null ? null : actualInfo['avgDeficit'] as num?;
  final days0 = actualInfo == null ? null : actualInfo['days'] as num?;
  final useActual = actualInfo != null && (avgDeficit ?? 0) > 0 && (days0 ?? 0) >= 2;
  final effDeficit = useActual ? avgDeficit! : realDeficit;
  // 预计时间用「用户预设档位」而非当日有效缺口：手表口径下 TDEE 随时间波动，
  // 用当日有效缺口会让预计时间在一天内剧烈跳动。真实摄入满 2 天后转实际缺口。
  final presetDeficit = b.deficit;
  final etaDeficit = useActual ? avgDeficit! : presetDeficit;
  final String etaText;
  if (need <= 0) {
    etaText = '已达标或目标不低于当前体重，维持当前摄入即可';
  } else if (etaDeficit <= 0) {
    etaText = useActual
        ? '近期实际摄入无缺口（吃动持平），无法减重，可适当控制饮食或增加运动'
        : '当前摄入无缺口，无法减重，请提高缺口档位';
  } else {
    final days = jsCeil(need * kcalPerKg / etaDeficit);
    final weeks = jsCeil(days / 7);
    final d = (now ?? DateTime.now()).add(Duration(days: days));
    final months = jsRound(days / 30.44);
    final span = months >= 12
        ? '约 ${months ~/ 12} 年 ${months % 12} 个月'
        : '约 $months 个月';
    var text = '预计 $weeks 周（$span · ${d.year}年${d.month}月${d.day}日）'
        '减到 ${jsNumText(targetWeight ?? W)}kg';
    text += useActual
        ? ' · 按近 ${jsNumText(days0!)} 天实际日均缺口 ${jsNumText(effDeficit)} kcal 估算'
        : ' · 按目标缺口 ${jsNumText(etaDeficit)} kcal 估算（记录满 2 天后转为实际缺口）';
    if (etaDeficit * 7 / kcalPerKg > 1) text += ' · 减重偏快，建议降为温和缺口';
    etaText = text;
  }
  final lo = (18.5 * math.pow(H / 100, 2)).toStringAsFixed(1);
  final hi = (23.9 * math.pow(H / 100, 2)).toStringAsFixed(1);
  return MetabResult(
    bmr: bmr,
    tdee: tdee,
    suggest: suggest,
    realDeficit: realDeficit,
    effDeficit: effDeficit,
    useActual: useActual,
    bmi: bmi,
    etaText: etaText,
    rangeText: '合理体重区间 $lo–$hi kg（BMI 18.5–23.9）',
    tdeeFromWatch: tdeeFromWatch,
  );
}

/// 宏量目标（g）：50/25/25 供能比（对齐 js/logic.js macroGoals）
MacroGoals macroGoals(num targetKcal) => MacroGoals(
      carb: jsRound(targetKcal * .5 / 4),
      protein: jsRound(targetKcal * .25 / 4),
      fat: jsRound(targetKcal * .25 / 9),
    );

// ShiguangFlutter/lib/domain/report.dart
// 报告域纯函数层：云函数周报/月报返回 → ReportData，日均、期间建议、今日柱索引。
// 逐字移植 H5 js/app.js：
//   日均         renderWeekReport:802-803（recorded=kcal.filter(v>0)；avg=Math.round(sum/(len||1))）
//   期间建议     buildPeriodAdvice:833-843（5 规则按序 push，slice(0,3).join('；')+'。'）
//   今日索引     renderWeekReport:792-793（getDay 0=日,1=一…6=六 → 周一=0…周日=6）
// 裁定 R2（bug-for-bug 兼容）：云端 rates 已封顶 100（api-diet/index.js:492
// Math.min(100,…)），carb>110 / fat>110 两规则在真实数据下永不触发（死分支），
// 此处逐字保留判断与文案，不得"修正"为 ≥100 或删除——双栈行为一致优先。
// 分层铁律：本文件不得 import package:flutter。
import 'js_compat.dart';

/// 周/月统一报告模型（对应 H5 renderWeekReport 入参 r）。
/// 字段来源：周报 {days,kcal,target,rates}；月报 {weeks,kcal,target,days,total,rates,isWeek}，
/// avgText 由调用方注入（H5 js/app.js:273 `{...r, avgText}`，parse 不生成，保持纯映射）。
class ReportData {
  const ReportData({
    required this.labels,
    required this.kcal,
    required this.target,
    required this.carbRate,
    required this.proteinRate,
    required this.fatRate,
    required this.isWeek,
    required this.recordedDays,
    required this.total,
    this.avgText,
  });

  /// 周报: days["一"…"日"]；月报: weeks["W1"…]
  final List<String> labels;

  /// 每日/每周热量（月报为各周有记录日的日均，云端 api-diet:533 已算好）
  final List<int> kcal;

  /// 每日热量目标（p.dailyKcal）
  final int target;

  /// 三项达标率（云函数已 Math.min(100,…) 封顶，直接读，不再经 macroGoals）
  final int carbRate, proteinRate, fatRate;

  /// 月报 false；周报 true（H5 用 r.isWeek === false 区分，缺字段即周报）
  final bool isWeek;

  /// 月报: days（有记录天数）；周报: kcal 中 >0 计数
  final int recordedDays;

  /// 月报: total（月总摄入）；周报: kcal 求和
  final int total;

  /// 月报注入"月均 X kcal · 记 N 天"；周报 null（UI 显示"日均 {avgRecorded} kcal"）
  final String? avgText;
}

/// 云端 json 数字是 num（可能为 double），整数语义字段统一 .toInt() 取整
/// （沿用 models.dart Body.fromMap `(m['age'] as num?)?.toInt()` 惯例）。
int _asInt(Object? v) => (v as num).toInt();

List<int> _asIntList(Object? v) => (v as List).map(_asInt).toList();

List<String> _asStringList(Object? v) => (v as List).cast<String>();

Map<Object?, Object?> _asMap(Object? v) => v as Map<Object?, Object?>;

/// 周报解析：云函数 /report/week 返回 {days,kcal,target,rates}（无 isWeek 字段）。
/// recordedDays/total 对应 H5 渲染期现算：>0 计数与 fold 求和。
ReportData parseWeekReport(Map<String, dynamic> m) {
  final kcal = _asIntList(m['kcal']);
  final rates = _asMap(m['rates']);
  return ReportData(
    labels: _asStringList(m['days']),
    kcal: kcal,
    target: _asInt(m['target']),
    carbRate: _asInt(rates['carb']),
    proteinRate: _asInt(rates['protein']),
    fatRate: _asInt(rates['fat']),
    isWeek: true,
    recordedDays: kcal.where((v) => v > 0).length,
    total: kcal.fold(0, (a, b) => a + b),
  );
}

/// 月报解析：云函数 /report/month 返回 {weeks,kcal,target,days,total,rates,isWeek:false}。
/// avgText 不在此生成——月均文案由控制器拼接后放入 m['avgText'] 透传（parse 纯映射）。
ReportData parseMonthReport(Map<String, dynamic> m) {
  final rates = _asMap(m['rates']);
  return ReportData(
    labels: _asStringList(m['weeks']),
    kcal: _asIntList(m['kcal']),
    target: _asInt(m['target']),
    carbRate: _asInt(rates['carb']),
    proteinRate: _asInt(rates['protein']),
    fatRate: _asInt(rates['fat']),
    isWeek: false,
    recordedDays: _asInt(m['days']),
    total: _asInt(m['total']),
    avgText: m['avgText'] as String?,
  );
}

/// 日均（只算有记录的天）：js/app.js:802-803
/// recorded = kcal.filter(v => v > 0); avg = Math.round(sum / (recorded.length || 1))
/// 空数组 → 分母按 1 → 0；Math.round 用 jsRound 保 V8 语义（100.5 → 101）。
int avgRecorded(List<int> kcal) {
  final recorded = kcal.where((v) => v > 0).toList();
  final sum = recorded.fold(0, (a, b) => a + b);
  return jsRound(sum / (recorded.isNotEmpty ? recorded.length : 1));
}

/// 多维规则建议引擎（周/月报）：逐字移植 js/app.js:833-843 buildPeriodAdvice。
/// 规则按源码顺序 push，top3 截断依赖该顺序，禁止调换；文案含数字插值逐字一致。
String periodAdvice(ReportData r, int avgKcal) {
  final tips = <String>[];
  if (r.proteinRate < 80) {
    tips.add('蛋白质达标率 ${r.proteinRate}%，偏低，每餐加一份鱼、虾、蛋或豆制品');
  }
  // R2 死分支（云端封顶 100）：保留 >110 判断原文，bug-for-bug 兼容
  if (r.carbRate > 110) {
    tips.add('碳水达目标 ${r.carbRate}%，偏高，主食可换粗粮或减两成');
  } else if (r.carbRate < 60) {
    tips.add('碳水达标率 ${r.carbRate}%，偏低，主食不足易乏力，保留适量谷物');
  }
  // R2 死分支（同上）
  if (r.fatRate > 110) {
    tips.add('脂肪达目标 ${r.fatRate}%，偏高，少油炸、多蒸煮拌');
  }
  if (avgKcal > r.target) {
    tips.add('日均 $avgKcal kcal 超目标 ${r.target} kcal，想控重每日减 ${avgKcal - r.target} kcal 左右');
  } else if (avgKcal > 0 && avgKcal < r.target * 0.7) {
    tips.add('日均 $avgKcal kcal 明显低于目标，长期吃太少会掉代谢，适当吃够');
  }
  if (tips.isEmpty) {
    tips.add('三餐节奏稳定，营养素都在合理区间，继续保持，把运动打卡也安排上');
  }
  return '${tips.take(3).join('；')}。';
}

/// 动态定位"今天"柱：H5 getDay()(0=日,1=一…6=六) → 数组索引 周一=0…周日=6
/// （js/app.js:792-793 `todayIdx === 0 ? 6 : todayIdx - 1`）。
/// Dart DateTime.weekday 本身即 周一=1…周日=7，等价换算为 weekday - 1。
/// 月视图不高亮由调用方处理（H5 isWeek===false 时返回 -1）。
int weekTodayIndex(DateTime now) => now.weekday - 1;

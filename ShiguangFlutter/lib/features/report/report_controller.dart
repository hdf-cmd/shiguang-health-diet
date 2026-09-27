// ShiguangFlutter/lib/features/report/report_controller.dart
// 报告页数据层 riverpod provider（M3 Task 4）。
// 惯例照抄 home_controller.dart（M2 T8）：测试只 override healthApiProvider
// 即可全链路换桩；本文件管周/月报取数 + 视图区间 + 体重趋势取数（T6）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
// riverpod 3.x：StateProvider 收敛在 legacy 导出（未废弃，@publicInLegacy）
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../../domain/report.dart';
import '../home/home_controller.dart'
    show healthApiProvider, SwrFamilyNotifier;
import 'weight_trend.dart';

/// 报告区间（H5 segmented data-range：week/month，index.html:153-154）
enum ReportRange { week, month }

/// 当前区间。默认周（H5 #screen-report 中 week 按钮带 active）。
/// 本任务 UI 只渲染周视图，month 分支 Task 5 接入。
final reportRangeProvider =
    StateProvider<ReportRange>((_) => ReportRange.week);

/// 本周报告（HealthAPI.getWeekReport → 契约 weekReport
/// {days,kcal,target,rates}，js/app.js:271 renderWeekReport 的数据源侧）。
final weekReportProvider =
    FutureProvider.autoDispose<ReportData>((ref) async {
  final m = await ref.watch(healthApiProvider).getWeekReport();
  return parseWeekReport(m);
});

/// 月报（契约 monthReport {weeks,kcal,target,days,total,rates,isWeek:false}）。
/// avgText 透传口径同 H5 js/app.js:273 `{...r, avgText}`——云端无此键，
/// 拼接由 Task 5 的月视图控制器负责；本任务仅按简报 Produces 建好管道。
final monthReportProvider =
    FutureProvider.autoDispose<ReportData>((ref) async {
  final m = await ref.watch(healthApiProvider).getMonthReport();
  return parseMonthReport(m);
});

/// 体重趋势（契约 weightTrend {points,labels}，js/app.js:262/845 renderWeightTrend
/// 的数据源）。autoDispose 等价 H5 每次进报告页重拉；**不随区间分派数据源**——
/// 点"月"走 loadMonthReport 不碰趋势（app.js:269-274）；点"周"走
/// loadReportPage（app.js:260-266,280），趋势与周报**并发重取**——该重取由
/// report_screen 分段回调里 `ref.invalidate(weightTrendProvider)` 触发（T8 缓办 B）。
/// M9-T3：转类形态 AsyncNotifier 并接 [SwrFamilyNotifier] 播种（键 `weightTrend`，
/// 非 family——arg 恒为键名本身）。对外引用名与 `AsyncValue<WeightTrend>` 消费面
/// 不变（report_screen/weight_log_card 零改动）；进页重开首帧先显缓存旧趋势，
/// 后台刷新，失败保旧。
final weightTrendProvider = AsyncNotifierProvider.autoDispose
    <WeightTrendNotifier, WeightTrend>(WeightTrendNotifier.new);

/// M9-T3 播种载体：复用 home 的 [SwrFamilyNotifier] 基类（build 播种链与
/// identical 守卫同款），非 family 语境下 arg 恒为缓存键 'weightTrend'。
class WeightTrendNotifier extends SwrFamilyNotifier<WeightTrend, String> {
  WeightTrendNotifier() : super('weightTrend');

  @override
  String cacheKey(String arg) => arg;

  @override
  Future<WeightTrend> fetch(String _) async {
    final m = await ref.watch(healthApiProvider).getWeightTrend();
    return WeightTrend.fromMap(m);
  }
}

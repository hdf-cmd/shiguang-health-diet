// ShiguangFlutter/lib/features/report/report_controller.dart
// 报告页数据层 riverpod provider（M3 Task 4）。
// 惯例照抄 home_controller.dart（M2 T8）：测试只 override healthApiProvider
// 即可全链路换桩；本文件只管周/月报取数 + 视图区间，体重趋势留 T6。
import 'package:flutter_riverpod/flutter_riverpod.dart';
// riverpod 3.x：StateProvider 收敛在 legacy 导出（未废弃，@publicInLegacy）
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../../domain/report.dart';
import '../home/home_controller.dart' show healthApiProvider;

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

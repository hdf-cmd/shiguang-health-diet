// ShiguangFlutter/lib/features/report/report_screen.dart
// 报告页骨架（M3 Task 4，仅周视图）。H5 对照 index.html:149-161 #screen-report：
// 页头"健康报告" + segmented（本周/月，月按按钮 Task 5 接）+ 热量卡
// （标题"每日热量 · 对比目标"、#report-avg 日均文案、#week-chart 柱状图）。
// 统计卡/建议卡/体重趋势不在本任务（T5/T6）。
// 选中气泡态是本组件的局部状态（H5 事件委托 val-on 语义）：单一
// ValueNotifier<int?>，同柱再点收起、别柱互斥切换（app.js:821-829）；
// 数据重渲染时复位（等价 H5 innerHTML 重建后 val-on 丢失）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/report.dart';
import 'report_controller.dart';
import 'week_chart.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  /// 当前展示气泡的柱索引（null=全收起）
  final _selectedBar = ValueNotifier<int?>(null);

  /// 用于检测"数据换了 → 收起气泡"（等价 H5 重渲染清类）
  ReportData? _shownData;

  @override
  void dispose() {
    _selectedBar.dispose();
    super.dispose();
  }

  void _onBarTap(int i) {
    // 互斥 + 再点同柱收起（app.js:826-828 wasOn 逻辑）
    _selectedBar.value = _selectedBar.value == i ? null : i;
  }

  /// 错误文案：ApiException 露后端 message（沿用首页 M2 口径）
  static String _errorMessage(Object? err) =>
      err is ApiException ? err.message : '加载失败，请检查网络后重试';

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(reportRangeProvider);
    final report = ref.watch(weekReportProvider);
    final data = report.value;

    if (data != null && !identical(data, _shownData)) {
      _shownData = data;
      _selectedBar.value = null;
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Tokens.sp4),
        children: [
          const Text('健康报告',
              style: TextStyle(
                  fontSize: Tokens.textXl,
                  fontWeight: FontWeight.w800,
                  color: Tokens.ink)),
          const SizedBox(height: Tokens.sp3), // segmented margin-top --sp-3
          _segmented(range),
          if (report.hasError) ...[
            const SizedBox(height: Tokens.sp4),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_errorMessage(report.error),
                      style: const TextStyle(
                          color: Tokens.danger, fontSize: Tokens.textMd)),
                  const SizedBox(height: Tokens.sp2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          ref.invalidate(weekReportProvider), // 重试=重新取数
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (data != null) ...[
            const SizedBox(height: Tokens.sp4),
            _kcalCard(data),
          ] else ...[
            // 加载态渲染静态卡框骨架，对齐 index.html:158-161：.card 框与
            // "每日热量 · 对比目标"标题是静态 HTML，数据回来前本来就可见，
            // 只有 #report-avg / #week-chart 两处 innerHTML 为空。
            // 与 M2 首页同原理（home_screen.dart:71-74 loading 期渲染
            // _ringCard(null) 零值卡）。骨架是纯静态 widget，不排持续帧：
            // Riverpod 3 默认失败退避重试（200ms 起）的计时问题在测试侧用
            // Duration.zero 定步 pump 消除，不靠牺牲加载期可见性来规避。
            const SizedBox(height: Tokens.sp4),
            _kcalSkeletonCard(),
          ],
        ],
      ),
    );
  }

  /// 周/月分段控件（index.html:152-155）。本任务只接 week：
  /// month 按钮渲染可点但无动作（Task 5 接切换逻辑）。
  Widget _segmented(ReportRange range) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Tokens.surfaceSoft,
          borderRadius: BorderRadius.circular(999), // --radius-full
          border: Border.all(color: Tokens.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segmentButton('本周',
                active: range == ReportRange.week,
                onTap: () =>
                    ref.read(reportRangeProvider.notifier).state =
                        ReportRange.week),
            _segmentButton('月',
                active: range == ReportRange.month,
                onTap: () {} // 占位：Task 5 接月视图
                ),
          ],
        ),
      ),
    );
  }

  Widget _segmentButton(String label,
      {required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
        decoration: BoxDecoration(
          color: active ? Tokens.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active ? const [Tokens.shadowSegmented] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: Tokens.textSm,
            color: active ? Tokens.ink : Tokens.ink2,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// 热量卡：标题行 + 日均文案（#report-avg）+ 柱状图（#week-chart）
  Widget _kcalCard(ReportData data) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('每日热量 · 对比目标',
                    style: TextStyle(
                        fontSize: Tokens.textMd,
                        fontWeight: FontWeight.w600,
                        color: Tokens.ink)),
              ),
              Text(
                // app.js:804：avgText || `日均 ${avg} kcal`（周报无 avgText 字段）
                data.avgText ?? '日均 ${avgRecorded(data.kcal)} kcal',
                style: const TextStyle(
                    fontSize: Tokens.textXs,
                    fontWeight: FontWeight.w400,
                    color: Tokens.ink3,
                    letterSpacing: 0.7), // --ls-wide .06em × 11px ≈ 0.7
              ),
            ],
          ),
          const SizedBox(height: Tokens.sp5), // .week-chart margin-top --sp-5
          WeekBarChart(
            data: data,
            todayIndex: weekTodayIndex(DateTime.now()),
            selectedIndex: _selectedBar,
            onBarTap: _onBarTap,
          ),
        ],
      ),
    );
  }

  /// 加载态骨架卡：静态标题行 + 空图表容器（高 140 = .week-chart 固定高，
  /// screens.css:407）。日均文案位（#report-avg）留空——H5 该 span 数据回来
  /// 前本为空，骨架不放任何持续动画，避免测试/低端机无谓排帧。
  Widget _kcalSkeletonCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('每日热量 · 对比目标',
              style: TextStyle(
                  fontSize: Tokens.textMd,
                  fontWeight: FontWeight.w600,
                  color: Tokens.ink)),
          SizedBox(height: Tokens.sp5), // .week-chart margin-top --sp-5
          SizedBox(
            height: 140,
            width: double.infinity,
            key: ValueKey('week-chart-skeleton'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.sp5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        boxShadow: Tokens.shadowCard,
      ),
      child: child,
    );
  }
}

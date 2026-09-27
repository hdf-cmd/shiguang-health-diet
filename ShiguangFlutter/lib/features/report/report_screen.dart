// ShiguangFlutter/lib/features/report/report_screen.dart
// 报告页（M3 Task 4-5）。H5 对照 index.html:149-168 #screen-report：
// 页头"健康报告" + segmented（本周/月，app.js:276-281 点击切区间）+ 热量卡
// （标题"每日热量 · 对比目标"、#report-avg 日均/月均文案、#week-chart 柱状图）
// + 达标统计卡（#report-stats，app.js:806-815）+ 期间建议卡
// （.advice-card，app.js:817-818）+ 体重趋势卡（.weight-trend，app.js:845-905，T6）。
// 月视图复用 WeekBarChart：labels=r.weeks、todayIndex=-1（app.js:793
// isWeek===false 不高亮今天）；周数由 labels.length 动态决定（31 天月 5 周）。
// 选中气泡态是本组件的局部状态（H5 事件委托 val-on 语义）：单一
// ValueNotifier<int?>，同柱再点收起、别柱互斥切换（app.js:821-829）；
// 数据重渲染时复位（等价 H5 innerHTML 重建后 val-on 丢失）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/report.dart';
import '../common/stagger.dart' show Stagger;
import '../profile/weight_log_card.dart' show WeightLogCard;
import 'report_controller.dart';
import 'weight_trend.dart';
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

  /// 月均文案（app.js:273 逐字）：月报 r.kcal 已是各周**日均**数组
  /// （云函数 api-diet:533 算好），avgRecorded 对它 = 周日均的平均，
  /// 与 H5 loadMonthReport 同口径——不是对天求和。天数用 r.days
  /// （parseMonthReport 映射进 recordedDays）。
  static String monthAvgText(ReportData r) =>
      '月均 ${avgRecorded(r.kcal)} kcal · 记 ${r.recordedDays} 天';

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(reportRangeProvider);
    // app.js:276-281：segmented 点击切数据源（week→getWeekReport，
    // month→getMonthReport），两 provider 均 autoDispose（等价 H5 每次点击重拉）
    final report = range == ReportRange.week
        ? ref.watch(weekReportProvider)
        : ref.watch(monthReportProvider);
    final data = report.value;

    if (data != null && !identical(data, _shownData)) {
      _shownData = data;
      _selectedBar.value = null;
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Tokens.sp4),
        children: [
          // M9-T6（B2 接线）：卡序错峰入场——热量卡/统计行/建议卡（数据支、
          // 骨架支、error 卡各占同位 index 0/1/2）+ 体重趋势卡=3 +
          // WeightLogCard=4；页标题与 segmented 不播（静态头部观感）。
          const Text('健康报告',
              style: TextStyle(
                  fontSize: Tokens.textXl,
                  fontWeight: FontWeight.w800,
                  color: Tokens.ink)),
          const SizedBox(height: Tokens.sp3), // segmented margin-top --sp-3
          _segmented(range),
          if (report.hasError) ...[
            const SizedBox(height: Tokens.sp4),
            Stagger(
              index: 0,
              child: _card(
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
                        // 重试 = 重新取当前区间的报告
                        onPressed: () => ref.invalidate(range == ReportRange.week
                            ? weekReportProvider
                            : monthReportProvider),
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (data != null) ...[
            const SizedBox(height: Tokens.sp4),
            Stagger(index: 0, child: _kcalCard(data)),
            const SizedBox(height: Tokens.sp4), // .report-stats margin-top --sp-4
            Stagger(index: 1, child: _statsRow(data)),
            const SizedBox(height: Tokens.sp4), // .advice-card margin-top --sp-4
            Stagger(index: 2, child: _adviceCard(data)),
          ] else ...[
            // 加载态渲染静态卡框骨架，对齐 index.html:158-168：.card 框、
            // "每日热量 · 对比目标"标题、.report-stats 三卡框与 .advice-card
            // 标题是静态 HTML，数据回来前本来就可见，只有 #report-avg /
            // #week-chart / #report-stats 内容 / #report-advice 四处 innerHTML 为空。
            // 与 M2 首页同原理（home_screen.dart:71-74 loading 期渲染
            // _ringCard(null) 零值卡）。骨架是纯静态 widget，不排持续帧：
            // Riverpod 3 默认失败退避重试（200ms 起）的计时问题在测试侧用
            // Duration.zero 定步 pump 消除，不靠牺牲加载期可见性来规避。
            const SizedBox(height: Tokens.sp4),
            Stagger(index: 0, child: _kcalSkeletonCard()),
            const SizedBox(height: Tokens.sp4),
            Stagger(index: 1, child: _statsSkeleton()),
            const SizedBox(height: Tokens.sp4),
            Stagger(index: 2, child: _adviceSkeletonCard(range)),
          ],
          // 体重趋势卡：index.html:170 .card.weight-trend 是报告页静态卡框，
          // 数据来自独立接口（app.js:262 与周报并发取一次），因此不参与上面
          // 报告三态分派，自己管加载/错误/空数据/有数据四态，周报失败也在。
          const SizedBox(height: Tokens.sp4), // .weight-trend margin-top --sp-4
          Stagger(index: 3, child: _weightCard()),
          // M8-①（老大 09-27 真机反馈）：体重记录卡自「我的」页搬来，贴
          // 趋势图下方——记完即见图变化（保存链 invalidate weightTrendProvider）。
          const SizedBox(height: Tokens.sp4),
          const Stagger(index: 4, child: WeightLogCard()),
        ],
      ),
    );
  }

  /// 周/月分段控件（index.html:152-155）。点击切 reportRangeProvider
  /// （app.js:276-281），数据源分派见 build。
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
                onTap: () {
                  // T8 缓办 B：app.js:276-281 点"周"走 loadReportPage
                  // （app.js:260-266），周报与 weight-trend **并发重取**；
                  // 点"月"走 loadMonthReport 不碰趋势。
                  // 终审 Important-2（口径自洽）：此前只 invalidate 趋势、周报
                  // 靠"切区间 autoDispose 重挂"顺带重取，于是**同区间重复点
                  // "本周"**（已是 week，range 不变）不发请求，与 H5 每次点击
                  // 都重发（app.js:280 无"已选中不重发"判断）相反 → 周报显式
                  // invalidate，两条数据源同一口径。
                  ref.invalidate(weekReportProvider);
                  ref.invalidate(weightTrendProvider);
                  ref.read(reportRangeProvider.notifier).state =
                      ReportRange.week;
                }),
            _segmentButton('月',
                active: range == ReportRange.month,
                onTap: () =>
                    ref.read(reportRangeProvider.notifier).state =
                        ReportRange.month),
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
                // app.js:804：avgText || `日均 ${avg} kcal`。周报无 avgText
                // 走日均分支；月报云端也无此键（app.js:273 在 loadMonthReport
                // 现场拼），等价口径 = monthAvgText。
                data.avgText ??
                    (data.isWeek
                        ? '日均 ${avgRecorded(data.kcal)} kcal'
                        : monthAvgText(data)),
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
            // app.js:793：isWeek===false（月报）→ -1，不高亮今天；
            // 柱数由 labels.length 动态（月报 4 或 5 周）
            todayIndex:
                data.isWeek ? weekTodayIndex(DateTime.now()) : -1,
            selectedIndex: _selectedBar,
            onBarTap: _onBarTap,
          ),
        ],
      ),
    );
  }

  /// 达标统计卡行（#report-stats，app.js:806-815）：3 列等宽 grid、
  /// gap --sp-3（screens.css:436）。rate 云函数已 Math.min(100,…) 封顶
  /// （api-diet/index.js:492），直接当百分比用，不再客户端封顶。
  Widget _statsRow(ReportData data) {
    return Row(
      children: [
        Expanded(child: _statCard('carb', '碳水达标', data.carbRate, Tokens.nutCarb)),
        const SizedBox(width: Tokens.sp3),
        Expanded(
            child: _statCard('protein', '蛋白达标', data.proteinRate,
                Tokens.nutProtein)),
        const SizedBox(width: Tokens.sp3),
        Expanded(child: _statCard('fat', '脂肪控制', data.fatRate, Tokens.nutFat)),
      ],
    );
  }

  /// 单张 .stat-card（components.css:190-193）：surface2 底 + radiusMd +
  /// padding sp4 + hairline 边框；label 11px ink3 宽字距；num 26px ink +
  /// 小号 " %"（.num small 11px ink3）；进度条 track 高 6 surfaceSoft、
  /// margin-top 8，fill 宽 rate%、色 var(--nut-{key})。
  Widget _statCard(String key, String label, int rate, Color fillColor) {
    return Container(
      key: ValueKey('stat-card-$key'),
      padding: const EdgeInsets.all(Tokens.sp4),
      decoration: BoxDecoration(
        color: Tokens.surface2,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: Tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: Tokens.textXs,
                  color: Tokens.ink3,
                  letterSpacing: 0.7)), // --ls-wide × 11px
          const SizedBox(height: 4), // .num margin-top 4px
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$rate',
                  style: const TextStyle(
                      fontSize: 26,
                      height: 1.15, // 与 small 底对齐用，行高收窄
                      fontWeight: FontWeight.w600,
                      color: Tokens.ink,
                      fontFeatures: [
                        FontFeature.tabularFigures() // tabular-nums
                      ])),
              const Text(' %',
                  style: TextStyle(
                      fontSize: Tokens.textXs, color: Tokens.ink3)),
            ],
          ),
          const SizedBox(height: Tokens.sp2), // track margin-top 8px
          Container(
            key: ValueKey('stat-track-$key'),
            height: 6,
            decoration: BoxDecoration(
              color: Tokens.surfaceSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  key: ValueKey('stat-fill-$key'),
                  width: constraints.maxWidth * rate / 100,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 期间建议卡（.advice-card，app.js:817-818）：primary-soft 底、无阴影
  /// （screens.css:437 box-shadow:none），标题按 isWeek 切"本周/本月建议"，
  /// 正文 periodAdvice(data, avgRecorded(data.kcal))——月报口径同 H5：
  /// avg 对周日均数组现算，与 #report-avg 月均数一致。
  Widget _adviceCard(ReportData data) {
    return _adviceCardFrame(
      title: data.isWeek ? '本周建议' : '本月建议',
      // .advice-card p 静态为空时才不占位：正文缺失即骨架
      body: periodAdvice(data, avgRecorded(data.kcal)),
    );
  }

  /// 建议卡外框（数据态与骨架共用）：index.html:165-168
  /// .card.advice-card > .card-title(#advice-title) + p(#report-advice)
  Widget _adviceCardFrame({required String title, String? body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.sp5),
      decoration: BoxDecoration(
        color: Tokens.primarySoft, // --primary-soft 覆盖 .card surface 底
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: Tokens.hairline),
        // .advice-card box-shadow:none（screens.css:437）→ 不给 shadowCard
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: Tokens.textMd,
                  fontWeight: FontWeight.w600,
                  color: Tokens.primaryDeep, // 内联 style color:--primary-deep
                  letterSpacing: 0.15)), // .card-title ls .01em × 15px
          if (body != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.sp2), // p margin-top
              child: Text(body,
                  style: const TextStyle(
                      fontSize: Tokens.textSm,
                      color: Tokens.primaryDeep,
                      height: 1.8)), // line-height 1.8
            ),
        ],
      ),
    );
  }

  /// 加载态骨架：三张 stat-card 空框（#report-stats 静态容器内的卡框位；
  /// label/rate/进度条是 innerHTML，数据回来前为空）。keys 与数据态一致，
  /// 测试可断言"框在、数据位不在"。
  Widget _statsSkeleton() {
    Widget box(String key) => Container(
          key: ValueKey('stat-card-$key'),
          height: _statCardSkeletonHeight,
          decoration: BoxDecoration(
            color: Tokens.surface2,
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
            border: Border.all(color: Tokens.hairline),
          ),
        );
    return Row(
      children: [
        Expanded(child: box('carb')),
        const SizedBox(width: Tokens.sp3),
        Expanded(child: box('protein')),
        const SizedBox(width: Tokens.sp3),
        Expanded(child: box('fat')),
      ],
    );
  }

  /// 骨架卡高 ≈ 数据态 stat-card：padding 16*2 + label 13 + 4 +
  /// num 26*1.15≈30 + 8 + track 6 = 93（仅占位，无内容）。
  /// T8 缓办 A：原写 89 与各项相加 93 矛盾，骨架↔数据切换会跳 ~4px。
  static const double _statCardSkeletonHeight = 93;

  /// 加载态建议卡：#advice-title 是静态 HTML（index.html:166 初值
  /// "本周建议"；H5 点"月"后到月报回来前标题其实不动——Flutter 侧区间
  /// 状态已知，按当前 range 给更自洽的占位标题），#report-advice 为空。
  Widget _adviceSkeletonCard(ReportRange range) {
    return _adviceCardFrame(
        title: range == ReportRange.month ? '本月建议' : '本周建议');
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
          // index.html:160 #week-chart 是静态 div：H5 加载期其
          // border-bottom:1px --hairline（screens.css:407）本就可见——
          // 底线随骨架一起画（T8 缓办 D① 延伸）。终审 Important-1：
          // border-bottom 在 .week-chart 容器最底沿，而日期标签 .lbl 在
          // .col 内部（app.js:796-800）→ 轴线在标签之下；上面 140 占位就是
          // 整个 .week-chart（含标签列），所以这条线本就在标签占位之后，
          // 与数据态 week_chart.dart 的落点一致。补 key 供加载态用例断言。
          SizedBox(
            width: double.infinity,
            height: 1,
            child: ColoredBox(
              key: ValueKey('week-chart-axis-skeleton'),
              color: Tokens.hairline,
            ),
          ),
        ],
      ),
    );
  }

  /// 体重趋势卡（index.html:170-174 `.card.weight-trend`，几何/文案见
  /// weight_trend.dart 顶部对照表）。标题行右侧 `.card-title .more` 即
  /// #weight-delta（app.js:903-904）：文案降/平 primary、升 warn，空数据为空串。
  /// **卡内不渲染"＋ 记今日体重"按钮**（index.html:173 #btn-log-weight）：
  /// 本里程碑不做写入口（简报 Step 5），HealthApi.logWeight 已就绪，
  /// 入口 UI 归后续「我的」页里程碑。
  Widget _weightCard() {
    final trend = ref.watch(weightTrendProvider);
    final data = trend.value;
    final points = data?.points ?? const <double>[];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('体重趋势',
                    style: TextStyle(
                        fontSize: Tokens.textMd,
                        fontWeight: FontWeight.w600,
                        color: Tokens.ink)),
              ),
              Text(
                weightDeltaText(points),
                style: TextStyle(
                    fontSize: Tokens.textXs,
                    fontWeight: FontWeight.w400, // .card-title .more
                    color: weightDeltaColor(points),
                    letterSpacing: 0.7), // --ls-wide .06em × 11px ≈ 0.7
              ),
            ],
          ),
          const SizedBox(height: Tokens.sp3), // .weight-trend svg margin-top --sp-3
          if (trend.hasError) ...[
            Text(_errorMessage(trend.error),
                style: const TextStyle(
                    color: Tokens.danger, fontSize: Tokens.textMd)),
            const SizedBox(height: Tokens.sp2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                // 重试 = 重新取体重趋势（照报告卡 invalidate 口径）
                onPressed: () => ref.invalidate(weightTrendProvider),
                child: const Text('重试'),
              ),
            ),
          ] else if (data != null)
            WeightTrendChart(points: data.points, labels: data.labels)
          else
            // 加载态：H5 此刻 #weight-svg 是带 viewBox 的空 SVG，按同比例占位
            const AspectRatio(
              key: ValueKey('weight-trend-skeleton'),
              aspectRatio: 320 / 132,
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

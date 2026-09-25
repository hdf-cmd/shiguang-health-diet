// ShiguangFlutter/test/weight_trend_test.dart
// M3 Task 6：体重趋势线。事实源 = H5 js/app.js:845-905 renderWeightTrend（逐字移植）。
// 两层断言：
//   ① computeTrendLayout 纯几何函数 —— 值域外扩/最小跨度/0.5 对齐、单点特判、
//      xOf/yOf 具体坐标（手算锁定）、4 条网格等分与 dash 归属、圆点半径与数值锚点；
//   ② WeightTrendChart / 报告页体重卡 —— 空数据占位文案、CustomPaint 不崩、
//      delta 文案与颜色（降/平 primary、升 warn）。
// 常数对照：viewBox 0 0 320 132（index.html:172）、绘图区 X0=44 X1=306 Y0=16 Y1=104
// （app.js:864）、末点 r=4.2 其余 r=3（app.js:887）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart' show healthApiProvider;
import 'package:shiguang_flutter/features/report/report_screen.dart';
import 'package:shiguang_flutter/features/report/weight_trend.dart';

import 'stubs/stub_health_api.dart';
import 'harness.dart';

Widget chartHarness(List<double> points, List<String> labels) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 320, child: WeightTrendChart(points: points, labels: labels)),
        ),
      ),
    );

Widget reportHarness(StubHealthApi api) => ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      child: const MaterialApp(home: ReportScreen()),
    );

void main() {
  /* ==================== ① 纯几何：常数与值域 ==================== */

  test('绘图区常数逐字对齐 app.js:864 / viewBox 320x132', () {
    expect(TrendGeometry.viewWidth, 320);
    expect(TrendGeometry.viewHeight, 132);
    expect(TrendGeometry.x0, 44);
    expect(TrendGeometry.x1, 306);
    expect(TrendGeometry.y0, 16);
    expect(TrendGeometry.y1, 104);
  });

  test('空数据/null 分支 → 无布局（H5 提前 return 画占位文字，app.js:847-851）', () {
    expect(computeTrendLayout(const <double>[]), isNull);
  });

  test('值域外扩：[70,70.2] 跨度必须 ≥1 且边界是 0.5 的倍数（app.js:859-861）', () {
    final l = computeTrendLayout(const [70, 70.2])!;
    expect(l.hi - l.lo, greaterThanOrEqualTo(1));
    expect((l.hi * 2) % 1, closeTo(0, 1e-9));
    expect((l.lo * 2) % 1, closeTo(0, 1e-9));
    // 手算：hi=lo=(70+70.2)/2±0.5 → 70.6/69.6 → ceil(141.2)/2=71、floor(139.2)/2=69.5
    expect(l.hi, closeTo(71.0, 1e-9));
    expect(l.lo, closeTo(69.5, 1e-9));
  });

  test('跨度本来就 >1 时只做了 0.5 对齐取整，不再外扩（app.js:861）', () {
    // [66.4,67,68]：hi 68 → ceil(136)/2=68；lo 66.4 → floor(132.8)/2=66
    final l = computeTrendLayout(const [66.4, 67, 68])!;
    expect(l.hi, closeTo(68, 1e-9));
    expect(l.lo, closeTo(66, 1e-9));
  });

  test('单点特判：一个点居中 x=(X0+X1)/2，不除零（app.js:854-855,865）', () {
    final l = computeTrendLayout(const [68.5])!;
    expect(l.single, isTrue);
    expect(l.count, 1);
    // 手算：hi=69 lo=68（0.5 对齐后仍是 69/68），y=104-(0.5/1)*88=60
    expect(l.lo, closeTo(68, 1e-9));
    expect(l.hi, closeTo(69, 1e-9));
    expect(l.points.single, const Offset(175, 60));
  });

  test('xOf/yOf：两点 [60,70] 端点坐标精确（首点贴底、末点贴顶）', () {
    expect(trendXOf(0, 2), 44);
    expect(trendXOf(1, 2), 306);
    expect(trendXOf(1, 3), 175); // 44 + 1*262/2
    expect(trendYOf(60, 60, 70), 104); // lo → Y1
    expect(trendYOf(70, 60, 70), 16); // hi → Y0
    expect(trendYOf(65, 60, 70), 60); // 中值 → Y1 与 Y0 中点
    final l = computeTrendLayout(const [60, 70])!;
    expect(l.points, const [Offset(44, 104), Offset(306, 16)]);
  });

  test('xOf 均分随点数动态：12 点不写死（app.js:865）', () {
    final pts = List<double>.generate(12, (i) => 60 + i * 0.1);
    final l = computeTrendLayout(pts)!;
    expect(l.count, 12);
    expect(l.points.first.dx, 44);
    expect(l.points.last.dx, 306);
    expect(l.points[1].dx, closeTo(44 + 262 / 11, 1e-9));
  });

  test('yOf：[66.4,67,68] 逐点手算（lo=66 hi=68，Y1-(v-lo)/(hi-lo)*88）', () {
    final l = computeTrendLayout(const [66.4, 67, 68])!;
    expect(l.points[0].dy, closeTo(104 - 0.4 / 2 * 88, 1e-9)); // 86.4
    expect(l.points[1].dy, closeTo(60, 1e-9));
    expect(l.points[2].dy, closeTo(16, 1e-9));
  });

  /* ==================== ② 网格 / 圆点 / 锚点 ==================== */

  test('Y 网格 4 条等分，首末为 hi/lo，仅末条实线其余 dash（app.js:869-874）', () {
    final l = computeTrendLayout(const [70, 70.2])!; // hi 71 / lo 69.5 / step 0.5
    expect(l.grid, hasLength(4));
    expect(l.grid.map((g) => g.value), [71.0, 70.5, 70.0, 69.5]);
    expect(l.grid.map((g) => g.dashed), [true, true, true, false]);
    expect(l.grid[0].y, closeTo(16, 1e-9));
    expect(l.grid[1].y, closeTo(16 + 88 / 3, 1e-6));
    expect(l.grid[2].y, closeTo(104 - 88 / 3, 1e-6));
    expect(l.grid[3].y, closeTo(104, 1e-9));
  });

  test('圆点：末点 r=4.2 其余 r=3；数值取原始点（app.js:884-887）', () {
    final l = computeTrendLayout(const [66.4, 67, 68])!;
    expect(l.dots.map((d) => d.radius), [3.0, 3.0, 4.2]);
    expect(l.dots.map((d) => d.isLast), [false, false, true]);
    expect(l.dots.map((d) => d.value), [66.4, 67.0, 68.0]);
  });

  test('数值锚点：非单点时首 start(-1)/末 end(+1)/其余 middle(0)，单点 middle(0)', () {
    final l = computeTrendLayout(const [66.4, 67, 68])!;
    expect(l.dots.map((d) => d.anchor),
        [TrendLabelAnchor.start, TrendLabelAnchor.middle, TrendLabelAnchor.end]);
    expect(l.dots.map((d) => d.labelDx), [-1.0, 0.0, 1.0]);
    // 单点：既是首也是末，仍走 middle（app.js:885 `!single` 特判）
    final s = computeTrendLayout(const [68.5])!;
    expect(s.dots.single.anchor, TrendLabelAnchor.middle);
    expect(s.dots.single.labelDx, 0.0);
    expect(s.dots.single.radius, 4.2); // 单点也是末点
    // 两点：首 end? 否——首仍是 start，末是 end
    final t = computeTrendLayout(const [60, 70])!;
    expect(t.dots.map((d) => d.anchor), [TrendLabelAnchor.start, TrendLabelAnchor.end]);
  });

  test('面积闭合顺序：折线 + 末点垂到 Y1 + 首点垂到 Y1（app.js:879）', () {
    final l = computeTrendLayout(const [66.4, 67, 68])!;
    final area = l.areaPoints;
    expect(area.length, l.count + 2);
    expect(area[l.count], const Offset(306, 104)); // 末点 x → Y1
    expect(area[l.count + 1], const Offset(44, 104)); // 首点 x → Y1
  });

  /* ==================== ③ delta 文案与颜色 ==================== */

  group('weightDeltaText / weightDeltaColor（app.js:902-904）', () {
    test('降：无 + 号、色 primary', () {
      expect(weightDeltaText(const [67.2, 67, 66.4]), '当前 66.4 kg · 本周 -0.80 kg');
      expect(weightDeltaColor(const [67.2, 67, 66.4]), Tokens.primary);
    });
    test('升：显式 + 号、色 warn', () {
      expect(weightDeltaText(const [66.4, 67, 67.2]), '当前 67.2 kg · 本周 +0.80 kg');
      expect(weightDeltaColor(const [66.4, 67, 67.2]), Tokens.warn);
    });
    test('平：0.00 无 + 号、色 primary（delta<=0 分支）', () {
      expect(weightDeltaText(const [66.5, 66.5, 66.5]), '当前 66.5 kg · 本周 0.00 kg');
      expect(weightDeltaColor(const [66.5, 66.5, 66.5]), Tokens.primary);
    });
    test('微量上升但 toFixed(2) 归零 → 按字符串语义无 + 号、色 primary', () {
      // JS：delta = (66.001-66).toFixed(2) === "0.00" → "0.00">0 为 false
      expect(weightDeltaText(const [66, 66.001]), '当前 66.001 kg · 本周 0.00 kg');
      expect(weightDeltaColor(const [66, 66.001]), Tokens.primary);
    });
    test('末值整数按 JS 模板字符串输出（67 不带 .0），整数差 -0.20', () {
      expect(weightDeltaText(const [67.2, 67]), '当前 67 kg · 本周 -0.20 kg');
      expect(weightDeltaColor(const [67.2, 67]), Tokens.primary);
    });
    test('单点：delta 0.00', () {
      expect(weightDeltaText(const [66.4]), '当前 66.4 kg · 本周 0.00 kg');
    });
    test('空数据：文案为空串（app.js:849）', () {
      expect(weightDeltaText(const <double>[]), '');
    });
  });

  /* ==================== ④ WeightTrendChart widget ==================== */

  testWidgets('空数据：画"暂无体重数据"占位，无曲线（app.js:848 逐字）', (tester) async {
    await tester.pumpWidget(chartHarness(const [], const []));
    await tester.pump();
    expect(find.text('暂无体重数据'), findsOneWidget);
    expect(
        (tester.widget<Text>(find.text('暂无体重数据')).style!).color, Tokens.ink3);
    // 占位分支不画画布（H5 innerHTML 只有那条 text）
    expect(find.byKey(WeightTrendChart.canvasKey), findsNothing);
  });

  testWidgets('有数据：AspectRatio 320/132 + CustomPaint，无占位文字', (tester) async {
    await tester.pumpWidget(chartHarness(
      const [67.2, 67, 66.8, 66.66, 66.6, 66.5, 66.4],
      const ['9.19', '9.20', '9.21', '9.22', '9.23', '9.24', '9.25'],
    ));
    await tester.pump();
    expect(find.text('暂无体重数据'), findsNothing);
    final ratio =
        tester.widget<AspectRatio>(find.byKey(WeightTrendChart.frameKey)).aspectRatio;
    expect(ratio, closeTo(320 / 132, 1e-9));
    expect(find.byKey(WeightTrendChart.canvasKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('labels 缺项不画该日期 / 单点不崩（app.js:892-893）', (tester) async {
    await tester.pumpWidget(chartHarness(const [68.5], const []));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(WeightTrendChart.canvasKey), findsOneWidget);

    await tester.pumpWidget(chartHarness(const [66.4, 67, 68], const ['9.24', '', '9.26']));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  /* ==================== ⑤ 报告页体重卡接线 ==================== */

  Future<void> pumpReport(WidgetTester tester, StubHealthApi api) async {
    // 拉长视口：体重卡是页尾第 5 张卡，默认 600 高视口会落在缓存区外
    // （视口样板 + addTearDown 复位收敛在 test/harness.dart 的 useBigSurface）
    await useBigSurface(tester);
    await tester.pumpWidget(reportHarness(api));
    await tester.pumpAndSettle(); // 周柱 700ms 入场动画收敛
  }

  testWidgets('体重卡：标题 + delta 行（桩默认 = 契约 fixture 7 点降）', (tester) async {
    await pumpReport(tester, StubHealthApi());
    expect(find.text('体重趋势'), findsOneWidget);
    expect(find.text('当前 66.4 kg · 本周 -0.80 kg'), findsOneWidget);
    expect(
        (tester.widget<Text>(find.text('当前 66.4 kg · 本周 -0.80 kg')).style!).color,
        Tokens.primary);
    // 记体重入口本任务不渲染（logWeight UI 归「我的」页里程碑）
    expect(find.text('＋ 记今日体重'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('体重卡空数据：占位文案 + delta 行空（app.js:847-851）', (tester) async {
    await pumpReport(tester, StubHealthApi(
        weightTrend: StubHealthApi.weightTrendMap(points: const [], labels: const [])));
    expect(find.text('体重趋势'), findsOneWidget);
    expect(find.text('暂无体重数据'), findsOneWidget);
    expect(find.text('当前 66.4 kg · 本周 -0.80 kg'), findsNothing);
  });

  testWidgets('体重卡错误态：后端 message + 重试，重试重新取数', (tester) async {
    final api = StubHealthApi(weightTrendError: ApiException('趋势加载失败'));
    // 定步 pump 不推进时钟 → 不踩 Riverpod 3 失败退避重试（同 T4/T5 错误态用例）。
    // 注意：本用例的容器是 reportHarness 里的 ProviderScope，**不走**
    // buildRootContainer，所以 M4-T1 的 retry: (_, _) => null 对它无效——
    // 定步 pump 仍是必需，别当冗余删掉。
    await useBigSurface(tester);
    await tester.pumpWidget(reportHarness(api));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('趋势加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(api.trendCalls, 1);

    api.weightTrendError = null;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('趋势加载失败'), findsNothing);
    expect(find.text('当前 66.4 kg · 本周 -0.80 kg'), findsOneWidget);
    expect(api.trendCalls, 2);
  });

  testWidgets('报告区间联动：切月不重拉趋势/周报、切回周并发重取、同区间再点"本周"仍重取'
      '（H5 app.js:260-266,269-274,276-281 两向锁；终审 Important-2）',
      (tester) async {
    final api = StubHealthApi();
    await pumpReport(tester, api);
    expect(api.trendCalls, 1);
    expect(api.weekCalls, 1);
    // 点"月" = loadMonthReport（app.js:269-274）：只换柱状图数据源，
    // 既不碰趋势也不重取周报
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(api.trendCalls, 1);
    expect(api.weekCalls, 1);
    expect(api.monthCalls, 1);
    expect(find.text('体重趋势'), findsOneWidget);
    expect(find.text('当前 66.4 kg · 本周 -0.80 kg'), findsOneWidget);
    // 点"本周" = loadReportPage（app.js:260-266,280）：周报与趋势并发重取
    // （T8 缓办 B：Flutter 此前切回不重取趋势，与 H5 不一致）
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(api.trendCalls, 2);
    expect(api.weekCalls, 2);
    expect(find.text('当前 66.4 kg · 本周 -0.80 kg'), findsOneWidget);
    // 同区间重复点"本周"：H5 的 click 监听（app.js:276-281）没有
    // "已选中就不重发"判断 → 每次点击都重新并发取周报+趋势
    // （终审 Important-2：此前周报靠 autoDispose 重挂顺带重取，同区间再点
    // 不发请求，与已 invalidate 的趋势口径相反）
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(api.trendCalls, 3);
    expect(api.weekCalls, 3);
    expect(find.text('当前 66.4 kg · 本周 -0.80 kg'), findsOneWidget);
  });

  testWidgets('周报错误态下体重卡仍在（index.html:170 静态卡框）', (tester) async {
    final api = StubHealthApi(weekError: ApiException('周报加载失败'));
    await useBigSurface(tester);
    await tester.pumpWidget(reportHarness(api));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('周报加载失败'), findsOneWidget);
    expect(find.text('体重趋势'), findsOneWidget);
    expect(find.text('当前 66.4 kg · 本周 -0.80 kg'), findsOneWidget);
  });
}

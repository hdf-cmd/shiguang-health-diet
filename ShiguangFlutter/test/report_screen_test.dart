// ShiguangFlutter/test/report_screen_test.dart
// M3 Task 4：报告页骨架 + 周柱状图（加载态静态卡框 / 入场动画后断言 /
// 点击互斥气泡 / 错误态重试——错误态用定步 pump，见用例内注释）。
// 全部走 StubHealthApi（override healthApiProvider），零网络。
// 样本数据 = contract/fixtures/diet-core.json weekReport.responseSample。
// 几何/交互事实源：js/app.js:788-829、css/screens.css:407-435。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/domain/report.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart' show healthApiProvider;
import 'package:shiguang_flutter/features/report/report_controller.dart';
import 'package:shiguang_flutter/features/report/report_screen.dart';

import 'stubs/stub_health_api.dart';

Widget harness(StubHealthApi api) => ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      child: const MaterialApp(home: ReportScreen()),
    );

void main() {
  const days = ['一', '二', '三', '四', '五', '六', '日'];
  const kcal = [1720, 1688, 0, 1856, 1745, 0, 988];
  const target = 1679;
  final kWeek = StubHealthApi.weekReportMap(
    days: days,
    kcal: kcal,
    target: target,
    carb: 86,
    protein: 72,
    fat: 64,
  );
  // js/app.js:802-803：recorded=[1720,1688,1856,1745,988]，sum 7997 / 5 → 1599
  final avgText = '日均 ${avgRecorded(kcal)} kcal';

  // 柱几何以 140 为基准（screens.css:407）；H5 高度% = max(4, kcal/max*100)，
  // max = 1856*1.1 = 2041.6
  double expectBarPx(int i) =>
      math.max(4.0, kcal[i] / (1856 * 1.1) * 100) / 100 * 140;

  Future<void> pumpReport(WidgetTester tester, StubHealthApi api) async {
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle(); // 等 700ms 柱入场动画收敛后再断言
  }

  testWidgets('骨架：页头/分段/卡片标题/日均文案 + 7 根柱 + 今天柱标签', (tester) async {
    await pumpReport(tester, StubHealthApi(weekReport: kWeek));

    expect(find.text('健康报告'), findsOneWidget); // index.html:151
    expect(find.text('本周'), findsOneWidget); // index.html:153
    expect(find.text('月'), findsOneWidget); // index.html:154
    expect(find.text('每日热量 · 对比目标'), findsOneWidget); // index.html:159
    expect(find.text(avgText), findsOneWidget); // #report-avg（app.js:804）
    expect(find.text('目标 $target'), findsOneWidget); // 目标虚线标签（app.js:795）

    final todayIdx = weekTodayIndex(DateTime.now());
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(ValueKey('week-bar-$i')), findsOneWidget, reason: '柱 $i');
    }
    expect(find.text('今天'), findsOneWidget); // app.js:799 今天柱标签
    for (var i = 0; i < 7; i++) {
      if (i == todayIdx) continue;
      expect(find.text(days[i]), findsOneWidget);
    }
  });

  testWidgets('几何与配色：0 kcal 柱 min 4% 高、over=warnSoft、正常=primarySoft（app.js:797-798 / screens.css:414-433）',
      (tester) async {
    await pumpReport(tester, StubHealthApi(weekReport: kWeek));

    // min 4%：0 kcal 柱高 = 140*.04 = 5.6px（不是 0）
    final zeroBar = tester
        .widget<Container>(find.byKey(const ValueKey('week-bar-fill-2')))
        .decoration! as BoxDecoration;
    expect(tester.getSize(find.byKey(const ValueKey('week-bar-fill-2'))).height,
        closeTo(expectBarPx(2), 0.5));
    expect(zeroBar.color, Tokens.primarySoft);

    // 非今天且非 over 的柱（kcal<=target：2/5/6 中挑一个不是今天的）
    final todayIdx = weekTodayIndex(DateTime.now());
    final normalIdx = [2, 5, 6].firstWhere((i) => i != todayIdx);
    expect(
        (tester
                    .widget<Container>(
                        find.byKey(ValueKey('week-bar-fill-$normalIdx')))
                    .decoration!
                as BoxDecoration)
            .color,
        Tokens.primarySoft);

    // over 柱（kcal>target：0/1/3/4 全部超 1679）→ warnSoft；
    // CSS 里 .col.over .bar 规则在 .col.today .bar 之后，即使今天=该柱也是 warnSoft
    for (final i in [0, 1, 3, 4]) {
      expect(
          (tester
                      .widget<Container>(find.byKey(ValueKey('week-bar-fill-$i')))
                      .decoration!
                  as BoxDecoration)
              .color,
          Tokens.warnSoft,
          reason: 'over 柱 $i');
    }
    // 有值柱高度按 pct 对 140 线性（app.js:798 kcal/max*100）
    expect(tester.getSize(find.byKey(const ValueKey('week-bar-fill-0'))).height,
        closeTo(expectBarPx(0), 0.5));
  });

  testWidgets('今天柱：渐变 primary→primaryDeep + primaryGlow 阴影（screens.css:429-431）',
      (tester) async {
    // 确定化构造：把"今天"那天 kcal 改为 1500（≤target，非 over），
    // over 规则不会覆盖 today 渐变——任何星期几跑都走渐变分支，
    // 不再用 early-return 静默跳过（此前周五跑会零断言假通过）。
    final todayIdx = weekTodayIndex(DateTime.now());
    final kcalToday = List<int>.from(kcal)..[todayIdx] = 1500;
    await pumpReport(tester,
        StubHealthApi(weekReport: StubHealthApi.weekReportMap(
            days: days, kcal: kcalToday, target: target)));

    final deco = tester
        .widget<Container>(find.byKey(ValueKey('week-bar-fill-$todayIdx')))
        .decoration! as BoxDecoration;
    final gradient = deco.gradient!;
    expect(gradient.colors.first, Tokens.primary);
    expect(gradient.colors.last, Tokens.primaryDeep);
    expect(deco.boxShadow!.single.color, Tokens.primaryGlow);
  });

  testWidgets('点击气泡：出→收起→点别柱互斥；0 kcal 柱显"未记录"（app.js:821-829）',
      (tester) async {
    await pumpReport(tester, StubHealthApi(weekReport: kWeek));

    // 初始全部收起（气泡文本不在树里，H5 display:none 等价）
    expect(find.text('1720 kcal'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('week-bar-0')));
    await tester.pump();
    expect(find.text('1720 kcal'), findsOneWidget);

    // 再点同柱 → 收起
    await tester.tap(find.byKey(const ValueKey('week-bar-0')));
    await tester.pump();
    expect(find.text('1720 kcal'), findsNothing);

    // 点柱 3 → 气泡切到 1856；再点柱 2（0 kcal）→ "未记录"，且互斥
    await tester.tap(find.byKey(const ValueKey('week-bar-3')));
    await tester.pump();
    expect(find.text('1856 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('week-bar-2')));
    await tester.pump();
    expect(find.text('未记录'), findsOneWidget);
    expect(find.text('1856 kcal'), findsNothing);

    // 气泡文字颜色：over 柱 warn，其余 primaryDeep（screens.css:423,428）
    await tester.tap(find.byKey(const ValueKey('week-bar-0')));
    await tester.pump();
    expect(
        (tester.widget<Text>(find.text('1720 kcal')).style!).color,
        Tokens.warn);
    await tester.tap(find.byKey(const ValueKey('week-bar-2')));
    await tester.pump();
    expect(
        (tester.widget<Text>(find.text('未记录')).style!).color,
        isNot(Tokens.warn));
  });

  testWidgets('入场动画：柱高自 0 补间，settle 后到位（css transition height .7s --ease-out）',
      (tester) async {
    final api = StubHealthApi(weekReport: kWeek);
    await tester.pumpWidget(harness(api));
    await tester.pump(); // 数据到位 → 柱首帧，TweenAnimationBuilder 从 0 起步
    final h0 = tester.getSize(find.byKey(const ValueKey('week-bar-fill-0'))).height;
    expect(h0, lessThan(expectBarPx(0))); // 入场起点不是瞬现

    await tester.pump(const Duration(milliseconds: 300));
    final hMid =
        tester.getSize(find.byKey(const ValueKey('week-bar-fill-0'))).height;
    expect(hMid, greaterThan(h0)); // 补间推进中
    expect(hMid, lessThanOrEqualTo(expectBarPx(0))); // 不越过终值

    await tester.pumpAndSettle(); // 700ms 动画收敛
    expect(
        tester.getSize(find.byKey(const ValueKey('week-bar-fill-0'))).height,
        closeTo(expectBarPx(0), 0.5));
  });

  testWidgets('加载态：渲染静态卡框骨架（index.html:158-161 卡框+标题为静态 HTML），不出数据文案',
      (tester) async {
    // 用永不完成的 Future 覆盖 provider，钉死 loading 态：
    // 骨架无排帧动画，pumpAndSettle 只收敛路由转场，不会挂。
    final pending = Completer<ReportData>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        healthApiProvider.overrideWithValue(StubHealthApi()),
        weekReportProvider.overrideWith((ref) => pending.future),
      ],
      child: const MaterialApp(home: ReportScreen()),
    ));
    await tester.pumpAndSettle();

    // 卡框 + 静态标题可见（对齐 H5 加载期形态）
    expect(find.text('每日热量 · 对比目标'), findsOneWidget);
    expect(find.byKey(const ValueKey('week-chart-skeleton')), findsOneWidget);
    // 数据位仍为空：日均文案 / 目标线标签 / 柱都不在树里
    expect(find.text(avgText), findsNothing);
    expect(find.text('目标 $target'), findsNothing);
    expect(find.byKey(const ValueKey('week-bar-0')), findsNothing);
  });

  testWidgets('错误态：ApiException.message + 重试；invalidate 后重新取数成功', (tester) async {
    final api = StubHealthApi(weekError: ApiException('登录已过期，请重新登录'));
    await tester.pumpWidget(harness(api));
    // 定步 pump（Duration.zero 不推进时钟）替代 pumpAndSettle：
    // pumpAndSettle 每轮推进 100ms 时钟，会踩中 Riverpod 3 默认失败退避
    // 重试（200ms 起）令 weekCalls 不定；桩 Future 同轮微任务即完成，
    // 两帧内必达错误态。
    await tester.pump(); // 微任务里 getWeekReport 抛 → provider 置错
    await tester.pump(); // 错误态 rebuild

    expect(find.text('登录已过期，请重新登录'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text(avgText), findsNothing);

    api.weekError = null;
    api.weekReport = kWeek;
    await tester.tap(find.text('重试'));
    await tester.pump(); // invalidate → loading（静态骨架卡）
    await tester.pump(); // 微任务成功 → 数据态首帧（柱已进树，高自动画）
    await tester.pump();

    expect(find.text('登录已过期，请重新登录'), findsNothing);
    expect(find.text(avgText), findsOneWidget);
    expect(find.byKey(const ValueKey('week-bar-0')), findsOneWidget);
    expect(api.weekCalls, 2); // 确实重发请求，非缓存翻牌
  });
}

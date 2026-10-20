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
      child: const MaterialApp(home: Scaffold(body: ReportScreen())), // M8-① 报告页含 WeightLogCard(TextField)，需 Material 祖先（生产由 Shell Scaffold 提供）
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
    // T8 缓办 D①：.week-chart 底部轴线（screens.css:407 border-bottom 1px hairline）
    expect(find.byKey(const ValueKey('week-chart-axis')), findsOneWidget);

    final todayIdx = weekTodayIndex(DateTime.now());
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(ValueKey('week-bar-$i')), findsOneWidget, reason: '柱 $i');
    }
    expect(find.text('今天'), findsOneWidget); // app.js:799 今天柱标签
    for (var i = 0; i < 7; i++) {
      if (i == todayIdx) continue;
      expect(find.text(days[i]), findsOneWidget);
    }

    // 终审 Important-1：轴线落在**日期标签之下**（H5 .week-chart 的
    // border-bottom 在 140 容器最底沿，而 .lbl 在 .col 内部，app.js:796-800
    // → 浏览器里日期标签盖在轴线上方），不是柱区与标签之间。
    final axisTop =
        tester.getRect(find.byKey(const ValueKey('week-chart-axis'))).top;
    final barBottom = tester
        .getRect(find.byKey(const ValueKey('week-bar-fill-0')))
        .bottom;
    expect(axisTop, greaterThan(barBottom)); // 轴线在柱区之下
    for (var i = 0; i < 7; i++) {
      expect(
          tester
              .getRect(find.text(i == todayIdx ? '今天' : days[i]))
              .bottom,
          lessThanOrEqualTo(axisTop),
          reason: '轴线应在标签 $i 之下');
    }
  });

  testWidgets('几何与配色：0 kcal 柱 min 4% 高、over=warnSoft、正常=primarySoft（app.js:797-798 / screens.css:414-433）',
      (tester) async {
    await pumpReport(tester, StubHealthApi(weekReport: kWeek));

    // min 4%：0 kcal 柱高 = 140*.04 = 5.6px（不是 0）。
    // 🔴 M10 卫生修复（**改动前既有缺陷，非本批引入**）：原写死 index 2，而
    // weekTodayIndex=weekday-1（周一=0，report.dart:142），**每逢周三 todayIdx==2**
    // 即撞上今天柱——_barDecoration 今天支返回 LinearGradient（color 恒 null，
    // week_chart.dart:161-174），本断言必红。M9 收官日 09-27 是周日，故当时全绿。
    // 零 kcal 柱有 2/5 两根，按下方 normalIdx 同款守卫择「非今天」者，与运行日无关。
    final zeroIdx =
        [2, 5].firstWhere((i) => i != weekTodayIndex(DateTime.now()));
    final zeroBar = tester
        .widget<Container>(find.byKey(ValueKey('week-bar-fill-$zeroIdx')))
        .decoration! as BoxDecoration;
    expect(tester.getSize(find.byKey(ValueKey('week-bar-fill-$zeroIdx'))).height,
        closeTo(expectBarPx(zeroIdx), 0.5));
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
      child: const MaterialApp(home: Scaffold(body: ReportScreen())), // M8-① 报告页含 WeightLogCard(TextField)，需 Material 祖先（生产由 Shell Scaffold 提供）
    ));
    await tester.pumpAndSettle();

    // 卡框 + 静态标题可见（对齐 H5 加载期形态）
    expect(find.text('每日热量 · 对比目标'), findsOneWidget);
    expect(find.byKey(const ValueKey('week-chart-skeleton')), findsOneWidget);
    // 终审 Important-1 延伸 + T8 缓办（骨架线无 key 无断言）：加载期
    // .week-chart 的 border-bottom 本就可见，且落点同样在标签占位之后
    expect(find.byKey(const ValueKey('week-chart-axis-skeleton')),
        findsOneWidget);
    expect(
        tester
            .getRect(find.byKey(const ValueKey('week-chart-axis-skeleton')))
            .top,
        greaterThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('week-chart-skeleton'))).bottom -
                0.5));
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

  /* ================= M3 Task 5：月视图 + 达标统计卡 + 期间建议卡 ================= */

  // 月桩默认体（stub monthReportMap）：weeks W1..W4、kcal [1652,1723,0,1688]、
  // days 19、rates 78/69/73。月均口径 = 对**周日均数组**再算有记录均值
  // （app.js:271-273 与 renderWeekReport:802-803 同一公式）：
  // round((1652+1723+1688)/3) = round(1687.66…) = 1688。
  const monthAvgText = '月均 1688 kcal · 记 19 天';
  // 周建议（carb 86 / protein 72 / fat 64，日均 1599 ≤ 1679 且 > 0.7×1679）：
  // 仅蛋白规则触发（app.js:835）。
  const weekAdvice = '蛋白质达标率 72%，偏低，每餐加一份鱼、虾、蛋或豆制品。';
  // 月建议：蛋白 69<80 + 日均 1688 超目标 1679（app.js:839 分支）。
  const monthAdvice =
      '蛋白质达标率 69%，偏低，每餐加一份鱼、虾、蛋或豆制品；'
      '日均 1688 kcal 超目标 1679 kcal，想控重每日减 9 kcal 左右。';

  Future<void> switchToMonth(WidgetTester tester) async {
    await tester.tap(find.text('月')); // index.html:154 segmented data-range=month
    await tester.pumpAndSettle(); // 月柱 700ms 入场动画收敛
  }

  testWidgets('切月：柱标签 W1..W4、月均文案、无今天高亮（app.js:268-274,793）',
      (tester) async {
    final api = StubHealthApi(weekReport: kWeek);
    await pumpReport(tester, api);
    await switchToMonth(tester);

    // 标题行 #report-avg 换成月均文案，周日均文案消失
    expect(find.text(monthAvgText), findsOneWidget);
    expect(find.text(avgText), findsNothing);

    // 柱按 labels.length 动态：4 周桩 → 4 根，无第 5 根
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('week-bar-$i')), findsOneWidget, reason: '柱 $i');
    }
    expect(find.byKey(const ValueKey('week-bar-4')), findsNothing);

    // 标签行 = weeks 数组；周标签与"今天"全部消失（todayIndex=-1）
    for (final w in ['W1', 'W2', 'W3', 'W4']) {
      expect(find.text(w), findsOneWidget, reason: '标签 $w');
    }
    expect(find.text('今天'), findsNothing);
    expect(find.text('三'), findsNothing);

    // 柱 0（1652 ≤ 1679 非 over）若是"今天"会变渐变——纯色 primarySoft
    // 即证明 todayIndex=-1（周一跑也不误判，不依赖真实星期几）
    final bar0 = tester
        .widget<Container>(find.byKey(const ValueKey('week-bar-fill-0')))
        .decoration! as BoxDecoration;
    expect(bar0.color, Tokens.primarySoft);
    expect(bar0.gradient, isNull);
    expect(api.monthCalls, 1); // 切月确实拉了月报
  });

  testWidgets('月视图动态周数：31 天月 5 周样本 → 5 根柱 + W5（不写死 4）',
      (tester) async {
    final api = StubHealthApi(weekReport: kWeek, monthReport:
        StubHealthApi.monthReportMap(
      weeks: const ['W1', 'W2', 'W3', 'W4', 'W5'],
      kcal: const [1600, 1700, 1500, 1650, 0], // 5 条，末周未记录
      days: 26,
      total: 6450,
    ));
    await pumpReport(tester, api);
    await switchToMonth(tester);

    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('week-bar-$i')), findsOneWidget, reason: '柱 $i');
    }
    expect(find.text('W5'), findsOneWidget);
    // round((1600+1700+1500+1650)/4) = round(1612.5) = 1613（jsRound 半值进位）
    expect(find.text('月均 1613 kcal · 记 26 天'), findsOneWidget);
  });

  testWidgets('建议卡：标题与正文随 周/月 切换（app.js:817-818）', (tester) async {
    final api = StubHealthApi(weekReport: kWeek);
    await pumpReport(tester, api);

    expect(find.text('本周建议'), findsOneWidget);
    expect(find.text(weekAdvice), findsOneWidget);

    await switchToMonth(tester);
    expect(find.text('本月建议'), findsOneWidget);
    expect(find.text('本周建议'), findsNothing);
    expect(find.text(monthAdvice), findsOneWidget);
    expect(find.text(weekAdvice), findsNothing);
  });

  testWidgets('达标统计卡：三张 label + rate% + 进度条宽 rate%（app.js:806-815）',
      (tester) async {
    final api = StubHealthApi(weekReport: kWeek); // rates 86/72/64
    await pumpReport(tester, api);

    final cases = {
      'carb': ['碳水达标', '86', 86, Tokens.nutCarb],
      'protein': ['蛋白达标', '72', 72, Tokens.nutProtein],
      'fat': ['脂肪控制', '64', 64, Tokens.nutFat],
    };
    for (final e in cases.entries) {
      final key = e.key, v = e.value;
      final card = find.byKey(ValueKey('stat-card-$key'));
      expect(card, findsOneWidget, reason: 'stat-card-$key');
      expect(find.descendant(of: card, matching: find.text(v[0] as String)),
          findsOneWidget,
          reason: '${v[0]} label'); // .label
      expect(find.descendant(of: card, matching: find.text(v[1] as String)),
          findsOneWidget,
          reason: '${v[1]} num'); // .num（rate 与 ' %' 分列，components.css:192-193）

      // fill 宽 / track 宽 ≈ rate%（width:${rate}%），色走 Tokens
      final track = find.byKey(ValueKey('stat-track-$key'));
      final fill = find.byKey(ValueKey('stat-fill-$key'));
      expect(tester.getSize(fill).width / tester.getSize(track).width,
          closeTo((v[2] as int) / 100, 0.02),
          reason: '$key fill 宽 ${v[2]}%');
      expect(
          (tester.widget<Container>(fill).decoration! as BoxDecoration).color,
          v[3],
          reason: '$key 色');
      expect(
          (tester.widget<Container>(track).decoration! as BoxDecoration).color,
          Tokens.surfaceSoft,
          reason: '$key 轨底色 surface-soft');
    }

    // 切月后统计卡跟着月报 rates 78/69/73 走
    await switchToMonth(tester);
    expect(find.text('78'), findsOneWidget);
    expect(find.text('69'), findsOneWidget);
    expect(find.text('73'), findsOneWidget);
    final fillCarb = find.byKey(const ValueKey('stat-fill-carb'));
    final trackCarb = find.byKey(const ValueKey('stat-track-carb'));
    expect(tester.getSize(fillCarb).width / tester.getSize(trackCarb).width,
        closeTo(0.78, 0.02));
  });

  testWidgets('加载态：统计卡/建议卡静态骨架补齐，数据位为空（index.html:163-165）',
      (tester) async {
    final pending = Completer<ReportData>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        healthApiProvider.overrideWithValue(StubHealthApi()),
        weekReportProvider.overrideWith((ref) => pending.future),
      ],
      child: const MaterialApp(home: Scaffold(body: ReportScreen())), // M8-① 报告页含 WeightLogCard(TextField)，需 Material 祖先（生产由 Shell Scaffold 提供）
    ));
    await tester.pumpAndSettle();

    // 三张 stat-card 框 + 建议卡标题（HTML 静态部分）可见
    for (final key in ['carb', 'protein', 'fat']) {
      expect(find.byKey(ValueKey('stat-card-$key')), findsOneWidget,
          reason: '骨架 stat-card-$key');
    }
    expect(find.text('本周建议'), findsOneWidget); // #advice-title 静态初值
    // 数据位为空：label/rate/建议正文都不在树里
    expect(find.text('碳水达标'), findsNothing);
    expect(find.text(weekAdvice), findsNothing);
    expect(find.text('86'), findsNothing);
  });

  testWidgets('月视图错误态：报后端 message + 重试重新取月报', (tester) async {
    final api = StubHealthApi(
        weekReport: kWeek, monthError: ApiException('月报加载失败'));
    await pumpReport(tester, api);

    await tester.tap(find.text('月'));
    // 定步 pump 不推进时钟 → 不踩 Riverpod 3 失败退避重试（同周错误态用例）
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('月报加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text(monthAvgText), findsNothing);

    api.monthError = null;
    await tester.tap(find.text('重试'));
    await tester.pump(); // invalidate → loading 骨架
    await tester.pump(); // 微任务成功 → 数据态
    await tester.pump();

    expect(find.text('月报加载失败'), findsNothing);
    expect(find.text(monthAvgText), findsOneWidget);
    expect(find.text('本月建议'), findsOneWidget);
    expect(api.monthCalls, 2); // 重试打的是月报，不是周报
    expect(api.weekCalls, 1);
  });
}

// ShiguangFlutter/test/m9_t6_stagger_wiring_test.dart
// M9-T6 接线钉：Stagger 落到首页/报告页后的「错峰序位」行为面。
// 钉的不是像素观感（目检归 T10），而是接线本身：
// ① 首页卡序 delay 递增——盘子卡(index1，delay 40ms)先于建议卡
//    (index2，delay 80ms)起播；t=70ms 采样点必须 盘子>0 且 建议==0。
// ② 报告页加载支（静态骨架卡框）同样错峰——热量骨架卡(index0)在播时
//    统计骨架(index1，delay 40ms)尚未起播；settle 后全部到位=1。
// 时序依据 stagger.dart：Timer(40ms×index) + 220ms easeOutCubic；
// 采样帧 = pumpWidget(t=0 建 State/挂定时器) → pump(60) → pump(10)=t70。
// （forward 后首帧 elapsed=0，故需 delay 之后第二帧值才 >0。）
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/domain/report.dart';
import 'package:shiguang_flutter/features/common/stagger.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/home/home_screen.dart';
import 'package:shiguang_flutter/features/report/report_controller.dart'
    show weekReportProvider;
import 'package:shiguang_flutter/features/report/report_screen.dart';

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

/// 指定 index 的 Stagger 内层 FadeTransition 当前 opacity。
/// .first：Stagger 本体 build 的根即其 FadeTransition，深度序首个=本体；
/// WeightLogCard 等子树内部另有 FadeTransition（同步态动画），取首避免
/// 「Too many elements」（也是唯一正确的本体）。
double staggerOpacity(WidgetTester tester, int index) {
  final stagger = find.byWidgetPredicate(
    (w) => w is Stagger && w.index == index,
  );
  expect(stagger, findsOneWidget, reason: 'index=$index 的 Stagger 应恰有一处');
  final fade =
      find
              .descendant(of: stagger, matching: find.byType(FadeTransition))
              .evaluate()
              .first
              .widget
          as FadeTransition;
  return fade.opacity.value;
}

void main() {
  testWidgets('首页接线钉：盘子卡(1)与建议卡(2) delay 序位——t=70ms 盘子已起播、建议未到点；settle 后双 1', (
    tester,
  ) async {
    final api = StubHealthApi(
      summary: StubHealthApi.summaryMap(
        kcal: 712,
        target: 1679,
        carb: 60,
        protein: 45,
        fat: 30,
        water: 3,
      ),
    );
    await useBigSurface(tester);
    final container = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null, // 同 home_screen_test 定式：禁退避重试
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: shiguangTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60)); // t=60：0/1 号 timer 到点
    await tester.pump(const Duration(milliseconds: 10)); // t=70：1 号第二帧值>0

    expect(staggerOpacity(tester, 1), greaterThan(0.0)); // 盘子卡已在播
    expect(staggerOpacity(tester, 2), 0.0); // 建议卡（delay 80ms）未到点

    await tester.pumpAndSettle();
    expect(staggerOpacity(tester, 1), 1.0);
    expect(staggerOpacity(tester, 2), 1.0);
  });

  testWidgets('报告页接线钉：加载支骨架卡错峰——index0 在播时 index1 未到点；settle 后到位', (
    tester,
  ) async {
    final pending = Completer<ReportData>(); // 钉死加载支（同既有加载态用例）
    await useBigSurface(tester); // WeightLogCard(index4) 在末位，默认视口下落缓存区外
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthApiProvider.overrideWithValue(StubHealthApi()),
          weekReportProvider.overrideWith((ref) => pending.future),
        ],
        child: const MaterialApp(home: Scaffold(body: ReportScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10)); // index0 timer(0ms) 到点
    await tester.pump(
      const Duration(milliseconds: 10),
    ); // t=20：index0 值>0；index1(40ms) 未到

    expect(staggerOpacity(tester, 0), greaterThan(0.0));
    expect(staggerOpacity(tester, 1), 0.0);

    await tester.pumpAndSettle(); // 骨架支无持续帧：收敛=全部入场完成
    expect(staggerOpacity(tester, 0), 1.0);
    expect(staggerOpacity(tester, 1), 1.0);
    expect(staggerOpacity(tester, 2), 1.0);
    expect(staggerOpacity(tester, 3), 1.0);
    expect(staggerOpacity(tester, 4), 1.0);
  });
}

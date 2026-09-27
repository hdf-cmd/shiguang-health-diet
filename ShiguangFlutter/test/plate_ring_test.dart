// ShiguangFlutter/test/plate_ring_test.dart
// M3 Task 7：首页营养餐盘环（双环 CustomPainter + 600ms 进度/500ms 数字滚动）
// + 首页加载/空态区分（M2 终审 Minor M1 核销）。
// H5 事实源：js/app.js:296-344 renderRing、js/app.js:380-387 animateNum、
// index.html:77-104（餐盘卡结构/文案）、css/screens.css:151-166（几何）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart';
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/features/home/home_controller.dart';
import 'package:shiguang_flutter/features/home/home_screen.dart';
import 'package:shiguang_flutter/features/home/plate_ring.dart';

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

Widget ringHarness(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

Widget homeHarness(StubHealthApi api) => ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      child: const MaterialApp(home: HomeScreen()),
    );

/// 环中心数字（key 锚定，避免与 aside 数字串扰）
String ringNum(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('ring-num')))
    .data!;

void main() {
  /* ---------- 纯计算：外环扫角（app.js:314 pct=min(1, kcal/budget)） ---------- */
  group('ringSweep', () {
    test('kcal=0 → 0（空环）', () => expect(ringSweep(0, 1679), 0));
    test('半程 → 0.5', () => expect(ringSweep(800, 1600), closeTo(0.5, 1e-12)));
    test('超预算封顶 1（min(1,…)）', () {
      expect(ringSweep(9999, 1679), 1);
      expect(ringSweep(1679, 1679), 1); // 恰好等于也满环（pct=1，色仍 primary）
    });
    test('budget=0 防除零（锁定语义：kcal=0→0，kcal>0→1）', () {
      // H5 推演：0/0=NaN → dashoffset 无效样式保持初始满 offset=扫角0；
      // kcal>0 时 x/0=Infinity → min(1,∞)=1 满环。两者都非崩溃路径。
      expect(ringSweep(0, 0), 0);
      expect(ringSweep(500, 0), 1);
    });
  });

  /* ---------- 纯计算：内环三段占比（app.js:326-331，顺序 carb→protein→fat） ---------- */
  group('macroFractions', () {
    test('归一化且顺序不得换：[carb, protein, fat]', () {
      expect(
        macroFractions(60, 45, 30),
        [closeTo(60 / 135, 1e-12), closeTo(45 / 135, 1e-12), closeTo(30 / 135, 1e-12)],
      );
    });
    test('全 0 → 分母按 1（app.js:326 `|| 1`）三段皆 0', () {
      expect(macroFractions(0, 0, 0), [0, 0, 0]);
    });
    test('单一宏量 → 该段为 1', () {
      expect(macroFractions(100, 0, 0), [1, 0, 0]);
    });
  });

  /* ---------- 纯计算：内环三段色序锁（T8 缓办 C：此前调换色序全测试仍绿） ---------- */
  test('plateRingSegColors = [nutCarb, nutProtein, nutFat]，与 macroFractions 返回顺序一一对应', () {
    expect(plateRingSegColors,
        const [Tokens.nutCarb, Tokens.nutProtein, Tokens.nutFat]);
    // 三色两两互异：调换任意两色本断言必红（macroFractions 文档顺序
    // [carb, protein, fat] ⇔ segColors 下标 0/1/2 配对，painter 逐 i 取色）
    expect(plateRingSegColors.toSet(), hasLength(3));
  });

  /* ---------- 纯计算：超预算色（app.js:323 `kcal > budget ? warn : primary`） ---------- */
  group('ringProgressColor', () {
    test('kcal > budget → warn', () {
      expect(ringProgressColor(1680, 1679), Tokens.warn);
      expect(ringProgressColor(500, 0), Tokens.warn); // 零预算有摄入即超
    });
    test('kcal == budget → primary（严格大于才变色）', () {
      expect(ringProgressColor(1679, 1679), Tokens.primary);
    });
    test('kcal < budget → primary', () {
      expect(ringProgressColor(712, 1679), Tokens.primary);
      expect(ringProgressColor(0, 0), Tokens.primary);
    });
  });

  /* ---------- PlateRing widget ---------- */
  group('PlateRing', () {
    testWidgets('pumpAndSettle 后中心数字 = max(0, budget-kcal)，单位行逐字', (tester) async {
      await tester.pumpWidget(ringHarness(const PlateRing(
          kcal: 712, target: 1679, carb: 60, protein: 45, fat: 30)));
      await tester.pumpAndSettle();
      expect(ringNum(tester), '967'); // 1679(=target+0 运动额度) - 712
      expect(find.text('还可摄入 kcal'), findsOneWidget); // index.html:92-94 逐字
    });

    testWidgets('超预算：中心数字下限 0，环不崩', (tester) async {
      await tester.pumpWidget(ringHarness(const PlateRing(
          kcal: 2000, target: 1679, carb: 150, protein: 90, fat: 60)));
      await tester.pumpAndSettle();
      expect(ringNum(tester), '0'); // max(0, 1679-2000)
      expect(tester.takeException(), isNull);
    });

    testWidgets('内环三段（有宏量）渲染无异常；全 0 宏量同样安全', (tester) async {
      await tester.pumpWidget(ringHarness(const PlateRing(
          kcal: 712, target: 1679, carb: 60, protein: 45, fat: 30)));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(ringHarness(const PlateRing(
          kcal: 0, target: 1679, carb: 0, protein: 0, fat: 0)));
      await tester.pumpAndSettle();
      expect(ringNum(tester), '1679');
      expect(tester.takeException(), isNull);
    });
  });

  /* ---------- HomeScreen 接线：加载/零值区分 + aside/note 文案 ---------- */
  group('HomeScreen 餐盘卡', () {
    testWidgets('加载期：环位显静态骨架、三餐卡退役（不显数字、不显"未记录"），与全空态可分辨',
        (tester) async {
      final api = StubHealthApi(
        summary: StubHealthApi.summaryMap(kcal: 712, target: 1679, carb: 60, protein: 45, fat: 30),
        summaryGate: Completer<void>(),
        recordsGate: Completer<void>(),
      );
      await tester.pumpWidget(homeHarness(api));
      await tester.pump(); // 定步 pump：加载期若有持续动画不死等（本实现为静态骨架，无帧）

      expect(find.byKey(const ValueKey('plate-ring-skeleton')), findsOneWidget);
      expect(find.byKey(const ValueKey('meal-skeleton')),
          findsNothing); // M8-②：三餐卡整卡删除，骨架位不复存在
      expect(find.text('还可摄入 kcal'), findsNothing);
      expect(find.textContaining('已摄入 712'), findsNothing);
      expect(find.text('未记录'), findsNothing); // 加载期不得伪装成全空态
      expect(find.textContaining('—'), findsWidgets); // aside 占位横线

      api.summaryGate!.complete();
      api.recordsGate!.complete();
      await tester.pumpAndSettle(); // 环/数字动画终态确定，可 settle
      expect(find.byKey(const ValueKey('plate-ring-skeleton')), findsNothing);
      expect(ringNum(tester), '967');
    });

    testWidgets('aside 三行 + note/nutrient-note 逐字（app.js:302-311，ex==0 分支）',
        (tester) async {
      final api = StubHealthApi(
        summary: StubHealthApi.summaryMap(kcal: 712, target: 1679, carb: 60, protein: 45, fat: 30),
      );
      await tester.pumpWidget(homeHarness(api));
      await tester.pumpAndSettle();

      expect(find.textContaining('今日额度 1679 kcal'), findsOneWidget);
      expect(find.textContaining('已摄入 712 kcal'), findsOneWidget);
      expect(find.textContaining('运动消耗 0 kcal'), findsOneWidget); // ex 恒 0（M4+ 启用）
      // app.js:308 逐字
      expect(find.text('基准目标 1679 kcal · 记运动后额度自动上调'), findsOneWidget);
      // app.js:311 逐字（nutrient-note 在 index.html:103 餐盘卡内 → 逐字搬）
      expect(
        find.text('营养素目标 = 基准 1679 × 供能比 50%/25%/25% ÷ (4/4/9) kcal，'
            '不含运动额度；热量额度含运动，两者基数不同'),
        findsOneWidget,
      );
    });

    testWidgets('加载完成且无记录：显真实零值（已摄入 0、环中心=预算；M8-② 三餐卡不在场）',
        (tester) async {
      // M6-T5 注：AdviceCard 落位后默认 800×600 视口把三餐卡推出 ListView
      // 缓存区（harness.dart 注②病症）→ 撑大视口
      await useBigSurface(tester);
      final api = StubHealthApi(summary: StubHealthApi.summaryMap(target: 1679));
      await tester.pumpWidget(homeHarness(api));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('plate-ring-skeleton')), findsNothing);
      expect(ringNum(tester), '1679'); // 全零摄入 → 还可摄入 = budget
      expect(find.textContaining('已摄入 0 kcal'), findsOneWidget);
      expect(find.text('未记录'),
          findsNothing); // M8-②：三餐「未记录」行随卡退役
    });

    testWidgets('error 分支沿用重试行（回归锚：错误优先于骨架）', (tester) async {
      final api = StubHealthApi(
        summaryError: ApiException('登录已过期，请重新登录'),
        recordsError: ApiException('登录已过期，请重新登录'),
      );
      await tester.pumpWidget(homeHarness(api));
      await tester.pumpAndSettle();
      expect(find.text('登录已过期，请重新登录'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.byKey(const ValueKey('plate-ring-skeleton')), findsNothing);
    });
  });
}
